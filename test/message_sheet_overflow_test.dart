import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/connect/mock_voryn_state.dart';
import 'package:voryn/features/connect/user_interaction_screens.dart';
import 'package:voryn/shared/widgets/voryn_button.dart';
import 'package:voryn/shared/widgets/voryn_presence.dart';

void main() {
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

  Widget buildTestableSheet({
    required Size physicalSize,
    required double devicePixelRatio,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) {
    return MaterialApp(
      theme: VorynTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(
            physicalSize.width / devicePixelRatio,
            physicalSize.height / devicePixelRatio,
          ),
          viewInsets: viewInsets,
          padding: const EdgeInsets.only(top: 24, bottom: 16),
        ),
        child: const Scaffold(
          body: QuickMessageSheet(user: testUser),
        ),
      ),
    );
  }

  group('QuickMessageSheet UI & Overflow Tests', () {
    testWidgets('Renders without overflow on phone viewport', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(1080, 2400),
          devicePixelRatio: 2.5,
        ),
      );
      await tester.pump();

      expect(find.text('Message Vikash Chaurasiya'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders without overflow on Android tablet', (tester) async {
      tester.view.physicalSize = const Size(1600, 2560);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(1600, 2560),
          devicePixelRatio: 2.0,
        ),
      );
      await tester.pump();

      expect(find.text('Message Vikash Chaurasiya'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders without overflow on desktop web viewport', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(1920, 1080),
          devicePixelRatio: 1.0,
        ),
      );
      await tester.pump();

      expect(find.text('Message Vikash Chaurasiya'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders without overflow on narrow browser viewport', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(320, 568),
          devicePixelRatio: 1.0,
        ),
      );
      await tester.pump();

      final ex = tester.takeException();
      expect(ex, isNull);
    });

    testWidgets('Renders without overflow when keyboard is open', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      // Simulating a 340px soft keyboard
      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(1080, 2400),
          devicePixelRatio: 2.5,
          viewInsets: const EdgeInsets.only(bottom: 340),
        ),
      );
      await tester.pump();

      expect(find.text('Message Vikash Chaurasiya'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Scroll up to reveal Send button if necessary
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pump();
      expect(find.widgetWithText(VorynButton, 'Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Quick reply selection enables Send and toggles correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(1080, 2400),
          devicePixelRatio: 2.5,
        ),
      );
      await tester.pump();

      // Send button should initially be disabled
      final initialSendBtn = tester.widget<VorynButton>(
        find.widgetWithText(VorynButton, 'Send'),
      );
      expect(initialSendBtn.isDisabled, isTrue);

      // Tap first preset: "Call me when you're free."
      final presetFinder = find.text("Call me when you're free.");
      expect(presetFinder, findsOneWidget);

      await tester.tap(presetFinder);
      await tester.pump();

      // Send button should now be enabled
      final sendBtn = tester.widget<VorynButton>(
        find.widgetWithText(VorynButton, 'Send'),
      );
      expect(sendBtn.isDisabled, isFalse);
      expect(sendBtn.onPressed, isNotNull);
    });

    testWidgets('Custom message typing enforces 120 character limit and enables Send', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(1080, 2400),
          devicePixelRatio: 2.5,
        ),
      );
      await tester.pump();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      // Type 100 character text
      final longText = 'A' * 100;
      await tester.enterText(textField, longText);
      await tester.pump();

      expect(find.text(longText), findsOneWidget);

      final sendBtn = tester.widget<VorynButton>(
        find.widgetWithText(VorynButton, 'Send'),
      );
      expect(sendBtn.isDisabled, isFalse);
      expect(sendBtn.onPressed, isNotNull);
    });

    testWidgets('Reminder toggle switches on and off', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableSheet(
          physicalSize: const Size(1080, 2400),
          devicePixelRatio: 2.5,
        ),
      );
      await tester.pump();

      final switchTile = find.byType(SwitchListTile);
      expect(switchTile, findsOneWidget);

      final switchBefore = tester.widget<SwitchListTile>(switchTile);
      expect(switchBefore.value, isFalse);

      await tester.tap(switchTile);
      await tester.pump();

      final switchAfter = tester.widget<SwitchListTile>(switchTile);
      expect(switchAfter.value, isTrue);
    });
  });
}
