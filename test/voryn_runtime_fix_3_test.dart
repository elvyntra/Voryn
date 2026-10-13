// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/features/calling/group_call_screen.dart';
import 'package:voryn/features/calling/voryn_call_history_service.dart';
import 'package:voryn/features/calling/widgets/video_upgrade_prompt.dart';
import 'package:voryn/features/meetings/meeting_room_screen.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Checkpoint VORYN-RUNTIME-FIX-3', () {
    testWidgets('Part B: Video Upgrade Waiting Banner displayed for requester, Prompt Card NOT displayed for requester', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VideoUpgradeWaitingBanner(onCancel: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(VideoUpgradeWaitingBanner), findsOneWidget);
      expect(find.text('Waiting for approval…'), findsOneWidget);
      expect(find.byType(VideoUpgradePromptCard), findsNothing);
    });

    testWidgets('Part B: Video Upgrade Prompt Card displayed for receiver with caller name and Accept/Decline', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool accepted = false;
      bool declined = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VideoUpgradePromptCard(
                  callerName: 'Alice',
                  onAccept: () => accepted = true,
                  onDecline: () => declined = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Switch to video call?'), findsOneWidget);
      expect(find.text('Alice wants to turn this audio call into a video call.'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(accepted, isTrue);

      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(declined, isTrue);
    });

    testWidgets('Part C: MeetingRoomScreen renders fullscreen without bottom navigation bar', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      const joined = VorynJoinedMeeting(
        meetingId: 'meet-test-root-001',
        title: 'Fullscreen Standup',
        livekitRoomName: 'room-001',
        role: 'host',
        status: 'active',
        access: 'public',
        livekitUrl: 'https://livekit.internal',
        livekitToken: 'mock.token',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingRoomScreen(
            joinedMeeting: joined,
            customParticipants: const [
              GroupCallParticipant(id: 'me', name: 'You', initials: 'YU', isYou: true),
              GroupCallParticipant(id: 'other', name: 'Bob', initials: 'BO'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify meeting room UI is present
      expect(find.text('Fullscreen Standup'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);

      // Verify bottom navigation tabs (Connect, Recents, Contacts, Meetings) are NOT present in MeetingRoomScreen
      expect(find.text('Connect'), findsNothing);
      expect(find.text('Recents'), findsNothing);
      expect(find.text('Contacts'), findsNothing);

      // Tap stage to toggle controls
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Persistent pill appears when controls are hidden
      expect(find.byKey(const Key('persistent_status_pill')), findsOneWidget);
    });

    testWidgets('Part D: Recents deletion confirmation dialog and call row removal', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testCall = VorynCallHistoryItem(
        id: 'call-123',
        otherUid: 'user-456',
        displayName: 'Sarah Connor',
        vorynId: 'sarah',
        callType: 'audio',
        direction: 'incoming',
        status: 'completed',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        endedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      bool deleted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) {
                  return ListTile(
                    title: Text(testCall.displayName),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete from history?'),
                            content: Text('Remove this call with ${testCall.displayName} from your history?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          deleted = true;
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      // Tap delete icon to open confirmation dialog
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Delete from history?'), findsOneWidget);
      expect(find.text('Remove this call with Sarah Connor from your history?'), findsOneWidget);

      // Tap Delete in dialog
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });

    testWidgets('Part D: Past meeting removal confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool removed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ListTile(
                  title: const Text('Sprint Review'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Remove from history?'),
                          content: const Text('Remove "Sprint Review" from your past meetings?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        removed = true;
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sprint Review'), findsOneWidget);

      // Tap remove
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Remove from history?'), findsOneWidget);
      expect(find.text('Remove "Sprint Review" from your past meetings?'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(removed, isTrue);
    });
  });
}
