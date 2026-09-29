import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/features/calling/widgets/call_waiting_banner.dart';
import 'package:voryn/features/calling/widgets/held_call_bar.dart';
import 'package:voryn/main.dart';

void main() {
  testWidgets(
    'Incoming call route renders full screen outside bottom nav shell',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/incoming-call/test-call-001'),
      );
      await tester.pump();

      // Verify incoming call UI elements
      expect(find.text('SECURE CALL · DIRECT TRANSPORT'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Remind'), findsOneWidget);

      // Verify it is NOT wrapped in VorynShell (no bottom nav)
      expect(find.text('Recents'), findsNothing);
      expect(find.text('Contacts'), findsNothing);
      expect(find.text('Meetings'), findsNothing);
    },
  );

  testWidgets(
    'Active audio call route renders 2x3 tray and waveform outside shell',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-audio-call/test-call-002'),
      );
      await tester.pump();

      // Verify Stitch Screen 2 elements
      expect(find.text('SECURE CALL'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Hold'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.text('HD VOICE'), findsOneWidget);

      // Verify shell isolation
      expect(find.text('Recents'), findsNothing);
      expect(find.text('Contacts'), findsNothing);
      expect(find.text('Meetings'), findsNothing);
    },
  );

  testWidgets(
    'Active video call route renders PiP and 2x3 controls outside shell',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-video-call/test-call-003'),
      );
      await tester.pump();

      // Verify Stitch Screen 3 elements
      expect(find.text('HD'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Flip'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);

      // Verify shell isolation
      expect(find.text('Recents'), findsNothing);
      expect(find.text('Contacts'), findsNothing);
      expect(find.text('Meetings'), findsNothing);
    },
  );

  testWidgets(
    'Group call route renders speaker spotlight and strip outside shell',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/group-call/test-meet-004'),
      );
      await tester.pump();

      // Verify Stitch Screen 6 elements
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Flip'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);

      // Verify shell isolation
      expect(find.text('Recents'), findsNothing);
      expect(find.text('Contacts'), findsNothing);
    },
  );

  testWidgets(
    'Tapping add participant on active audio call opens AddParticipantSheet',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const VorynApp(initialLocation: '/active-audio-call/test-call-005'),
      );
      await tester.pump();

      final addParticipantBtn = find.byTooltip('Add participant');
      expect(addParticipantBtn, findsOneWidget);

      await tester.tap(addParticipantBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add People to Call'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets(
    'CallWaitingBanner renders caller identity and triggers action callbacks',
    (tester) async {
      var declined = false;
      var heldAndAccepted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CallWaitingBanner(
                callerName: 'Vikash Chaurasiya',
                callType: 'audio',
                onDecline: () => declined = true,
                onHoldAndAccept: () => heldAndAccepted = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Call Waiting'), findsOneWidget);
      expect(find.text('Vikash Chaurasiya'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Hold & Accept'), findsOneWidget);

      await tester.tap(find.text('Decline'));
      expect(declined, isTrue);

      await tester.tap(find.text('Hold & Accept'));
      expect(heldAndAccepted, isTrue);
    },
  );

  testWidgets(
    'HeldCallBar renders held contact and triggers switch callback',
    (tester) async {
      var switched = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HeldCallBar(
                heldContactName: 'Lucky',
                onSwitch: () => switched = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('On hold: Lucky'), findsOneWidget);
      expect(find.text('Switch'), findsOneWidget);

      await tester.tap(find.text('Switch'));
      expect(switched, isTrue);
    },
  );
}
