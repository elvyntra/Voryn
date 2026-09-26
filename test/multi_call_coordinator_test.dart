import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/features/calling/multi_call_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MultiCallCoordinator Unit Tests', () {
    late MultiCallCoordinator coordinator;

    setUp(() {
      coordinator = MultiCallCoordinator.instance;
      coordinator.removeSession('call-active-1');
      coordinator.removeSession('call-held-2');
      coordinator.dismissWaitingCall('call-waiting-3');
    });

    tearDown(() {
      coordinator.removeSession('call-active-1');
      coordinator.removeSession('call-held-2');
      coordinator.dismissWaitingCall('call-waiting-3');
    });

    test('initial state has no active, held, or waiting call', () {
      expect(coordinator.activeCallId, isNull);
      expect(coordinator.heldCallId, isNull);
      expect(coordinator.waitingCallId, isNull);
      expect(coordinator.hasWaitingCall, isFalse);
      expect(coordinator.hasHeldCall, isFalse);
    });

    test('handleIncomingWaitingCall sets waiting call state', () {
      coordinator.handleIncomingWaitingCall(
        callId: 'call-waiting-3',
        callerName: 'Alice',
        callType: 'audio',
      );

      expect(coordinator.waitingCallId, 'call-waiting-3');
      expect(coordinator.waitingCallerName, 'Alice');
      expect(coordinator.waitingCallType, 'audio');
      expect(coordinator.hasWaitingCall, isTrue);
    });

    test('duplicate waiting call event is ignored idempotently', () {
      coordinator.handleIncomingWaitingCall(
        callId: 'call-waiting-3',
        callerName: 'Alice',
        callType: 'audio',
      );

      // Duplicate invocation
      coordinator.handleIncomingWaitingCall(
        callId: 'call-waiting-3',
        callerName: 'Alice Updated',
        callType: 'video',
      );

      expect(coordinator.waitingCallId, 'call-waiting-3');
      expect(coordinator.waitingCallerName, 'Alice'); // Unchanged
    });

    test('dismissWaitingCall clears waiting call state', () {
      coordinator.handleIncomingWaitingCall(
        callId: 'call-waiting-3',
        callerName: 'Alice',
        callType: 'audio',
      );
      expect(coordinator.hasWaitingCall, isTrue);

      coordinator.dismissWaitingCall('call-waiting-3');
      expect(coordinator.hasWaitingCall, isFalse);
      expect(coordinator.waitingCallId, isNull);
      expect(coordinator.waitingCallerName, isNull);
    });

    test('remote hold state tracking works correctly', () {
      expect(coordinator.isCallHeldByRemote('call-active-1'), isFalse);
      expect(coordinator.getRemoteHolder('call-active-1'), isNull);

      coordinator.setRemoteHoldState('call-active-1', 'remote-user-uid');
      expect(coordinator.isCallHeldByRemote('call-active-1'), isTrue);
      expect(coordinator.getRemoteHolder('call-active-1'), 'remote-user-uid');

      coordinator.setRemoteHoldState('call-active-1', null);
      expect(coordinator.isCallHeldByRemote('call-active-1'), isFalse);
      expect(coordinator.getRemoteHolder('call-active-1'), isNull);
    });

    test('pre-hold media state preservation', () {
      coordinator.recordPreHoldMediaState(
        'call-active-1',
        micEnabled: false,
        cameraEnabled: true,
        speakerEnabled: true,
      );

      final state = coordinator.getPreHoldMediaState('call-active-1');
      expect(state, isNotNull);
      expect(state!.wasMicEnabled, isFalse);
      expect(state.wasCameraEnabled, isTrue);
      expect(state.wasSpeakerEnabled, isTrue);
    });
  });
}
