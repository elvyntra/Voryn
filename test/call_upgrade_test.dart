import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/features/calling/active_audio_call_screen.dart';
import 'package:voryn/features/calling/active_video_call_screen.dart';
import 'package:voryn/features/calling/multi_call_coordinator.dart';
import 'package:voryn/features/calling/voryn_call_runtime_coordinator.dart';
import 'package:voryn/features/connect/mock_voryn_state.dart';
import 'package:voryn/main.dart';
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

  const testUser = VorynMockUser(
    backendUid: '6f7f1ca3-32c2-43c3-a4f9-d01dadd1a4b5',
    customName: null,
    name: 'Vikash Chaurasiya',
    id: '@vikash',
    phone: '+919876543210',
    email: 'vikash@example.com',
    presence: VorynPresenceStatus.online,
    initials: 'VC',
  );

  group('Audio to Video Call Upgrade Coordinator Tests', () {
    test('Timer continuity across audio and video transitions', () async {
      const callId = 'test-call-timer-01';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);

      // Audio call connects at T-10 seconds
      final startTime = DateTime.now().subtract(const Duration(seconds: 10));
      coordinator.markConnected(startTime);

      expect(coordinator.connectedAt, startTime);
      expect(coordinator.currentDuration.inSeconds >= 10, isTrue);

      // Video call attaches and checks duration
      coordinator.markConnected(); // idempotent - does not overwrite
      expect(coordinator.connectedAt, startTime);
      expect(coordinator.currentDuration.inSeconds >= 10, isTrue);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    test('Screen-aware detachment prevents disposed old screen from killing active session', () async {
      const callId = 'test-call-detach-01';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final screenA = Object();
      final screenB = Object();

      int statusUpdates = 0;
      int exitCalls = 0;

      // Screen A attaches
      coordinator.attachScreen(
        screenKey: screenA,
        onStatusChanged: (_) => statusUpdates++,
        onRouteExit: () => exitCalls++,
      );

      expect(coordinator.isScreenActive(screenA), isTrue);
      expect(coordinator.isScreenActive(screenB), isFalse);

      // Transition begins
      coordinator.isTransitioning = true;

      // Screen B attaches
      coordinator.attachScreen(
        screenKey: screenB,
        onStatusChanged: (_) => statusUpdates++,
        onRouteExit: () => exitCalls++,
      );

      expect(coordinator.isScreenActive(screenB), isTrue);
      expect(coordinator.isScreenActive(screenA), isFalse);

      // Screen A disposes and calls detachScreen(screenA)
      coordinator.detachScreen(screenA);

      // Screen B should STILL be active and callbacks must NOT be cleared
      expect(coordinator.isScreenActive(screenB), isTrue);
      expect(coordinator.isEnded, isFalse);

      // Screen B disposes without transition (user hangs up)
      coordinator.detachScreen(screenB);
      expect(coordinator.isScreenActive(screenB), isFalse);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    test('MultiCallCoordinator tracks video call type on upgrade', () {
      const callId = 'test-call-type-upgrade';
      MultiCallCoordinator.instance.recordCallType(callId, 'audio');
      expect(MultiCallCoordinator.instance.getCallType(callId), 'audio');

      MultiCallCoordinator.instance.recordCallType(callId, 'video');
      expect(MultiCallCoordinator.instance.getCallType(callId), 'video');
    });

    test('ActiveAudioCallScreen and ActiveVideoCallScreen constructors preserve initial parameters', () {
      const audioScreen = ActiveAudioCallScreen(
        callId: 'call-params-audio',
        user: testUser,
        initialMuted: true,
        initialSpeakerOn: true,
      );
      expect(audioScreen.callId, 'call-params-audio');
      expect(audioScreen.initialMuted, isTrue);
      expect(audioScreen.initialSpeakerOn, isTrue);

      const videoScreen = ActiveVideoCallScreen(
        callId: 'call-params-video',
        user: testUser,
        initialMuted: true,
        initialCameraEnabled: false,
      );
      expect(videoScreen.callId, 'call-params-video');
      expect(videoScreen.initialMuted, isTrue);
      expect(videoScreen.initialCameraEnabled, isFalse);
    });

    test('Repeated Audio <-> Video switching 5 times maintains continuity and prevents teardown', () async {
      const callId = 'test-repeated-switching-01';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final startTime = DateTime.now().subtract(const Duration(seconds: 30));
      coordinator.markConnected(startTime);

      Object currentScreen = Object();
      coordinator.attachScreen(
        screenKey: currentScreen,
        onStatusChanged: (_) {},
        onRouteExit: () {},
      );

      for (int cycle = 1; cycle <= 5; cycle++) {
        // --- Transition to Video ---
        coordinator.isTransitioning = true;
        MultiCallCoordinator.instance.recordCallType(callId, 'video');

        final nextVideoScreen = Object();
        coordinator.attachScreen(
          screenKey: nextVideoScreen,
          onStatusChanged: (_) {},
          onRouteExit: () {},
        );
        coordinator.detachScreen(currentScreen);
        currentScreen = nextVideoScreen;

        expect(coordinator.isScreenActive(currentScreen), isTrue);
        expect(coordinator.isEnded, isFalse);
        expect(coordinator.isTearingDown, isFalse);
        expect(coordinator.connectedAt, startTime);
        expect(coordinator.currentDuration.inSeconds >= 30, isTrue);
        expect(MultiCallCoordinator.instance.getCallType(callId), 'video');

        // --- Transition back to Audio ---
        coordinator.isTransitioning = true;
        MultiCallCoordinator.instance.recordCallType(callId, 'audio');

        final nextAudioScreen = Object();
        coordinator.attachScreen(
          screenKey: nextAudioScreen,
          onStatusChanged: (_) {},
          onRouteExit: () {},
        );
        coordinator.detachScreen(currentScreen);
        currentScreen = nextAudioScreen;

        expect(coordinator.isScreenActive(currentScreen), isTrue);
        expect(coordinator.isEnded, isFalse);
        expect(coordinator.isTearingDown, isFalse);
        expect(coordinator.connectedAt, startTime);
        expect(coordinator.currentDuration.inSeconds >= 30, isTrue);
        expect(MultiCallCoordinator.instance.getCallType(callId), 'audio');
      }

      coordinator.detachScreen(currentScreen);
      expect(coordinator.isEnded, isFalse);
      VorynCallRuntimeCoordinator.remove(callId);
    });

    test('allowAutoUpgrade defaults to true and can be disabled to prevent downgrade bounce-back loop', () {
      const defaultAudioScreen = ActiveAudioCallScreen(callId: 'call-auto-default');
      expect(defaultAudioScreen.allowAutoUpgrade, isTrue);

      const noAutoAudioScreen = ActiveAudioCallScreen(
        callId: 'call-auto-disabled',
        allowAutoUpgrade: false,
      );
      expect(noAutoAudioScreen.allowAutoUpgrade, isFalse);
    });
  });

  group('Audio to Video Call Upgrade Widget Flow Tests', () {
    testWidgets('ActiveAudioCallScreen renders Video upgrade action in control tray', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-audio-call/test-widget-audio-01'),
      );
      await tester.pump();

      // Verify Video upgrade button is visible in tray
      final videoButton = find.text('Video');
      expect(videoButton, findsOneWidget);

      // Tap Video upgrade button
      await tester.tap(videoButton);
      await tester.pump(const Duration(milliseconds: 300));

      // Call is still alive and does not trigger unhandled exception
      final coordinator = VorynCallRuntimeCoordinator.forCall('test-widget-audio-01');
      expect(coordinator.isEnded, isFalse);
      VorynCallRuntimeCoordinator.remove('test-widget-audio-01');
    });

    testWidgets('ActiveVideoCallScreen renders camera, flip, and controls without overflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/test-widget-video-01'),
      );
      await tester.pump();

      // Controls on video call screen
      expect(find.text('Flip'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);

      final coordinator = VorynCallRuntimeCoordinator.forCall('test-widget-video-01');
      expect(coordinator.isEnded, isFalse);
      VorynCallRuntimeCoordinator.remove('test-widget-video-01');
    });

    testWidgets('End Call on ActiveVideoCallScreen initiates coordinator teardown', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/test-widget-end-01'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final coordinator = VorynCallRuntimeCoordinator.forCall('test-widget-end-01');

      final endButton = find.byIcon(Icons.call_end_rounded);
      expect(endButton, findsOneWidget);

      await tester.tap(endButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(coordinator.isEnded || coordinator.isTearingDown, isTrue);
      VorynCallRuntimeCoordinator.remove('test-widget-end-01');
    });
  });
}
