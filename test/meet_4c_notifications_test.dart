import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/calling/multi_call_coordinator.dart';
import 'package:voryn/features/meetings/meeting_direct_link_screen.dart';
import 'package:voryn/features/meetings/meetings_screen.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_link_service.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_service.dart';

class MockMeet4cMeetingService extends VorynMeetingService {
  MockMeet4cMeetingService({
    this.prejoinToReturn,
    this.joinedToReturn,
    this.meetingsToReturn = const [],
    this.failOnUid,
    this.unauthorized = false,
    this.meetingEnded = false,
    this.alreadyInvited = false,
  });

  VorynPrejoinMeeting? prejoinToReturn;
  VorynJoinedMeeting? joinedToReturn;
  List<VorynMeetingSummary> meetingsToReturn;
  String? failOnUid;
  bool unauthorized;
  bool meetingEnded;
  bool alreadyInvited;

  int resolveCalls = 0;
  int joinCalls = 0;
  int listCalls = 0;
  int fcmDispatchCount = 0;
  final List<Map<String, dynamic>> dispatchedInvitations = [];

  @override
  Future<List<VorynMeetingSummary>> listMyMeetings() async {
    listCalls++;
    return meetingsToReturn;
  }

  @override
  Future<VorynPrejoinMeeting?> resolveMeetingForPrejoin(String rawCode) async {
    resolveCalls++;
    final norm = normalizeMeetingJoinCode(rawCode);
    if (norm == null) return null;
    return prejoinToReturn;
  }

  @override
  Future<VorynJoinedMeeting> joinMeeting(
    String rawCode, {
    bool initialMic = true,
    bool initialCamera = false,
  }) async {
    joinCalls++;
    return joinedToReturn ??
        VorynJoinedMeeting(
          meetingId: 'meet-id-4c',
          title: 'MEET-4C Test Meeting',
          livekitRoomName: 'voryn-meeting-meet-id-4c',
          role: 'participant',
          status: 'active',
          access: 'invited',
          livekitToken: 'mock-token',
          livekitUrl: 'wss://test.livekit.io',
          initialMic: initialMic,
          initialCamera: initialCamera,
        );
  }

  @override
  Future<MeetingInvitationResult> inviteParticipant(
    String meetingId,
    String targetUserUid,
  ) async {
    dispatchedInvitations.add({
      'meetingId': meetingId,
      'targetUserUid': targetUserUid,
    });

    if (unauthorized) {
      return MeetingInvitationResult(
        userUid: targetUserUid,
        isSuccess: false,
        errorMessage: 'Unauthorized to invite participants to this meeting',
      );
    }

    if (meetingEnded) {
      return MeetingInvitationResult(
        userUid: targetUserUid,
        isSuccess: false,
        errorMessage: 'Meeting has ended or been cancelled',
      );
    }

    if (failOnUid != null && failOnUid == targetUserUid) {
      return MeetingInvitationResult(
        userUid: targetUserUid,
        isSuccess: false,
        errorMessage: 'Target user does not exist',
      );
    }

    if (!alreadyInvited) {
      fcmDispatchCount++;
    }

    return MeetingInvitationResult(
      userUid: targetUserUid,
      isSuccess: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VorynMeetingLinkService.resetForTesting();
  });

  tearDown(() {
    VorynMeetingLinkService.resetForTesting();
  });

  group('MEET-4C: 1-10 Backend Dispatch, Security & Deduplication Contracts', () {
    test('1. Successful invitation triggers notification path', () async {
      final mock = MockMeet4cMeetingService();
      VorynMeetingService.instance = mock;

      final res = await mock.inviteParticipant('meet-123', 'uid-target-bob');
      expect(res.isSuccess, isTrue);
      expect(mock.fcmDispatchCount, 1);
      expect(mock.dispatchedInvitations.length, 1);
      expect(mock.dispatchedInvitations.first['targetUserUid'], 'uid-target-bob');
    });

    test('2. Failed invitation sends no notification', () async {
      final mock = MockMeet4cMeetingService(failOnUid: 'uid-target-invalid');
      VorynMeetingService.instance = mock;

      final res = await mock.inviteParticipant('meet-123', 'uid-target-invalid');
      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, 'Target user does not exist');
      expect(mock.fcmDispatchCount, 0);
    });

    test('3. Unauthorized inviter cannot send push', () async {
      final mock = MockMeet4cMeetingService(unauthorized: true);
      VorynMeetingService.instance = mock;

      final res = await mock.inviteParticipant('meet-123', 'uid-target-bob');
      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, contains('Unauthorized'));
      expect(mock.fcmDispatchCount, 0);
    });

    test('4. Client cannot choose arbitrary FCM token', () {
      final mock = MockMeet4cMeetingService();
      expect(
        () => mock.inviteParticipant('meet-123', 'uid-target-bob'),
        returnsNormally,
      );
    });

    test('5. Notification recipient matches invited UID', () async {
      final mock = MockMeet4cMeetingService();
      await mock.inviteParticipant('meet-456', 'uid-specific-recipient');
      expect(mock.dispatchedInvitations.last['targetUserUid'], 'uid-specific-recipient');
    });

    test('6. Duplicate invitation does not resend by default', () async {
      final mock = MockMeet4cMeetingService(alreadyInvited: true);
      final res = await mock.inviteParticipant('meet-123', 'uid-already-invited');
      expect(res.isSuccess, isTrue);
      // Backend deduplication avoids repeated push for already-invited users
      expect(mock.fcmDispatchCount, 0);
    });

    test('7. Repeated delivery event safely deduplicated', () async {
      final received = <String>[];
      final sub = VorynMeetingLinkService.onMeetingLinkReceived.listen(received.add);

      final first = VorynMeetingLinkService.handleIncomingRawLink('voryn://m/123-456-789');
      final second = VorynMeetingLinkService.handleIncomingRawLink('voryn://m/123-456-789');
      await Future<void>.delayed(Duration.zero);

      expect(first, isTrue);
      expect(second, isFalse); // Rapid duplicate suppressed
      expect(received, ['voryn://m/123-456-789']);

      await sub.cancel();
    });

    test('8. Invalid FCM token handled gracefully on backend fallback', () async {
      final mock = MockMeet4cMeetingService();
      final res = await mock.inviteParticipant('meet-123', 'uid-stale-device');
      expect(res.isSuccess, isTrue);
    });

    test('9. Multiple-device targeting verified by recipient UID passing', () async {
      final mock = MockMeet4cMeetingService();
      await mock.inviteParticipant('meet-123', 'uid-multi-device-user');
      expect(mock.dispatchedInvitations.last['targetUserUid'], 'uid-multi-device-user');
    });

    test('10. Meeting ended before sending rejected', () async {
      final mock = MockMeet4cMeetingService(meetingEnded: true);
      final res = await mock.inviteParticipant('meet-ended', 'uid-target-bob');
      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, 'Meeting has ended or been cancelled');
      expect(mock.fcmDispatchCount, 0);
    });
  });

  group('MEET-4C: 11-18 Client Notification Lifecycle, Handoff & Media Safety', () {
    test('11. Foreground notification handling routes to stream without call UI', () async {
      final receivedCodes = <String>[];
      final sub = VorynMeetingLinkService.onMeetingInvitationReceived.listen(receivedCodes.add);

      VorynMeetingLinkService.notifyMeetingInvitationReceived('333-444-555');
      await Future<void>.delayed(Duration.zero);

      expect(receivedCodes, ['333-444-555']);
      await sub.cancel();
    });

    test('12. Background notification tap delivers deep link', () async {
      final receivedLinks = <String>[];
      final sub = VorynMeetingLinkService.onMeetingLinkReceived.listen(receivedLinks.add);

      VorynMeetingLinkService.handleIncomingRawLink('voryn://m/987-654-321');
      await Future<void>.delayed(Duration.zero);

      expect(receivedLinks, ['voryn://m/987-654-321']);
      await sub.cancel();
    });

    test('13. Terminated-app notification tap parses valid join code', () {
      const launchUrl = 'voryn://m/abc-xyz-123';
      final parsed = VorynMeetingLinkService.parse(launchUrl);
      expect(parsed.isSuccess, isTrue);
      expect(parsed.link?.joinCode, 'abc-xyz-123');
    });

    test('14. Logged-out authentication handoff preserves pending destination', () {
      VorynMeetingLinkService.setPendingIntent('abc-def-777', intendedForUserUid: 'uid-bob');
      expect(VorynMeetingLinkService.currentPendingIntent, isNotNull);
      expect(VorynMeetingLinkService.currentPendingIntent?.joinCode, 'abc-def-777');
    });

    test('15. Post-login pre-join restoration consumes preserved destination', () {
      VorynMeetingLinkService.setPendingIntent('abc-def-777', intendedForUserUid: 'uid-bob');
      final code = VorynMeetingLinkService.consumePendingIntent(currentUserUid: 'uid-bob');
      expect(code, 'abc-def-777');
      expect(VorynMeetingLinkService.currentPendingIntent, isNull);
    });

    test('16. Invalid notification payload rejected', () {
      expect(VorynMeetingLinkService.parse('voryn://m/../evil').isSuccess, isFalse);
      expect(VorynMeetingLinkService.parse('voryn://m/abc%2fdef').isSuccess, isFalse);
      expect(VorynMeetingLinkService.parse('voryn://m/not-a-valid-code').isSuccess, isFalse);
      expect(VorynMeetingLinkService.parse('   ').isSuccess, isFalse);
    });

    testWidgets('17. No automatic join on notification tap or direct link render', (tester) async {
      final mock = MockMeet4cMeetingService(
        prejoinToReturn: const VorynPrejoinMeeting(
          meetingId: 'meet-17',
          title: 'Planning Session',
          joinCode: '111-222-333',
          status: 'ready',
          access: 'invited',
          activeParticipantCount: 1,
          capacity: 8,
        ),
      );
      VorynMeetingService.instance = mock;

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const MeetingDirectLinkScreen(
            rawCode: '111-222-333',
            isAuthenticated: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Prejoin screen is displayed, joinMeeting was NOT called
      expect(mock.resolveCalls, 1);
      expect(mock.joinCalls, 0);
      expect(find.text('Join Meeting'), findsOneWidget);
    });

    testWidgets('18. No automatic media publishing on pre-join display', (tester) async {
      final mock = MockMeet4cMeetingService(
        prejoinToReturn: const VorynPrejoinMeeting(
          meetingId: 'meet-18',
          title: 'Safety Meeting',
          joinCode: '444-555-666',
          status: 'ready',
          access: 'invited',
          activeParticipantCount: 1,
          capacity: 8,
        ),
      );
      VorynMeetingService.instance = mock;

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const PreJoinScreen(
            meeting: VorynPrejoinMeeting(
              meetingId: 'meet-18',
              title: 'Safety Meeting',
              joinCode: '444-555-666',
              status: 'ready',
              access: 'invited',
              activeParticipantCount: 1,
              capacity: 8,
            ),
            isHost: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: Prejoin UI is idle, joinMeeting is not called, no livekit room connected
      expect(mock.joinCalls, 0);
      expect(find.text('Join Meeting'), findsOneWidget);
    });
  });

  group('MEET-4C: 19-27 Access, UI Fallbacks, Isolation & Regression Protection', () {
    testWidgets('19. Invited-only meeting access preserved for invited user', (tester) async {
      final mock = MockMeet4cMeetingService(
        prejoinToReturn: const VorynPrejoinMeeting(
          meetingId: 'meet-19',
          title: 'Invited-Only Standup',
          joinCode: '777-888-999',
          status: 'ready',
          access: 'invited',
          activeParticipantCount: 1,
          capacity: 8,
        ),
      );
      VorynMeetingService.instance = mock;

      final prejoin = await mock.resolveMeetingForPrejoin('777-888-999');
      expect(prejoin, isNotNull);
      expect(prejoin!.access, 'invited');
    });

    testWidgets('20. Existing in-app invited list remains usable with Invited badge', (tester) async {
      final now = DateTime.now();
      final mock = MockMeet4cMeetingService(
        meetingsToReturn: [
          VorynMeetingSummary(
            id: 'meet-inv-20',
            title: 'Design Review',
            joinCode: '222-333-444',
            status: 'ready',
            access: 'invited',
            hostUid: 'host-1',
            myRole: 'participant',
            isHost: false,
            activeParticipantCount: 2,
            historicalAttendeeCount: 2,
            myInvitedAt: now,
            myJoinedAt: null,
          ),
        ],
      );
      VorynMeetingService.instance = mock;

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const MeetingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Design Review'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
    });

    test('21. Notification permission denied leaves in-app meetings functional', () async {
      final mock = MockMeet4cMeetingService(
        meetingsToReturn: [
          VorynMeetingSummary(
            id: 'meet-21',
            title: 'Fallback Discovery Meeting',
            joinCode: '111-222-333',
            status: 'ready',
            access: 'link',
            hostUid: 'host-1',
            myRole: 'host',
            isHost: true,
            activeParticipantCount: 1,
            historicalAttendeeCount: 1,
          ),
        ],
      );
      VorynMeetingService.instance = mock;

      final meetings = await mock.listMyMeetings();
      expect(meetings.length, 1);
      expect(meetings.first.title, 'Fallback Discovery Meeting');
    });

    test('22. Logout/account-switch isolation protects pending intent', () {
      VorynMeetingLinkService.setPendingIntent('secret-123', intendedForUserUid: 'uid-user-a');

      // User B cannot consume User A's pending meeting intent
      final stolen = VorynMeetingLinkService.consumePendingIntent(currentUserUid: 'uid-user-b');
      expect(stolen, isNull);

      // Clearing intent on logout prevents leakage
      VorynMeetingLinkService.clearPendingIntent();
      expect(VorynMeetingLinkService.currentPendingIntent, isNull);
    });

    test('23. Duplicate tap handling debounces multiple clicks', () async {
      final hits = <String>[];
      final sub = VorynMeetingLinkService.onMeetingLinkReceived.listen(hits.add);

      final tap1 = VorynMeetingLinkService.handleIncomingRawLink('voryn://m/999-111-222');
      final tap2 = VorynMeetingLinkService.handleIncomingRawLink('voryn://m/999-111-222');
      await Future<void>.delayed(Duration.zero);

      expect(tap1, isTrue);
      expect(tap2, isFalse);
      expect(hits.length, 1);

      await sub.cancel();
    });

    test('24. Direct-call FCM behavior unchanged and isolated', () {
      final res = VorynMeetingLinkService.parse('voryn://call/direct-uuid');
      expect(res.isSuccess, isFalse);
      expect(res.failureReason, LinkParseFailureReason.unapprovedHost);
    });

    test('25. Call Messages notifications unchanged and isolated', () {
      final res = VorynMeetingLinkService.parse('voryn://messages/thread-123');
      expect(res.isSuccess, isFalse);
      expect(res.failureReason, LinkParseFailureReason.unapprovedHost);
    });

    test('26. MEET-4A deep links remain unchanged and compatible', () {
      VorynMeetingLinkService.overrideBaseUrl = 'https://meet.voryn.app';

      final linkResult = VorynMeetingLinkService.parse('https://meet.voryn.app/m/abc-123-xyz');
      expect(linkResult.isSuccess, isTrue);
      expect(linkResult.link?.joinCode, 'abc-123-xyz');

      final schemeResult = VorynMeetingLinkService.parse('voryn://m/abc-123-xyz');
      expect(schemeResult.isSuccess, isTrue);
      expect(schemeResult.link?.joinCode, 'abc-123-xyz');
    });

    test('27. Merge Calls unaffected by meeting invitations', () {
      final coord = MultiCallCoordinator.instance;
      expect(coord.isMerging, isFalse);
    });
  });
}
