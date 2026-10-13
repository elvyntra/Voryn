import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/calling/active_video_call_screen.dart';
import 'package:voryn/features/calling/voryn_call_runtime_coordinator.dart';
import 'package:voryn/features/calling/widgets/call_controls.dart';
import 'package:voryn/features/calling/widgets/call_top_bar.dart';
import 'package:voryn/features/calling/widgets/video_pip.dart';
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

  group('Checkpoint VIDEO-UI-2: Immersive Video Call UI Tests', () {
    testWidgets('1. Controls initially visible', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-init-01';
      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/$callId'),
      );
      await tester.pump();

      // Controls must be rendered
      expect(find.byType(CallTopBar), findsOneWidget);
      expect(find.byType(CallControlTray), findsOneWidget);
      expect(find.text('Switch to Audio'), findsOneWidget);

      // Core actions present in tray
      expect(find.text('Flip'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);
      expect(find.text('Hold'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);

      // Verify opacity is 1.0 (visible)
      final topBarOpacityFinder = find.ancestor(
        of: find.byType(CallTopBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        1.0,
      );

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('2. Tap main video hides controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-hide-01';
      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/$callId'),
      );
      await tester.pump();

      final topBarOpacityFinder = find.ancestor(
        of: find.byType(CallTopBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        1.0,
      );

      // Tap main video surface in center (away from PIP)
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();

      // Controls must now be hidden
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        0.0,
      );

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('3. Tap again restores controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-restore-01';
      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/$callId'),
      );
      await tester.pump();

      final topBarOpacityFinder = find.ancestor(
        of: find.byType(CallTopBar),
        matching: find.byType(AnimatedOpacity),
      );

      // Hide controls
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        0.0,
      );

      // Tap again to restore controls
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        1.0,
      );

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('4. Floating PIP remains visible when controls hide', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-pip-persist-01';
      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/$callId'),
      );
      await tester.pump();

      expect(find.byType(VideoPip), findsOneWidget);

      // Hide controls
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();

      // Floating PIP must remain visible
      expect(find.byType(VideoPip), findsOneWidget);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('5. Tapping PIP swaps dominant and PIP video tracks', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-swap-01';
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: ActiveVideoCallScreen(
            callId: callId,
            user: testUser,
          ),
        ),
      );
      await tester.pump();

      // Initially: PIP is Local ('You'), dominant shows remote contact ('Vikash Chaurasiya')
      final pipWidget = find.byType(VideoPip);
      expect(pipWidget, findsOneWidget);
      expect(find.descendant(of: pipWidget, matching: find.text('You')), findsOneWidget);
      expect(find.text('Vikash Chaurasiya'), findsWidgets);

      // Tap PIP to swap view
      await tester.tap(pipWidget);
      await tester.pumpAndSettle();

      // Dominant is now Local ('You'), PIP is Remote ('Vikash Chaurasiya')
      expect(find.descendant(of: pipWidget, matching: find.text('You')), findsNothing);
      expect(find.descendant(of: pipWidget, matching: find.text('Vikash Chaurasiya')), findsOneWidget);

      // Tap PIP again to swap back
      await tester.tap(pipWidget);
      await tester.pumpAndSettle();

      // Swapped back: PIP is Local ('You')
      expect(find.descendant(of: pipWidget, matching: find.text('You')), findsOneWidget);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('6. Tapping PIP does not toggle controls visibility', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-pip-no-toggle-01';
      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/$callId'),
      );
      await tester.pump();

      final topBarOpacityFinder = find.ancestor(
        of: find.byType(CallTopBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        1.0,
      );

      // Tap PIP
      final pipFinder = find.byType(VideoPip);
      await tester.tap(pipFinder);
      await tester.pumpAndSettle();

      // Controls must STILL be visible (opacity == 1.0)
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        1.0,
      );

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('7. Main/PIP swap does not reconnect room or recreate session', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-swap-no-reconnect-01';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final startTime = DateTime.now().subtract(const Duration(seconds: 15));
      coordinator.markConnected(startTime);

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: ActiveVideoCallScreen(
            callId: callId,
            user: testUser,
          ),
        ),
      );
      await tester.pump();

      final pipFinder = find.byType(VideoPip);

      // Perform multiple swaps
      for (int i = 0; i < 4; i++) {
        await tester.tap(pipFinder);
        await tester.pumpAndSettle();

        // Call state remains continuous
        expect(coordinator.isEnded, isFalse);
        expect(coordinator.isTearingDown, isFalse);
        expect(coordinator.connectedAt, startTime);
      }

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('8. Camera-off fallback avatar renders for local and remote', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-camera-off-01';
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: ActiveVideoCallScreen(
            callId: callId,
            user: testUser,
            initialCameraEnabled: false,
          ),
        ),
      );
      await tester.pump();

      // "Camera off" appears in placeholder and controls
      expect(find.text('Camera off'), findsWidgets);
      // Initials / name rendered in avatar
      expect(find.text('VC'), findsWidgets);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('9. Reconnecting indicator remains visible when controls are hidden', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ui-reconnecting-01';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: ActiveVideoCallScreen(
            callId: callId,
            user: testUser,
          ),
        ),
      );
      await tester.pump();

      // Hide controls
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();

      // Normal header is hidden
      final topBarOpacityFinder = find.ancestor(
        of: find.byType(CallTopBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        0.0,
      );

      // Trigger reconnecting event
      coordinator.notifyStatus('reconnecting');
      await tester.pumpAndSettle();

      // Persistent critical status pill MUST be visible with 'Reconnecting…'
      expect(find.byKey(const Key('persistent_call_status_pill')), findsOneWidget);
      expect(find.textContaining('Reconnecting'), findsOneWidget);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('10. Responsive layout tests across viewports with zero overflow', (
      tester,
    ) async {
      const viewports = [
        Size(360, 640),   // Narrow Android mobile
        Size(390, 844),   // Standard mobile (iPhone / Pixel)
        Size(768, 1024),  // Tablet portrait
        Size(1024, 768),  // Tablet landscape / Desktop
        Size(1440, 900),  // Wide Web
      ];

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        final callId = 'test-viewport-${size.width.toInt()}';
        await tester.pumpWidget(
          MaterialApp(
            theme: VorynTheme.dark,
            home: ActiveVideoCallScreen(
              callId: callId,
              user: testUser,
            ),
          ),
        );
        await tester.pump();

        // Verify zero RenderFlex overflows
        expect(tester.takeException(), isNull, reason: 'Overflow on viewport ${size.width}x${size.height}');

        // Verify essential elements rendered correctly
        expect(find.byType(CallControlTray), findsOneWidget);
        expect(find.byType(VideoPip), findsOneWidget);

        VorynCallRuntimeCoordinator.remove(callId);
      }

      tester.view.resetPhysicalSize();
    });
  });
}
