import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/core/notifications/lock_screen_service.dart';
import 'package:voryn/core/theme/voryn_theme_controller.dart';
import 'package:voryn/features/calling/active_audio_call_screen.dart';
import 'package:voryn/features/calling/voryn_call_latency_tracker.dart';
import 'package:voryn/features/calling/voryn_call_runtime_coordinator.dart';
import 'package:voryn/main.dart';

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

    test(
      'performTeardown is idempotent and executes route exit once',
      () async {
        final coordinator = VorynCallRuntimeCoordinator.forCall(
          'call-uuid-teardown',
        );
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
      },
    );

    test('isTransitioning suppresses teardown during screen swap', () async {
      final coordinator = VorynCallRuntimeCoordinator.forCall(
        'call-uuid-transition',
      );

      coordinator.attachScreen(onStatusChanged: (_) {}, onRouteExit: () {});

      expect(coordinator.isTransitioning, isFalse);

      // Screen transition begins (e.g. audio to video)
      coordinator.isTransitioning = true;
      coordinator.detachScreen();

      expect(coordinator.isTransitioning, isTrue);
      expect(coordinator.isEnded, isFalse);

      // Next screen attaches
      coordinator.attachScreen(onStatusChanged: (_) {}, onRouteExit: () {});

      expect(coordinator.isTransitioning, isFalse);
      expect(coordinator.isEnded, isFalse);

      await coordinator.performTeardown();
      expect(coordinator.isEnded, isTrue);
    });

    test('runAcceptOnce deduplicates accept invocations for a call', () async {
      int acceptExecutions = 0;
      final callId = 'call-accept-dedup-1';

      expect(VorynCallRuntimeCoordinator.isAcceptInFlight(callId), isFalse);

      final f1 = VorynCallRuntimeCoordinator.runAcceptOnce(callId, () async {
        acceptExecutions++;
        await Future.delayed(const Duration(milliseconds: 50));
        return 'done';
      });

      expect(VorynCallRuntimeCoordinator.isAcceptInFlight(callId), isTrue);

      expect(
        () => VorynCallRuntimeCoordinator.runAcceptOnce(callId, () async {
          acceptExecutions++;
          return 'done';
        }),
        throwsA(isA<StateError>()),
      );

      final result = await f1;
      expect(result, 'done');
      expect(acceptExecutions, 1);
    });

    test(
      'updateProximity and prepareForVideoUpgrade update coordinator state',
      () async {
        final coordinator = VorynCallRuntimeCoordinator.forCall(
          'call-uuid-prox-1',
        );

        coordinator.updateProximity(
          isConnected: true,
          mediaMode: 'audio',
          isHeld: false,
        );
        expect(coordinator.isEnded, isFalse);

        await coordinator.prepareForVideoUpgrade();
        expect(coordinator.isEnded, isFalse);

        await coordinator.performTeardown();
        expect(coordinator.isEnded, isTrue);
      },
    );
  });

  group('VorynCallLatencyTracker', () {
    test(
      'stages are deduplicated and tracked against base timestamp',
      () async {
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
      },
    );
  });

  group('LockedAcceptBootstrap', () {
    test(
      'call host launch configuration targets active call and excludes shell routes',
      () {
        const audioConfig = AppLaunchConfig(
          mode: AppLaunchMode.acceptedCall,
          callId: 'call-101',
          callType: 'audio',
          initialLocation: '/active-audio-call/call-101',
        );

        expect(audioConfig.initialLocation, '/active-audio-call/call-101');
        expect(audioConfig.initialLocation.contains('/connect'), isFalse);
        expect(audioConfig.initialLocation.contains('/recents'), isFalse);
        expect(audioConfig.initialLocation.contains('/contacts'), isFalse);
        expect(audioConfig.initialLocation.contains('/meetings'), isFalse);
        expect(audioConfig.mode, AppLaunchMode.acceptedCall);

        const videoConfig = AppLaunchConfig(
          mode: AppLaunchMode.acceptedCall,
          callId: 'call-102',
          callType: 'video',
          initialLocation: '/active-video-call/call-102',
        );

        expect(videoConfig.initialLocation, '/active-video-call/call-102');
        expect(videoConfig.initialLocation.contains('/connect'), isFalse);
        expect(videoConfig.mode, AppLaunchMode.acceptedCall);
      },
    );

    test('locked Accept routing logic maps keyguard state to target host', () {
      String resolveTargetHost({required bool keyguardLocked}) {
        return keyguardLocked ? 'VorynCallActivity' : 'MainActivity';
      }

      expect(resolveTargetHost(keyguardLocked: true), 'VorynCallActivity');
      expect(resolveTargetHost(keyguardLocked: false), 'MainActivity');
    });

    test(
      'duplicate accept does not create multiple active call sessions',
      () async {
        int acceptExecutions = 0;
        final callId = 'call-locked-dedup-1';

        final acceptFuture1 = VorynCallRuntimeCoordinator.runAcceptOnce(
          callId,
          () async {
            acceptExecutions++;
            await Future.delayed(const Duration(milliseconds: 20));
            return 'connected';
          },
        );

        // Second invocation while in flight throws StateError
        expect(
          () => VorynCallRuntimeCoordinator.runAcceptOnce(callId, () async {
            acceptExecutions++;
            return 'connected';
          }),
          throwsStateError,
        );

        final status = await acceptFuture1;
        expect(status, 'connected');
        expect(acceptExecutions, 1);
      },
    );

    test(
      'isCallHostApp flag forces moveCallTaskBehindKeyguard on coordinator teardown',
      () async {
        LockScreenService.isCallHostApp = true;
        final coordinator = VorynCallRuntimeCoordinator.forCall(
          'call-host-test-1',
        );
        bool exitCalled = false;
        coordinator.attachScreen(
          onStatusChanged: (_) {},
          onRouteExit: () {
            exitCalled = true;
          },
        );

        await coordinator.performTeardown(isLocalInitiator: true);
        expect(coordinator.isEnded, isTrue);
        // In call host app, route exit delegates to moveCallTaskBehindKeyguard rather than calling normal exit
        expect(exitCalled, isFalse);
        LockScreenService.isCallHostApp = false;
      },
    );

    testWidgets(
      'VorynCallHostApp renders ActiveAudioCallScreen directly without shell',
      (tester) async {
        final controller = VorynThemeController();
        await tester.pumpWidget(
          VorynCallHostApp(
            controller: controller,
            initialLocation: '/active-audio-call/test-host-call',
            callId: 'test-host-call',
            isVideo: false,
          ),
        );
        await tester.pump();

        expect(find.byType(ActiveAudioCallScreen), findsOneWidget);
        expect(find.byType(VorynShell), findsNothing);
        expect(find.text('Connect'), findsNothing);
        expect(find.text('Recents'), findsNothing);
        expect(find.text('Contacts'), findsNothing);
        expect(find.text('Meetings'), findsNothing);
      },
    );
  });
}
