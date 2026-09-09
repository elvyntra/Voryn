import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/main.dart';
import 'package:voryn/features/connect/connect_screen.dart';

void main() {
  testWidgets('Voryn auth flow renders welcome and sign in screens', (
    tester,
  ) async {
    await tester.pumpWidget(const VorynApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Voryn'), findsOneWidget);
    expect(find.text('Connect your way.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);

    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('Forgot password shows check email success state', (
    tester,
  ) async {
    await tester.pumpWidget(const VorynApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'person@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text('We sent a reset link to person@example.com.'),
      findsOneWidget,
    );
  });

  testWidgets('Voryn shell renders four primary tabs', (tester) async {
    await tester.pumpWidget(const VorynApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'person@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret1',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Connect'), findsWidgets);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Meetings'), findsOneWidget);
    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.byType(VorynKeyboard), findsOneWidget);

    await tester.tap(find.text('Recents'));
    await tester.pumpAndSettle();

    expect(find.text('Your recent Voryn calls'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Bhai'), findsWidgets);
    expect(find.text('Suggestions'), findsNothing);

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();

    expect(find.text('Your people on Voryn'), findsOneWidget);
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
  });
}
