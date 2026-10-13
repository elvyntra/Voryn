import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/calling/active_video_call_screen.dart';
import 'package:voryn/features/calling/voryn_call_runtime_coordinator.dart';
import 'package:voryn/features/calling/widgets/call_top_bar.dart';
import 'package:voryn/features/calling/widgets/video_pip.dart';
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

  const testUser = VorynMockUser(
    backendUid: 'user-uuid-1234',
    customName: 'Jane Doe',
    name: 'Jane Doe',
    id: '@janedoe',
    phone: '+1234567890',
    email: 'jane@example.com',
    presence: VorynPresenceStatus.online,
    initials: 'JD',
  );

  Widget wrapScreen(String callId) {
    return MaterialApp(
      theme: VorynTheme.light,
      darkTheme: VorynTheme.dark,
      home: ActiveVideoCallScreen(
        callId: callId,
        user: testUser,
      ),
    );
  }

  group('Part C — Active Video Call Fullscreen UX Verification Tests', () {
    testWidgets('1. Calling badge is not displayed once connected',
        (tester) async {
      const callId = 'test-ux-badge-01';
      await tester.pumpWidget(wrapScreen(callId));
      await tester.pumpAndSettle();

      // In fallback/connected state, the persistent status pill should not display "Calling…" or "Ringing…"
      expect(find.byKey(const Key('persistent_call_status_pill')), findsNothing);
      expect(find.text('Calling…'), findsNothing);
      expect(find.text('Ringing…'), findsNothing);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('2. Immersive mode toggles controls on empty space tap',
        (tester) async {
      const callId = 'test-ux-immersive-01';
      await tester.pumpWidget(wrapScreen(callId));
      await tester.pumpAndSettle();

      // Top bar and tray should be visible initially
      final topBarOpacityFinder = find.ancestor(
        of: find.byType(CallTopBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        1.0,
      );

      // Tap on empty space (middle of screen)
      await tester.tapAt(const Offset(150, 300));
      await tester.pumpAndSettle();

      // Now controls must be hidden
      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        0.0,
      );

      // Tap again to restore
      await tester.tapAt(const Offset(150, 300));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AnimatedOpacity>(topBarOpacityFinder.first).opacity,
        1.0,
      );

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('3. Layout toggle switches between PiP mode and 50/50 Split view',
        (tester) async {
      const callId = 'test-ux-split-01';
      await tester.pumpWidget(wrapScreen(callId));
      await tester.pumpAndSettle();

      // Initially in PiP mode: VideoPip exists
      expect(find.byType(VideoPip), findsOneWidget);
      expect(find.byKey(const Key('layout_toggle_button')), findsOneWidget);

      // Tap layout toggle button to switch to 50/50 Split
      await tester.tap(find.byKey(const Key('layout_toggle_button')));
      await tester.pumpAndSettle();

      // In 50/50 Split mode: VideoPip is hidden, both remote and local placeholders/renderers are present
      expect(find.byType(VideoPip), findsNothing);
      expect(find.text('Jane Doe'), findsAtLeastNWidgets(1));
      expect(find.text('You'), findsOneWidget);

      // Tap layout toggle button again to return to PiP
      await tester.tap(find.byKey(const Key('layout_toggle_button')));
      await tester.pumpAndSettle();

      // Returned to PiP mode
      expect(find.byType(VideoPip), findsOneWidget);

      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('4. VideoPip drag gesture clamps to safe screen bounds',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      const callId = 'test-ux-drag-01';
      await tester.pumpWidget(wrapScreen(callId));
      await tester.pumpAndSettle();

      final pipFinder = find.byType(VideoPip);
      expect(pipFinder, findsOneWidget);

      final initialRect = tester.getRect(pipFinder);

      // Drag PiP up and to the left
      await tester.drag(pipFinder, const Offset(-50, -100));
      await tester.pumpAndSettle();

      final updatedRect = tester.getRect(pipFinder);
      expect(updatedRect.top, lessThan(initialRect.top));

      // Attempt to drag completely offscreen
      await tester.drag(pipFinder, const Offset(-1000, -1000));
      await tester.pumpAndSettle();

      final clampedRect = tester.getRect(pipFinder);
      // PiP must stay within visible screen bounds
      expect(clampedRect.left, greaterThanOrEqualTo(0.0));
      expect(clampedRect.top, greaterThanOrEqualTo(0.0));

      VorynCallRuntimeCoordinator.remove(callId);
    });
  });
}
