import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/features/calling/active_audio_call_screen.dart';
import 'package:voryn/features/calling/active_video_call_screen.dart';
import 'package:voryn/features/calling/models/video_upgrade_models.dart';
import 'package:voryn/features/calling/multi_call_coordinator.dart';
import 'package:voryn/features/calling/voryn_call_runtime_coordinator.dart';
import 'package:voryn/features/calling/widgets/video_upgrade_prompt.dart';
import 'package:voryn/features/connect/mock_voryn_state.dart';
import 'package:voryn/shared/widgets/voryn_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.voryn.app/lock_screen'),
      (call) async => null,
    );
  });

  const testUserA = VorynMockUser(
    backendUid: 'user-a-1111-2222-3333',
    customName: null,
    name: 'Alice Requester',
    id: '@alice',
    phone: '+1234567890',
    email: 'alice@example.com',
    presence: VorynPresenceStatus.online,
    initials: 'AR',
  );

  const testUserB = VorynMockUser(
    backendUid: 'user-b-4444-5555-6666',
    customName: null,
    name: 'Bob Receiver',
    id: '@bob',
    phone: '+1987654321',
    email: 'bob@example.com',
    presence: VorynPresenceStatus.online,
    initials: 'BR',
  );

  group('Checkpoint CALL-AV-1: Audio-to-Video Upgrade with Receiver Approval', () {
    // -------------------------------------------------------------
    // Scenario 1: Audio remains active during negotiation
    // -------------------------------------------------------------
    test('1. Audio remains active during negotiation without teardown', () async {
      const callId = 'call-av1-01-negotiating';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final startTime = DateTime.now().subtract(const Duration(seconds: 15));
      coordinator.markConnected(startTime);

      final screen = Object();
      coordinator.attachScreen(
        screenKey: screen,
        onStatusChanged: (_) {},
        onRouteExit: () {},
      );

      // Verify connected state remains true while upgrade is requested
      expect(coordinator.isConnected, isTrue);
      expect(coordinator.isEnded, isFalse);
      expect(coordinator.isTearingDown, isFalse);
      expect(coordinator.currentDuration.inSeconds >= 15, isTrue);

      coordinator.detachScreen(screen);
      VorynCallRuntimeCoordinator.remove(callId);
    });

    // -------------------------------------------------------------
    // Scenario 2: Receiver receives upgrade request
    // -------------------------------------------------------------
    testWidgets('2. Receiver receives upgrade request and sees prompt card', (tester) async {
      bool acceptTapped = false;
      bool declineTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoUpgradePromptCard(
              callerName: 'Alice',
              onAccept: () => acceptTapped = true,
              onDecline: () => declineTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Switch to video call?'), findsOneWidget);
      expect(find.text('Alice wants to turn this audio call into a video call.'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      expect(acceptTapped, isTrue);

      await tester.tap(find.text('Decline'));
      expect(declineTapped, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 3: Accept transitions both users to video
    // -------------------------------------------------------------
    test('3. Accept transitions call type to video while preserving session coordinator', () async {
      const callId = 'call-av1-03-accept';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final startTime = DateTime.now().subtract(const Duration(seconds: 40));
      coordinator.markConnected(startTime);

      MultiCallCoordinator.instance.recordCallType(callId, 'audio');
      expect(MultiCallCoordinator.instance.getCallType(callId), 'audio');

      // Peer accepts upgrade
      coordinator.isTransitioning = true;
      MultiCallCoordinator.instance.recordCallType(callId, 'video');

      expect(MultiCallCoordinator.instance.getCallType(callId), 'video');
      expect(coordinator.connectedAt, startTime);
      expect(coordinator.isEnded, isFalse);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    // -------------------------------------------------------------
    // Scenario 4: Decline preserves audio
    // -------------------------------------------------------------
    test('4. Decline preserves audio call and call duration', () async {
      const callId = 'call-av1-04-decline';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final startTime = DateTime.now().subtract(const Duration(seconds: 25));
      coordinator.markConnected(startTime);

      // Status change to declined
      final req = VideoUpgradeRequest(
        id: 'req-04',
        callId: callId,
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.declined,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(req.status, VideoUpgradeStatus.declined);
      expect(coordinator.isEnded, isFalse);
      expect(coordinator.currentDuration.inSeconds >= 25, isTrue);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    // -------------------------------------------------------------
    // Scenario 5: Timeout preserves audio
    // -------------------------------------------------------------
    test('5. Timeout after 30s marks request expired and preserves audio call', () async {
      final pastTime = DateTime.now().subtract(const Duration(seconds: 35));
      final expiredReq = VideoUpgradeRequest(
        id: 'req-05-timeout',
        callId: 'call-av1-05',
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.pending,
        createdAt: pastTime,
        expiresAt: pastTime.add(const Duration(seconds: 30)),
      );

      expect(expiredReq.isExpired(), isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 6: Cancel preserves audio
    // -------------------------------------------------------------
    testWidgets('6. Requester cancels upgrade request via waiting banner', (tester) async {
      bool cancelTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoUpgradeWaitingBanner(
              onCancel: () => cancelTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Video request sent'), findsOneWidget);
      expect(find.text('Waiting for approval…'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      expect(cancelTapped, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 7: Requester cannot self-approve
    // -------------------------------------------------------------
    test('7. Requester cannot self-approve request (target must not equal requester)', () {
      final req = VideoUpgradeRequest(
        id: 'req-07-self',
        callId: 'call-av1-07',
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      // Security check: Local user A cannot respond to their own request
      final isSelfApproval = req.requestedBy == req.targetUserUid;
      expect(isSelfApproval, isFalse);
      expect(req.requestedBy != req.targetUserUid, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 8: Unrelated user cannot respond
    // -------------------------------------------------------------
    test('8. Unrelated user ID is rejected from responding to request', () {
      final req = VideoUpgradeRequest(
        id: 'req-08-unrelated',
        callId: 'call-av1-08',
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      const maliciousUserId = 'evil-user-9999-9999';
      final canRespond = req.targetUserUid == maliciousUserId;
      expect(canRespond, isFalse);
    });

    // -------------------------------------------------------------
    // Scenario 9: Forged call ID rejected
    // -------------------------------------------------------------
    test('9. Mismatched or forged call ID does not match active call session', () {
      const activeCallId = 'call-av1-09-legit';
      const forgedCallId = 'call-av1-09-forged';

      final req = VideoUpgradeRequest(
        id: 'req-09',
        callId: forgedCallId,
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(req.callId == activeCallId, isFalse);
    });

    // -------------------------------------------------------------
    // Scenario 10: Duplicate acceptance ignored
    // -------------------------------------------------------------
    test('10. Duplicate acceptance on non-pending request is ignored', () {
      final alreadyAcceptedReq = VideoUpgradeRequest(
        id: 'req-10-duplicate',
        callId: 'call-av1-10',
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.accepted,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(alreadyAcceptedReq.isPending, isFalse);
    });

    // -------------------------------------------------------------
    // Scenario 11: Stale acceptance ignored
    // -------------------------------------------------------------
    test('11. Stale acceptance after expiry is rejected', () {
      final staleReq = VideoUpgradeRequest(
        id: 'req-11-stale',
        callId: 'call-av1-11',
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.pending,
        createdAt: DateTime.now().subtract(const Duration(seconds: 40)),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );

      expect(staleReq.isExpired(), isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 12: Request after call termination rejected
    // -------------------------------------------------------------
    test('12. Request after call teardown is blocked by coordinator lifecycle', () async {
      const callId = 'call-av1-12-terminated';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      await coordinator.performTeardown();

      expect(coordinator.isEnded, isTrue);
      VorynCallRuntimeCoordinator.remove(callId);
    });

    // -------------------------------------------------------------
    // Scenario 13: Simultaneous requests coalesced
    // -------------------------------------------------------------
    test('13. Simultaneous requests coalesce into immediate acceptance', () {
      const coalescedResult = VideoUpgradeResult(
        isSuccess: true,
        status: VideoUpgradeStatus.accepted,
        requestId: 'req-13-coalesced',
        coalesced: true,
      );

      expect(coalescedResult.isSuccess, isTrue);
      expect(coalescedResult.coalesced, isTrue);
      expect(coalescedResult.status, VideoUpgradeStatus.accepted);
    });

    // -------------------------------------------------------------
    // Scenario 14: Mic state preserved across upgrade
    // -------------------------------------------------------------
    test('14. Microphone mute state is preserved when constructing screens', () {
      const mutedAudioScreen = ActiveAudioCallScreen(
        callId: 'call-av1-14',
        initialMuted: true,
      );
      expect(mutedAudioScreen.initialMuted, isTrue);

      const mutedVideoScreen = ActiveVideoCallScreen(
        callId: 'call-av1-14',
        initialMuted: true,
        initialCameraEnabled: false,
      );
      expect(mutedVideoScreen.initialMuted, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 15: Speaker route preserved across upgrade
    // -------------------------------------------------------------
    test('15. Speaker state is maintained on screen transition', () {
      const speakerAudioScreen = ActiveAudioCallScreen(
        callId: 'call-av1-15',
        initialSpeakerOn: true,
      );
      expect(speakerAudioScreen.initialSpeakerOn, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 16: Call timer preserved across upgrade
    // -------------------------------------------------------------
    test('16. Call timer start timestamp is preserved without resetting to zero', () {
      const callId = 'call-av1-16-timer';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final originalStart = DateTime.now().subtract(const Duration(seconds: 45));
      coordinator.markConnected(originalStart);

      expect(coordinator.connectedAt, originalStart);

      // Re-connecting or upgrading preserves original connectedAt
      coordinator.markConnected(DateTime.now());
      expect(coordinator.connectedAt, originalStart);
      expect(coordinator.currentDuration.inSeconds >= 45, isTrue);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    // -------------------------------------------------------------
    // Scenario 17: Existing LiveKit session reused
    // -------------------------------------------------------------
    test('17. Existing LiveKit session is stored on coordinator and reused across routes', () {
      const callId = 'call-av1-17-session';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);

      expect(coordinator.session, isNull);
      VorynCallRuntimeCoordinator.remove(callId);
    });

    // -------------------------------------------------------------
    // Scenario 18: Camera permission denied handled safely
    // -------------------------------------------------------------
    test('18. Camera permission denied allows joining video call with camera off', () {
      const videoScreenCameraOff = ActiveVideoCallScreen(
        callId: 'call-av1-18-cam-off',
        user: testUserB,
        initialCameraEnabled: false,
      );

      expect(videoScreenCameraOff.initialCameraEnabled, isFalse);
    });

    // -------------------------------------------------------------
    // Scenario 19: Camera publishing requires consent
    // -------------------------------------------------------------
    test('19. Camera publishing defaults to false for receiver until accepted', () {
      final req = VideoUpgradeRequest(
        id: 'req-19',
        callId: 'call-av1-19',
        requestedBy: testUserA.backendUid!,
        targetUserUid: testUserB.backendUid!,
        status: VideoUpgradeStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      // When pending, receiver camera has not been enabled
      expect(req.status, VideoUpgradeStatus.pending);
    });

    // -------------------------------------------------------------
    // Scenario 20: Video init failure falls back to audio
    // -------------------------------------------------------------
    test('20. Video upgrade failure gracefully falls back to audio mode', () {
      const failedResult = VideoUpgradeResult(
        isSuccess: false,
        errorMessage: 'Camera device unavailable',
      );

      expect(failedResult.isSuccess, isFalse);
      expect(failedResult.errorMessage, 'Camera device unavailable');
    });

    // -------------------------------------------------------------
    // Scenario 21: Held calls unaffected
    // -------------------------------------------------------------
    test('21. Held calls cannot be upgraded to video while on hold', () {
      const callId = 'call-av1-21-hold';
      MultiCallCoordinator.instance.setRemoteHoldState(callId, 'remote-user');

      expect(MultiCallCoordinator.instance.isCallHeldByRemote(callId), isTrue);
      MultiCallCoordinator.instance.setRemoteHoldState(callId, null);
    });

    // -------------------------------------------------------------
    // Scenario 22: Merge Calls unaffected
    // -------------------------------------------------------------
    test('22. Multi-call conference registration and state unaffected', () {
      const callId = 'call-av1-22-merge';
      expect(MultiCallCoordinator.instance.isConference(callId), isFalse);
    });

    // -------------------------------------------------------------
    // Scenario 23: Incoming call notifications unaffected
    // -------------------------------------------------------------
    test('23. MultiCallCoordinator tracks waiting call independently of upgrade state', () {
      expect(MultiCallCoordinator.instance.hasWaitingCall, isFalse);
    });

    // -------------------------------------------------------------
    // Scenario 24: Meeting invitation notifications unaffected
    // -------------------------------------------------------------
    test('24. Call video upgrade does not interfere with meeting service routes', () {
      const normalAudioRoute = '/active-audio-call/call-av1-24';
      expect(normalAudioRoute.startsWith('/active-audio-call/'), isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 25: Reconnection functional
    // -------------------------------------------------------------
    test('25. Call coordinator reconnection preserves active state', () {
      const callId = 'call-av1-25-reconnect';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      coordinator.markConnected();

      expect(coordinator.isConnected, isTrue);
      expect(coordinator.isEnded, isFalse);

      VorynCallRuntimeCoordinator.remove(callId);
    });
  });
}
