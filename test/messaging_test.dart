import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/features/messages/voryn_message_local_store.dart';
import 'package:voryn/features/messages/voryn_message_models.dart';

void main() {
  group('Voryn Persistent Call Messages Tests', () {
    test('VorynMessageThread correctly parses from Map and reports unread', () {
      final map = {
        'thread_id': 'thread-123',
        'other_user_uid': 'user-456',
        'other_user_name': 'Jane Doe',
        'other_user_voryn_id': 'jane_doe',
        'other_user_avatar_url': null,
        'last_message_id': 'msg-789',
        'last_message_body': 'Can you call me?',
        'last_message_sender_uid': 'user-456',
        'last_message_created_at': '2026-09-21T10:00:00Z',
        'last_message_remind_to_call': true,
        'unread_count': 2,
      };

      final thread = VorynMessageThread.fromMap(map);

      expect(thread.threadId, 'thread-123');
      expect(thread.otherUserName, 'Jane Doe');
      expect(thread.otherUserVorynId, 'jane_doe');
      expect(thread.lastMessageBody, 'Can you call me?');
      expect(thread.lastMessageRemindToCall, isTrue);
      expect(thread.unreadCount, 2);
      expect(thread.hasUnread, isTrue);
    });

    test(
      'VorynMessage correctly identifies outgoing vs incoming without read receipts',
      () {
        final msg = VorynMessage(
          id: 'msg-001',
          threadId: 'thread-001',
          senderUid: 'my-uid',
          recipientUid: 'other-uid',
          senderName: 'Me',
          senderVorynId: 'me',
          body: 'Hello there',
          remindToCall: false,
          createdAt: DateTime.now(),
          clientMessageId: 'client-001',
        );

        expect(msg.isOutgoing('my-uid'), isTrue);
        expect(msg.isOutgoing('other-uid'), isFalse);
      },
    );

    test('VorynMessageLocalStore manages drafts and outbox cleanly', () {
      final store = VorynMessageLocalStore.instance;

      store.saveDraft('thread-abc', 'Draft text');
      expect(store.getDraft('thread-abc'), 'Draft text');

      store.clearDraft('thread-abc');
      expect(store.getDraft('thread-abc'), '');

      final outboxMsg = VorynMessage(
        id: 'tmp-1',
        threadId: 'thread-abc',
        senderUid: 'me',
        recipientUid: 'other',
        senderName: 'Me',
        senderVorynId: 'me',
        body: 'Outbox message',
        remindToCall: true,
        createdAt: DateTime.now(),
        clientMessageId: 'client-abc',
        status: VorynMessageDeliveryStatus.sending,
      );

      store.addToOutbox(outboxMsg);
      expect(store.getOutboxForThread('thread-abc').length, 1);

      store.updateOutboxStatus(
        'client-abc',
        VorynMessageDeliveryStatus.sent,
        realId: 'real-123',
      );
      final updated = store.getOutboxForThread('thread-abc').first;
      expect(updated.id, 'real-123');
      expect(updated.status, VorynMessageDeliveryStatus.sent);

      store.removeFromOutbox('client-abc');
      expect(store.getOutboxForThread('thread-abc'), isEmpty);
    });

    test(
      'VorynMessageThread handles null/empty fields and fallbacks gracefully',
      () {
        final map = {
          'thread_id': 'thread-999',
          'other_user_uid': 'user-999',
          'other_user_name': null,
          'other_user_voryn_id': null,
          'other_user_avatar_url': null,
          'last_message_id': null,
          'last_message_body': null,
          'last_message_sender_uid': null,
          'last_message_created_at': null,
          'last_message_remind_to_call': null,
          'unread_count': null,
        };

        final thread = VorynMessageThread.fromMap(map);
        expect(thread.threadId, 'thread-999');
        expect(thread.otherUserUid, 'user-999');
        expect(thread.otherUserName, 'Voryn User');
        expect(thread.otherUserVorynId, '');
        expect(thread.lastMessageBody, isNull);
        expect(thread.unreadCount, 0);
        expect(thread.hasUnread, isFalse);
      },
    );

    test('VorynMessage handles null/empty fields and fallbacks gracefully', () {
      final map = {
        'id': 'msg-999',
        'thread_id': null,
        'sender_uid': 'sender-1',
        'recipient_uid': null,
        'sender_name': null,
        'sender_voryn_id': null,
        'body': 'Quick hello',
        'remind_to_call': null,
        'created_at': null,
      };

      final msg = VorynMessage.fromMap(map);
      expect(msg.id, 'msg-999');
      expect(msg.threadId, '');
      expect(msg.senderUid, 'sender-1');
      expect(msg.recipientUid, '');
      expect(msg.senderName, 'Voryn User');
      expect(msg.body, 'Quick hello');
      expect(msg.remindToCall, isFalse);
      expect(msg.status, VorynMessageDeliveryStatus.sent);
    });
  });
}
