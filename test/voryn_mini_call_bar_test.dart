import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/calling/voryn_active_call_presentation_service.dart';
import 'package:voryn/features/calling/voryn_mini_call_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActiveCallSnapshot Model', () {
    test('getters evaluate active and minimized states correctly', () {
      const activeMinimized = ActiveCallSnapshot(
        callId: 'call-1',
        state: 'ACTIVE',
        presentation: 'MINIMIZED',
        callType: 'audio',
        displayName: 'Alice Walker',
        startedAt: 100000,
      );
      expect(activeMinimized.isActive, isTrue);
      expect(activeMinimized.isMinimized, isTrue);
      expect(activeMinimized.shouldShowMiniBar, isTrue);

      const activeFullscreen = ActiveCallSnapshot(
        callId: 'call-1',
        state: 'ACTIVE',
        presentation: 'FULLSCREEN',
        callType: 'audio',
        displayName: 'Alice Walker',
        startedAt: 100000,
      );
      expect(activeFullscreen.isActive, isTrue);
      expect(activeFullscreen.isMinimized, isFalse);
      expect(activeFullscreen.shouldShowMiniBar, isFalse);

      const terminal = ActiveCallSnapshot(
        callId: 'call-1',
        state: 'TERMINAL',
        presentation: 'MINIMIZED',
        callType: 'audio',
        displayName: 'Alice Walker',
        startedAt: 100000,
      );
      expect(terminal.isActive, isFalse);
      expect(terminal.shouldShowMiniBar, isFalse);
    });

    test('fromMap parses dynamic maps correctly', () {
      final map = {
        'callId': 'call-123',
        'state': 'ACTIVE',
        'presentation': 'MINIMIZED',
        'callType': 'video',
        'displayName': 'Bob Builder',
        'startedAt': 50000,
      };
      final snapshot = ActiveCallSnapshot.fromMap(map);
      expect(snapshot.callId, 'call-123');
      expect(snapshot.state, 'ACTIVE');
      expect(snapshot.presentation, 'MINIMIZED');
      expect(snapshot.callType, 'video');
      expect(snapshot.displayName, 'Bob Builder');
      expect(snapshot.startedAt, 50000);
      expect(snapshot.shouldShowMiniBar, isTrue);
    });
  });

  group('VorynMiniCallBar Widget', () {
    late VorynActiveCallPresentationService service;

    setUp(() {
      service = VorynActiveCallPresentationService.instance;
      service.clearSnapshot();
    });

    tearDown(() {
      service.clearSnapshot();
    });

    testWidgets('renders SizedBox.shrink when snapshot is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            bottomNavigationBar: VorynMiniCallBar(presentationService: service),
          ),
        ),
      );

      expect(find.byType(VorynMiniCallBar), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when ACTIVE + FULLSCREEN', (
      tester,
    ) async {
      service.setSnapshot(
        const ActiveCallSnapshot(
          callId: 'call-fs',
          state: 'ACTIVE',
          presentation: 'FULLSCREEN',
          callType: 'audio',
          displayName: 'Alice Fullscreen',
          startedAt: 10000,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            bottomNavigationBar: VorynMiniCallBar(presentationService: service),
          ),
        ),
      );

      expect(find.text('Alice Fullscreen'), findsNothing);
      expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
    });

    testWidgets('renders compact mini-bar when ACTIVE + MINIMIZED', (
      tester,
    ) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Started 75 seconds ago -> 01:15
      final startedAt = now - 75000;

      service.setSnapshot(
        ActiveCallSnapshot(
          callId: 'call-min',
          state: 'ACTIVE',
          presentation: 'MINIMIZED',
          callType: 'audio',
          displayName: 'Elena Rostova',
          startedAt: startedAt,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            bottomNavigationBar: VorynMiniCallBar(presentationService: service),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Elena Rostova'), findsOneWidget);
      expect(find.text('01:15'), findsOneWidget);
      expect(find.byIcon(Icons.call_rounded), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
    });

    testWidgets('renders long display name with ellipsis and no overflow', (
      tester,
    ) async {
      const veryLongName =
          'Dr. Alexander Bartholomew Montgomery III of Westminster';

      service.setSnapshot(
        const ActiveCallSnapshot(
          callId: 'call-long',
          state: 'ACTIVE',
          presentation: 'MINIMIZED',
          callType: 'video',
          displayName: veryLongName,
          startedAt: 10000,
        ),
      );

      // Set smaller mobile screen width
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            bottomNavigationBar: VorynMiniCallBar(presentationService: service),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(veryLongName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping mini-bar invokes returnToActiveCall', (tester) async {
      service.setSnapshot(
        const ActiveCallSnapshot(
          callId: 'call-tap',
          state: 'ACTIVE',
          presentation: 'MINIMIZED',
          callType: 'audio',
          displayName: 'David Kim',
          startedAt: 10000,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            bottomNavigationBar: VorynMiniCallBar(presentationService: service),
          ),
        ),
      );
      await tester.pump();

      final miniBarFinder = find.byType(VorynMiniCallBar);
      expect(miniBarFinder, findsOneWidget);

      await tester.tap(miniBarFinder);
      await tester.pump();

      // Upon tapping, the presentation transitions optimistically to FULLSCREEN
      expect(service.currentSnapshot?.presentation, 'FULLSCREEN');
      expect(find.text('David Kim'), findsNothing);
    });

    testWidgets('transition from MINIMIZED to TERMINAL hides mini-bar', (
      tester,
    ) async {
      service.setSnapshot(
        const ActiveCallSnapshot(
          callId: 'call-term',
          state: 'ACTIVE',
          presentation: 'MINIMIZED',
          callType: 'audio',
          displayName: 'Terminal User',
          startedAt: 10000,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            bottomNavigationBar: VorynMiniCallBar(presentationService: service),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Terminal User'), findsOneWidget);

      // Remote terminal arrives
      service.clearSnapshot();
      await tester.pump();

      expect(find.text('Terminal User'), findsNothing);
    });
  });
}
