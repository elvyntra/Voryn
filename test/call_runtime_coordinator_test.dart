import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/features/calling/voryn_call_latency_tracker.dart';
import 'package:voryn/features/calling/voryn_call_runtime_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VorynCallRuntimeCoordinator', () {
    test('forCall returns unique instance per callId', () {
      final c1 = VorynCallRuntimeCoordinator.forCall('call-uuid-1');
      final c2 = VorynCallRuntimeCoordinator.forCall('call-uuid-1');
      final c3 = VorynCallRuntimeCoordinator.forCall('call-uuid-2');

      expect(identical(c1, c2), isTrue);
      expect(identical(c1, c3), isFalse);

      VorynCallRuntimeCoordinator.remove('call-uuid-1');
      VorynCallRuntimeCoordinator.remove('call-uuid-2');
    });

    test('performTeardown is idempotent and executes route exit once', () async {
      final coordinator = VorynCallRuntimeCoordinator.forCall('call-uuid-teardown');
      int exitCalls = 0;

      coordinator.attachScreen(
        onStatusChanged: (_) {},
        onRouteExit: () {
          exitCalls++;
        },
      );

      // Call performTeardown multiple times concurrently
      final f1 = coordinator.performTeardown(isLocalInitiator: false);
      final f2 = coordinator.performTeardown(isLocalInitiator: false);
      final f3 = coordinator.performTeardown(isLocalInitiator: true);

      await Future.wait([f1, f2, f3]);

      expect(coordinator.isEnded, isTrue);
      expect(coordinator.isTearingDown, isTrue);
      expect(coordinator.routeExitIssued, isTrue);
      expect(exitCalls, 1);

      // Sequential call after completion should also be a no-op
      await coordinator.performTeardown(isLocalInitiator: true);
      expect(exitCalls, 1);
    });

    test('isTransitioning suppresses teardown during screen swap', () async {
      final coordinator = VorynCallRuntimeCoordinator.forCall('call-uuid-transition');

      coordinator.attachScreen(
        onStatusChanged: (_) {},
        onRouteExit: () {},
      );

      expect(coordinator.isTransitioning, isFalse);

      // Screen transition begins (e.g. audio to video)
      coordinator.isTransitioning = true;
      coordinator.detachScreen();

      expect(coordinator.isTransitioning, isTrue);
      expect(coordinator.isEnded, isFalse);

      // Next screen attaches
      coordinator.attachScreen(
        onStatusChanged: (_) {},
        onRouteExit: () {},
      );

      expect(coordinator.isTransitioning, isFalse);
      expect(coordinator.isEnded, isFalse);

      await coordinator.performTeardown();
      expect(coordinator.isEnded, isTrue);
    });
  });

  group('VorynCallLatencyTracker', () {
    test('stages are deduplicated and tracked against base timestamp', () async {
      final tracker = VorynCallLatencyTracker.start(
        callId: 'latency-call-1',
        baseTimestampMs: 5000,
      );

      await tracker.stage('test_stage_1');
      await tracker.stage('test_stage_1'); // Duplicate
      await tracker.stage('test_stage_2');

      // Subsequent get returns same tracker
      final sameTracker = VorynCallLatencyTracker.get('latency-call-1');
      expect(identical(tracker, sameTracker), isTrue);

      VorynCallLatencyTracker.dispose('latency-call-1');
      expect(VorynCallLatencyTracker.get('latency-call-1'), isNull);
    });
  });
}
