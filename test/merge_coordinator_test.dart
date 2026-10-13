import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:voryn/features/calling/multi_call_coordinator.dart';
import 'package:voryn/features/calling/voryn_call_service.dart';
import 'package:voryn/features/calling/voryn_livekit_service.dart';

class FakeLiveKitSession implements VorynLiveKitSession {
  bool micEnabled;
  bool cameraEnabled;
  bool speakerEnabled;
  bool held;
  bool disconnected = false;
  int resumeCount = 0;
  int connectCount = 0;

  FakeLiveKitSession({
    this.micEnabled = true,
    this.cameraEnabled = false,
    this.speakerEnabled = false,
    this.held = false,
  });

  @override
  bool get isConnected => !disconnected;

  @override
  bool get isHeld => held;

  @override
  livekit.VideoTrack? get localVideoTrack => null;

  @override
  livekit.VideoTrack? get remoteVideoTrack => null;

  @override
  bool get isScreenShareEnabled => false;

  @override
  livekit.VideoTrack? get localScreenShareTrack => null;

  @override
  livekit.VideoTrack? get remoteScreenShareTrack => null;

  @override
  String? get screenSharePresenterName => null;

  @override
  bool get hasRemoteScreenShare => false;

  @override
  bool get hasActiveScreenShare => false;

  @override
  livekit.Room get room => throw UnimplementedError('Mock session room');

  @override
  Future<void> hold() async {
    held = true;
    micEnabled = false;
  }

  @override
  Future<void> resume({
    bool restoreMic = true,
    bool restoreCamera = false,
  }) async {
    resumeCount++;
    held = false;
    micEnabled = restoreMic;
    cameraEnabled = restoreCamera;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    micEnabled = enabled;
  }

  @override
  Future<bool> setCameraEnabled(bool enabled) async {
    cameraEnabled = enabled;
    return true;
  }

  @override
  Future<void> setSpeakerEnabled(bool enabled) async {
    speakerEnabled = enabled;
  }

  @override
  Future<bool> setScreenShareEnabled(bool enabled) async => true;

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }
}

class FakeCallService extends VorynCallService {
  Map<String, dynamic>? prepareResult;
  Map<String, dynamic>? finalizeResult;
  Map<String, dynamic>? cancelResult;
  Map<String, dynamic>? getOpResult;
  final Map<String, Map<String, dynamic>> callsData = {};

  @override
  Future<Map<String, dynamic>?> getCall(String callId) async {
    return callsData[callId];
  }

  final List<String> preparedCalls = [];
  final List<String> finalizedOps = [];
  final List<String> cancelledOps = [];
  final List<String> endedCalls = [];

  @override
  Future<Map<String, dynamic>?> prepareCallMerge({
    required String primaryCallId,
    required String secondaryCallId,
  }) async {
    preparedCalls.add('$primaryCallId->$secondaryCallId');
    return prepareResult ??
        {
          'result': 'prepared',
          'merge_operation_id': 'op-123',
          'primary_call_id': primaryCallId,
          'secondary_call_id': secondaryCallId,
          'joining_user_uid': 'user-c',
          'expires_at': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
        };
  }

  @override
  Future<Map<String, dynamic>?> finalizeCallMerge({
    required String mergeOperationId,
  }) async {
    finalizedOps.add(mergeOperationId);
    return finalizeResult ??
        {
          'result': 'committed',
          'conferenceCallId': 'call-primary-1',
          'secondaryCallId': 'call-secondary-2',
        };
  }

  @override
  Future<Map<String, dynamic>?> cancelCallMerge({
    required String mergeOperationId,
    String reason = 'client_aborted',
  }) async {
    cancelledOps.add(mergeOperationId);
    return cancelResult ??
        {
          'result': 'cancelled',
          'mergeOperationId': mergeOperationId,
        };
  }

  @override
  Future<Map<String, dynamic>?> getCallMergeOperation(
    String mergeOperationId,
  ) async {
    return getOpResult;
  }

  @override
  Future<bool> end(String callId) async {
    endedCalls.add(callId);
    return true;
  }

  @override
  Future<bool> setCallHoldState(String callId, bool isHeld) async {
    return true;
  }

  @override
  Future<Map<String, dynamic>?> switchHeldCall({
    required String activeCallId,
    required String heldCallId,
  }) async {
    return {
      'result': 'applied',
      'active_call_id': heldCallId,
      'held_call_id': activeCallId,
    };
  }
}

class FakeLiveKitService extends VorynLiveKitService {
  FakeLiveKitSession? provisionalSessionToReturn;
  String? lastProvisionalPrimaryCallId;
  String? lastProvisionalMergeOpId;
  bool connectProvisionalCalled = false;
  bool shouldThrow = false;

  @override
  Future<VorynLiveKitSession> connectProvisional({
    required String primaryCallId,
    required String mergeOperationId,
  }) async {
    connectProvisionalCalled = true;
    lastProvisionalPrimaryCallId = primaryCallId;
    lastProvisionalMergeOpId = mergeOperationId;
    if (shouldThrow) {
      throw Exception('Provisional connection failed');
    }
    return provisionalSessionToReturn ??
        FakeLiveKitSession(
          micEnabled: false,
          cameraEnabled: false,
          speakerEnabled: false,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Checkpoint MC-2C — Two-Phase Merge Client State Machine Tests', () {
    late MultiCallCoordinator coordinator;
    late FakeCallService fakeCallService;
    late FakeLiveKitService fakeLiveKitService;

    late FakeLiveKitSession primarySession;
    late FakeLiveKitSession secondarySession;

    setUp(() {
      coordinator = MultiCallCoordinator.instance;
      coordinator.resetMergeState();
      coordinator.removeSession('call-primary-1');
      coordinator.removeSession('call-secondary-2');

      fakeCallService = FakeCallService();
      fakeLiveKitService = FakeLiveKitService();

      coordinator.callService = fakeCallService;
      coordinator.liveKitService = fakeLiveKitService;

      primarySession = FakeLiveKitSession(held: true, micEnabled: false);
      secondarySession = FakeLiveKitSession(held: false, micEnabled: true);
    });

    tearDown(() {
      coordinator.resetMergeState();
      coordinator.removeSession('call-primary-1');
      coordinator.removeSession('call-secondary-2');
      coordinator.callService = const VorynCallService();
      coordinator.liveKitService = const VorynLiveKitService();
    });

    void setupActiveAndHeldCalls() {
      coordinator.recordCallType('call-primary-1', 'audio');
      coordinator.recordCallType('call-secondary-2', 'audio');
      coordinator.registerSession('call-primary-1', primarySession, callType: 'audio');
      coordinator.registerSession('call-secondary-2', secondarySession, callType: 'audio');
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );
      coordinator.recordPreHoldMediaState(
        'call-primary-1',
        micEnabled: true,
        cameraEnabled: false,
        speakerEnabled: false,
      );
    }

    test('1. Merge state transitions (idle -> preparing -> waiting -> finalizing -> committed)', () async {
      setupActiveAndHeldCalls();

      expect(coordinator.heldCallId, 'call-primary-1');
      expect(coordinator.activeCallId, 'call-secondary-2');
      expect(coordinator.mergeState.status, MergeStatus.idle);

      final started = await coordinator.mergeCalls();
      expect(started, isTrue);
      expect(coordinator.mergeState.status, MergeStatus.waitingForParticipant);
      expect(coordinator.mergeState.mergeOperationId, 'op-123');

      final finalized = await coordinator.finalizeMerge('op-123');
      expect(finalized, isTrue);
      expect(coordinator.mergeState.status, MergeStatus.idle);
      expect(coordinator.activeCallId, 'call-primary-1');
      expect(coordinator.heldCallId, isNull);
    });

    test('2. Merge cancellation transitions (preparing -> cancelling -> idle)', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();
      expect(coordinator.mergeState.status, MergeStatus.waitingForParticipant);

      await coordinator.cancelMerge(reason: 'client_aborted');
      expect(coordinator.mergeState.status, MergeStatus.idle);
      expect(fakeCallService.cancelledOps, contains('op-123'));
    });

    test('3. Merge timeout triggers rollback', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();
      expect(coordinator.isMerging, isTrue);

      // Simulate timeout
      await coordinator.cancelMerge(reason: 'timeout');
      expect(coordinator.mergeState.status, MergeStatus.idle);
      expect(coordinator.isMerging, isFalse);
    });

    test('4. Primary designated as held call, secondary as active call', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();
      expect(coordinator.mergeState.primaryCallId, 'call-primary-1');
      expect(coordinator.mergeState.secondaryCallId, 'call-secondary-2');
      expect(fakeCallService.preparedCalls, contains('call-primary-1->call-secondary-2'));
    });

    test('5. Merge rejected if only one call exists', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.setTestCalls(activeCallId: 'call-primary-1', heldCallId: null);
      expect(coordinator.hasHeldCall, isFalse);

      final result = await coordinator.mergeCalls();
      expect(result, isFalse);
      expect(coordinator.mergeState.status, MergeStatus.idle);
    });

    test('6. Merge rejected if merge already in flight', () async {
      setupActiveAndHeldCalls();

      final first = await coordinator.mergeCalls();
      expect(first, isTrue);
      expect(coordinator.isMerging, isTrue);

      final second = await coordinator.mergeCalls();
      expect(second, isFalse);
    });

    test('7. Prepare failure rolls back cleanly to idle', () async {
      setupActiveAndHeldCalls();

      fakeCallService.prepareResult = {
        'result': 'rejected',
        'reason': 'capacity_exceeded',
      };

      final result = await coordinator.mergeCalls();
      expect(result, isFalse);
      expect(coordinator.mergeState.status, MergeStatus.idle);
      expect(coordinator.isMerging, isFalse);
    });

    test('8. Finalize failure triggers cancel and rolls back to idle', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();

      fakeCallService.finalizeResult = {
        'result': 'rejected',
        'reason': 'server_error',
      };

      final finalResult = await coordinator.finalizeMerge('op-123');
      expect(finalResult, isFalse);
      expect(coordinator.mergeState.status, MergeStatus.idle);
      expect(fakeCallService.cancelledOps, contains('op-123'));
    });

    test('9. Calls remain intact after failed merge', () async {
      setupActiveAndHeldCalls();

      fakeCallService.finalizeResult = {
        'result': 'rejected',
        'reason': 'database_error',
      };

      await coordinator.mergeCalls();
      await coordinator.finalizeMerge('op-123');

      // Both calls still present
      expect(coordinator.sessionsByCallId.containsKey('call-primary-1'), isTrue);
      expect(coordinator.sessionsByCallId.containsKey('call-secondary-2'), isTrue);
      expect(coordinator.activeCallId, 'call-secondary-2');
      expect(coordinator.heldCallId, 'call-primary-1');
    });

    test('10. Provisional connection is media-silent (no mic, no camera)', () async {
      final provSession = FakeLiveKitSession(
        micEnabled: false,
        cameraEnabled: false,
        speakerEnabled: false,
      );
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      expect(coordinator.provisionalSession, isNotNull);
      expect(coordinator.provisionalSession!.roomConnectedMediaSilent, isTrue);
    });

    test('11. Provisional connection does not touch audio route', () async {
      final provSession = FakeLiveKitSession(
        micEnabled: false,
        cameraEnabled: false,
        speakerEnabled: false,
      );
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      expect(provSession.speakerEnabled, isFalse);
    });

    test('12. Secondary session disposed only after commit', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();
      // Before commit: secondary is intact
      expect(secondarySession.disconnected, isFalse);
      expect(coordinator.sessionsByCallId.containsKey('call-secondary-2'), isTrue);

      // Finalize commit
      await coordinator.finalizeMerge('op-123');
      // After commit: secondary is disconnected and removed
      expect(secondarySession.disconnected, isTrue);
      expect(coordinator.sessionsByCallId.containsKey('call-secondary-2'), isFalse);
    });

    test('13. Primary session promoted to conference on commit', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();
      await coordinator.finalizeMerge('op-123');

      expect(coordinator.activeCallId, 'call-primary-1');
      expect(coordinator.heldCallId, isNull);
    });

    test('14. Media state restored on primary after commit', () async {
      setupActiveAndHeldCalls();

      expect(primarySession.held, isTrue);
      expect(primarySession.micEnabled, isFalse);

      await coordinator.mergeCalls();
      await coordinator.finalizeMerge('op-123');

      expect(primarySession.held, isFalse);
      expect(primarySession.micEnabled, isTrue);
    });

    test('15. User C joins provisionally without interrupting Call 2 audio', () async {
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(activeCallId: 'call-secondary-2', heldCallId: null);

      final provSession = FakeLiveKitSession(micEnabled: false);
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      // Call 2 audio remains active
      expect(secondarySession.disconnected, isFalse);
      expect(secondarySession.micEnabled, isTrue);
      // Provisional is media silent
      expect(provSession.micEnabled, isFalse);
    });

    test('16. User C promotes primary and disposes secondary on commit', () async {
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(activeCallId: 'call-secondary-2', heldCallId: null);

      final provSession = FakeLiveKitSession(micEnabled: false);
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      await coordinator.promoteProvisionalToActiveConference('call-primary-1');

      expect(secondarySession.disconnected, isTrue);
      expect(coordinator.sessionsByCallId.containsKey('call-secondary-2'), isFalse);
      expect(coordinator.activeCallId, 'call-primary-1');
      expect(provSession.micEnabled, isTrue);
    });

    test('17. User C aborts provisional on cancel and stays on Call 2', () async {
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(activeCallId: 'call-secondary-2', heldCallId: null);

      final provSession = FakeLiveKitSession(micEnabled: false);
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      await coordinator.rollbackProvisional('call-primary-1');

      expect(provSession.disconnected, isTrue);
      expect(coordinator.provisionalSession, isNull);
      expect(secondarySession.disconnected, isFalse);
      expect(coordinator.activeCallId, 'call-secondary-2');
    });

    test('18. Mid-merge hangup by initiator cancels merge', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();
      expect(coordinator.isMerging, isTrue);

      // Initiator hangs up active call
      await coordinator.endCall('call-secondary-2');

      expect(fakeCallService.cancelledOps, contains('op-123'));
      expect(coordinator.isMerging, isFalse);
    });

    test('19. Mid-merge hangup by joining user cancels merge', () async {
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(activeCallId: 'call-secondary-2', heldCallId: null);

      final provSession = FakeLiveKitSession(micEnabled: false);
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      // Joining user ends call
      await coordinator.endCall('call-secondary-2');

      expect(fakeCallService.cancelledOps, contains('op-join-99'));
      expect(provSession.disconnected, isTrue);
    });

    test('20. Mid-merge hangup by held user cancels merge', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();

      // Held call ends
      await coordinator.endCall('call-primary-1');

      expect(fakeCallService.cancelledOps, contains('op-123'));
      expect(coordinator.sessionsByCallId.containsKey('call-primary-1'), isFalse);
      expect(coordinator.sessionsByCallId.containsKey('call-secondary-2'), isTrue);
    });

    test('21. Realtime subscription receives commit event', () async {
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(activeCallId: 'call-secondary-2', heldCallId: null);

      final provSession = FakeLiveKitSession(micEnabled: false);
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      // Simulate commit event trigger
      await coordinator.promoteProvisionalToActiveConference('call-primary-1');

      expect(coordinator.activeCallId, 'call-primary-1');
      expect(coordinator.mergeState.status, MergeStatus.idle);
    });

    test('22. Duplicate merge tap ignored while transition in flight', () async {
      setupActiveAndHeldCalls();

      final first = await coordinator.mergeCalls();
      expect(first, isTrue);

      final second = await coordinator.mergeCalls();
      expect(second, isFalse);
    });

    test('23. Timeout at 30 seconds triggers cancellation', () async {
      setupActiveAndHeldCalls();

      await coordinator.mergeCalls();
      expect(coordinator.isMerging, isTrue);

      // Invoke cancel representing timeout trigger
      await coordinator.cancelMerge(reason: 'timeout');

      expect(fakeCallService.cancelledOps, contains('op-123'));
      expect(coordinator.isMerging, isFalse);
    });

    test('24. Audio focus never claimed by provisional session', () async {
      final provSession = FakeLiveKitSession(
        micEnabled: false,
        cameraEnabled: false,
        speakerEnabled: false,
      );
      fakeLiveKitService.provisionalSessionToReturn = provSession;

      await coordinator.handleMergeDetectedForJoining({
        'id': 'op-join-99',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
      });

      expect(provSession.speakerEnabled, isFalse);
    });

    test('25. Error notification shown to user on merge failure', () async {
      setupActiveAndHeldCalls();

      fakeCallService.prepareResult = {
        'result': 'rejected',
        'reason': 'capacity_exceeded',
      };

      await coordinator.mergeCalls();

      expect(coordinator.mergeErrorNotifier.value, contains('capacity_exceeded'));
    });
  });

  group('Checkpoint MC-2C.1 — Participant Convergence & Recovery Tests', () {
    late MultiCallCoordinator coordinator;
    late FakeCallService fakeCallService;
    late FakeLiveKitService fakeLiveKitService;

    late FakeLiveKitSession primarySession;
    late FakeLiveKitSession secondarySession;

    setUp(() {
      coordinator = MultiCallCoordinator.instance;
      coordinator.resetMergeState();
      coordinator.removeSession('call-primary-1');
      coordinator.removeSession('call-secondary-2');

      fakeCallService = FakeCallService();
      fakeLiveKitService = FakeLiveKitService();

      coordinator.callService = fakeCallService;
      coordinator.liveKitService = fakeLiveKitService;

      primarySession = FakeLiveKitSession(held: false, micEnabled: true);
      secondarySession = FakeLiveKitSession(held: false, micEnabled: true);
    });

    tearDown(() {
      coordinator.resetMergeState();
      coordinator.removeSession('call-primary-1');
      coordinator.removeSession('call-secondary-2');
      coordinator.callService = const VorynCallService();
      coordinator.liveKitService = const VorynLiveKitService();
    });

    test('1. B receives committed conference state', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.setRemoteHoldState('call-primary-1', 'user-a');
      expect(coordinator.isCallHeldByRemote('call-primary-1'), isTrue);

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(coordinator.isCallHeldByRemote('call-primary-1'), isFalse);
      expect(coordinator.getRemoteHolder('call-primary-1'), isNull);
    });

    test('2. B exits hold without reconnecting', () async {
      primarySession.held = true;
      primarySession.micEnabled = false;
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.setRemoteHoldState('call-primary-1', 'user-a');

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(primarySession.held, isFalse);
      expect(primarySession.disconnected, isFalse);
      expect(fakeLiveKitService.connectProvisionalCalled, isFalse);
    });

    test('3. B reuses same primary session', () async {
      primarySession.held = true;
      coordinator.registerSession('call-primary-1', primarySession);

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(identical(coordinator.sessionsByCallId['call-primary-1'], primarySession), isTrue);
    });

    test('4. B preserves mute state', () async {
      primarySession.held = true;
      primarySession.micEnabled = false;
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.recordPreHoldMediaState(
        'call-primary-1',
        micEnabled: false,
        cameraEnabled: false,
        speakerEnabled: false,
      );

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(primarySession.held, isFalse);
      expect(primarySession.micEnabled, isFalse);
    });

    test('5. B preserves camera state', () async {
      primarySession.held = true;
      primarySession.cameraEnabled = false;
      coordinator.registerSession('call-primary-1', primarySession, callType: 'video');
      coordinator.recordPreHoldMediaState(
        'call-primary-1',
        micEnabled: true,
        cameraEnabled: true,
        speakerEnabled: false,
      );

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(primarySession.held, isFalse);
      expect(primarySession.cameraEnabled, isTrue);
    });

    test('6. Duplicate commit event is idempotent', () async {
      primarySession.held = true;
      coordinator.registerSession('call-primary-1', primarySession);

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');
      final firstResumeCount = primarySession.resumeCount;
      expect(firstResumeCount, 1);

      await coordinator.reconcileCallStateOnResume('call-primary-1');
      expect(primarySession.resumeCount, firstResumeCount);
      expect(primarySession.held, isFalse);
    });

    test('7. Resume during prepared merge', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );

      await coordinator.mergeCalls();
      expect(coordinator.isMerging, isTrue);

      fakeCallService.getOpResult = {
        'id': 'op-123',
        'status': 'prepared',
        'expires_at': DateTime.now().toUtc().add(const Duration(seconds: 20)).toIso8601String(),
      };

      await coordinator.reconcileMergeOnResume();

      expect(coordinator.isMerging, isTrue);
      expect(coordinator.mergeState.mergeOperationId, 'op-123');
    });

    test('8. Resume during joining merge', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );

      await coordinator.mergeCalls();

      fakeCallService.getOpResult = {
        'id': 'op-123',
        'status': 'joining',
        'expires_at': DateTime.now().toUtc().add(const Duration(seconds: 20)).toIso8601String(),
      };

      await coordinator.reconcileMergeOnResume();

      expect(fakeCallService.finalizedOps, contains('op-123'));
    });

    test('9. Resume after committed merge', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );

      await coordinator.mergeCalls();

      fakeCallService.getOpResult = {
        'id': 'op-123',
        'status': 'committed',
        'primary_call_id': 'call-primary-1',
      };

      await coordinator.reconcileMergeOnResume();

      expect(fakeCallService.finalizedOps, contains('op-123'));
      expect(coordinator.activeCallId, 'call-primary-1');
      expect(coordinator.heldCallId, isNull);
      expect(coordinator.mergeState.status, MergeStatus.idle);
    });

    test('10. Resume after cancelled merge', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );

      await coordinator.mergeCalls();

      fakeCallService.getOpResult = {
        'id': 'op-123',
        'status': 'cancelled',
      };

      await coordinator.reconcileMergeOnResume();

      expect(coordinator.isMerging, isFalse);
      expect(coordinator.mergeState.status, MergeStatus.idle);
    });

    test('11. Resume after expired merge', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );

      await coordinator.mergeCalls();

      fakeCallService.getOpResult = {
        'id': 'op-123',
        'status': 'prepared',
        'expires_at': DateTime.now().toUtc().subtract(const Duration(seconds: 10)).toIso8601String(),
      };

      await coordinator.reconcileMergeOnResume();

      expect(fakeCallService.cancelledOps, contains('op-123'));
      expect(coordinator.isMerging, isFalse);
    });

    test('12. Cold restart after committed merge', () async {
      await coordinator.recoverFromColdRestart(
        userId: 'user-c',
        activeCallsFetcher: (uid) async => [
          {
            'call_id': 'call-secondary-2',
            'calls': {
              'id': 'call-secondary-2',
              'status': 'connected',
              'merged_into_call_id': 'call-primary-1',
            },
          },
        ],
      );

      expect(coordinator.activeCallId, 'call-primary-1');
      expect(coordinator.mergeState.status, MergeStatus.idle);
    });

    test('13. Cold restart after expired merge', () async {
      await coordinator.recoverFromColdRestart(
        userId: 'user-a',
        activeCallsFetcher: (uid) async => [
          {
            'call_id': 'call-primary-1',
            'calls': {
              'id': 'call-primary-1',
              'status': 'connected',
              'merged_into_call_id': null,
            },
          },
        ],
      );

      expect(coordinator.activeCallId, 'call-primary-1');
      expect(coordinator.mergeState.status, MergeStatus.idle);
    });

    test('14. Stale response from prior operation ignored', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );

      coordinator.resetMergeState();

      await coordinator.finalizeMerge('op-stale-99');

      expect(fakeCallService.finalizedOps, isNot(contains('op-stale-99')));
      expect(coordinator.mergeState.status, MergeStatus.idle);
    });

    test('15. New merge unaffected by old callback', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-secondary-2',
        heldCallId: 'call-primary-1',
      );

      fakeCallService.prepareResult = {
        'result': 'prepared',
        'merge_operation_id': 'op-new-222',
        'primary_call_id': 'call-primary-1',
        'secondary_call_id': 'call-secondary-2',
        'expires_at': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
      };

      await coordinator.mergeCalls();
      expect(coordinator.mergeState.mergeOperationId, 'op-new-222');

      await coordinator.cancelMerge(mergeOperationId: 'op-old-111', reason: 'stale_timeout');

      expect(coordinator.mergeState.mergeOperationId, 'op-new-222');
      expect(coordinator.isMerging, isTrue);
      expect(fakeCallService.cancelledOps, isNot(contains('op-old-111')));
    });

    test('16. B background/resume convergence', () async {
      primarySession.held = true;
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.setRemoteHoldState('call-primary-1', 'user-a');

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(primarySession.held, isFalse);
      expect(coordinator.isCallHeldByRemote('call-primary-1'), isFalse);
    });

    test('17. B network reconnect convergence', () async {
      primarySession.held = true;
      coordinator.registerSession('call-primary-1', primarySession);

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(primarySession.held, isFalse);
      expect(primarySession.isConnected, isTrue);
    });

    test('18. No duplicate Room.connect', () async {
      primarySession.held = true;
      coordinator.registerSession('call-primary-1', primarySession);

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(primarySession.connectCount, 0);
      expect(fakeLiveKitService.connectProvisionalCalled, isFalse);
    });

    test('19. No duplicate media publication', () async {
      primarySession.held = true;
      coordinator.registerSession('call-primary-1', primarySession);

      fakeCallService.callsData['call-primary-1'] = {
        'id': 'call-primary-1',
        'status': 'connected',
        'held_by': null,
      };

      await coordinator.reconcileCallStateOnResume('call-primary-1');

      expect(primarySession.resumeCount, 1);
      expect(primarySession.held, isFalse);
    });

    test('20. Existing Hold/Switch still passes', () async {
      coordinator.registerSession('call-primary-1', primarySession);
      coordinator.registerSession('call-secondary-2', secondarySession);
      coordinator.setTestCalls(
        activeCallId: 'call-primary-1',
        heldCallId: 'call-secondary-2',
      );

      final switched = await coordinator.switchCalls();

      expect(switched, isTrue);
      expect(coordinator.activeCallId, 'call-secondary-2');
      expect(coordinator.heldCallId, 'call-primary-1');
    });
  });
}

extension on VorynLiveKitSession {
  bool get roomConnectedMediaSilent {
    if (this is FakeLiveKitSession) {
      final s = this as FakeLiveKitSession;
      return !s.micEnabled && !s.cameraEnabled;
    }
    return true;
  }
}
