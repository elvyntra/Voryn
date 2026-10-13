import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/messages/voryn_message_models.dart';
import 'package:voryn/features/recents/recents_live_screen.dart';
import 'package:voryn/shared/widgets/voryn_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: VorynTheme.light,
    darkTheme: VorynTheme.dark,
    home: Scaffold(body: child),
  );
}

void main() {
  group('Recents Multi-Select Verification', () {
    testWidgets('Recents live screen does not show permanent delete buttons',
        (tester) async {
      await tester.pumpWidget(_wrap(const RecentsLiveScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Recents'), findsOneWidget);
      expect(find.text('Select all'), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });
  });

  group('VorynCard Long Press', () {
    testWidgets('Triggers onLongPress callback', (tester) async {
      bool longPressed = false;
      await tester.pumpWidget(
        _wrap(
          VorynCard(
            onLongPress: () {
              longPressed = true;
            },
            child: const Text('Card Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Card Content'));
      await tester.pumpAndSettle();

      expect(longPressed, isTrue);
    });
  });

  group('VorynMessage Model Actions', () {
    test('displayBody returns body for normal message and indicates deleted', () {
      final msg = VorynMessage(
        id: 'msg-1',
        threadId: 'thread-1',
        senderUid: 'user-1',
        recipientUid: 'user-2',
        senderName: 'Alice',
        senderVorynId: 'alice',
        body: 'Hello VoRyn',
        remindToCall: false,
        createdAt: DateTime.now(),
      );
      expect(msg.displayBody, equals('Hello VoRyn'));
      expect(msg.isDeleted, isFalse);

      final deletedMsg = msg.copyWith(deletedAt: DateTime.now(), body: null);
      expect(deletedMsg.isDeleted, isTrue);
      expect(deletedMsg.displayBody, equals('Message deleted'));
    });
  });
}

