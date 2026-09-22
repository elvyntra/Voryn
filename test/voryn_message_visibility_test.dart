import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/features/messages/voryn_message_local_store.dart';

void main() {
  group('VorynMessageLocalStore Visibility & Clear Cursor', () {
    final store = VorynMessageLocalStore.instance;
    const userA = 'user-a';
    const userB = 'user-b';
    const threadId = 'thread-1';

    test('hidden message tracking is user-scoped', () {
      expect(store.isMessageHidden(userA, 'msg-1'), isFalse);
      expect(store.isMessageHidden(userB, 'msg-1'), isFalse);

      store.markMessageHidden(userA, 'msg-1');
      expect(store.isMessageHidden(userA, 'msg-1'), isTrue);
      expect(store.isMessageHidden(userB, 'msg-1'), isFalse);
    });

    test('clear cursor tracks monotonic latest tuple', () {
      final t1 = DateTime.utc(2026, 9, 22, 10, 0, 0);
      final t2 = DateTime.utc(2026, 9, 22, 10, 5, 0);

      store.setThreadClearCursor(userA, threadId, t1, '00000000-0000-0000-0000-000000000001');
      var cursor = store.getThreadClearCursor(userA, threadId);
      expect(cursor, isNotNull);
      expect(cursor!.clearedBeforeCreatedAt, equals(t1));
      expect(cursor.clearedBeforeMessageId, equals('00000000-0000-0000-0000-000000000001'));

      // Older cursor should not overwrite newer cursor
      final t0 = DateTime.utc(2026, 9, 22, 9, 50, 0);
      store.setThreadClearCursor(userA, threadId, t0, '00000000-0000-0000-0000-000000000009');
      cursor = store.getThreadClearCursor(userA, threadId);
      expect(cursor!.clearedBeforeCreatedAt, equals(t1));

      // Newer cursor updates
      store.setThreadClearCursor(userA, threadId, t2, '00000000-0000-0000-0000-000000000002');
      cursor = store.getThreadClearCursor(userA, threadId);
      expect(cursor!.clearedBeforeCreatedAt, equals(t2));
      expect(cursor.clearedBeforeMessageId, equals('00000000-0000-0000-0000-000000000002'));
    });

    test('clearing thread removes local drafts and outbox', () {
      store.saveDraft(threadId, 'Unsent message draft');
      expect(store.getDraft(threadId), equals('Unsent message draft'));

      store.clearThreadMessages(threadId);
      expect(store.getDraft(threadId), isEmpty);
    });
  });
}
