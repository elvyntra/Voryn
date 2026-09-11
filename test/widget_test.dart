import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/main.dart';

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

  testWidgets('Forgot password validates the email before submitting', (
    tester,
  ) async {
    await tester.pumpWidget(const VorynApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(find.text('Check your email'), findsNothing);
  });

  testWidgets('Password recovery route allows a new password to be entered', (
    tester,
  ) async {
    await tester.pumpWidget(const VorynApp(initialLocation: '/reset-password'));
    await tester.pumpAndSettle();

    expect(find.text('Create new password'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm new password'), findsOneWidget);
    expect(find.text('Save password'), findsOneWidget);
  });

  testWidgets('Onboarding does not show sample account data', (tester) async {
    await tester.pumpWidget(
      const VorynApp(initialLocation: '/onboarding/profile'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vikash Mishra'), findsNothing);
    expect(find.text('vikash@example.com'), findsNothing);
    expect(find.text('98765 43210'), findsNothing);
    expect(find.text('IN +91'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Onboarding requires a phone number without showing OTP UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      const VorynApp(initialLocation: '/onboarding/profile'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Send verification code'), findsNothing);
  });

  testWidgets('Voryn ID checks only on request and keeps keyboard focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      const VorynApp(initialLocation: '/onboarding/voryn-id'),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'vikash');
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Checking...'), findsNothing);
    expect(
      find.text('Enter an ID, then check whether it is available.'),
      findsOneWidget,
    );
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Check availability'));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('Voryn shell renders four primary tabs', (tester) async {
    await tester.pumpWidget(const VorynApp(initialLocation: '/connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsWidgets);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Meetings'), findsOneWidget);
    expect(find.text('Recently connected'), findsOneWidget);

    await tester.tap(find.text('Recents'));
    await tester.pumpAndSettle();

    expect(find.text('Your recent Voryn calls'), findsOneWidget);
    expect(find.text('No recent calls'), findsOneWidget);
    expect(find.text('Recently connected'), findsNothing);

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();

    expect(find.text('Your people on Voryn'), findsOneWidget);
    expect(find.text('My profile'), findsNothing);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.byTooltip('Refresh contacts'), findsOneWidget);
  });
}
