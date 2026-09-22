import 'voryn_message_models.dart';

class ThreadClearCursor {
  final DateTime clearedBeforeCreatedAt;
  final String clearedBeforeMessageId;

  const ThreadClearCursor({
    required this.clearedBeforeCreatedAt,
    required this.clearedBeforeMessageId,
  });
}

class VorynMessageLocalStore {
  VorynMessageLocalStore._();
  static final VorynMessageLocalStore instance = VorynMessageLocalStore._();

  final Map<String, String> _drafts = {};
  final List<VorynMessage> _outbox = [];

  final Map<String, Set<String>> _hiddenMessagesByUser = {};
  final Map<String, Map<String, ThreadClearCursor>> _clearCursorsByUser = {};

  void markMessageHidden(String userUid, String messageId) {
    _hiddenMessagesByUser.putIfAbsent(userUid, () => <String>{}).add(messageId);
  }

  bool isMessageHidden(String userUid, String messageId) {
    return _hiddenMessagesByUser[userUid]?.contains(messageId) ?? false;
  }

  void setThreadClearCursor(
    String userUid,
    String threadId,
    DateTime createdAt,
    String messageId,
  ) {
    final threadMap = _clearCursorsByUser.putIfAbsent(
      userUid,
      () => <String, ThreadClearCursor>{},
    );
    final existing = threadMap[threadId];
    if (existing == null ||
        createdAt.isAfter(existing.clearedBeforeCreatedAt) ||
        (createdAt.isAtSameMomentAs(existing.clearedBeforeCreatedAt) &&
            messageId.compareTo(existing.clearedBeforeMessageId) >= 0)) {
      threadMap[threadId] = ThreadClearCursor(
        clearedBeforeCreatedAt: createdAt,
        clearedBeforeMessageId: messageId,
      );
    }
  }

  ThreadClearCursor? getThreadClearCursor(String userUid, String threadId) {
    return _clearCursorsByUser[userUid]?[threadId];
  }

  void clearThreadMessages(String threadId) {
    clearDraft(threadId);
    _outbox.removeWhere((m) => m.threadId == threadId);
  }

  void saveDraft(String threadId, String text) {
    if (text.trim().isEmpty) {
      _drafts.remove(threadId);
    } else {
      _drafts[threadId] = text;
    }
  }

  String getDraft(String threadId) => _drafts[threadId] ?? '';

  void clearDraft(String threadId) {
    _drafts.remove(threadId);
  }

  void addToOutbox(VorynMessage message) {
    _outbox.removeWhere((m) => m.clientMessageId == message.clientMessageId);
    _outbox.add(message);
  }

  void updateOutboxStatus(
    String clientMessageId,
    VorynMessageDeliveryStatus status, {
    String? realId,
  }) {
    final idx = _outbox.indexWhere((m) => m.clientMessageId == clientMessageId);
    if (idx != -1) {
      final current = _outbox[idx];
      _outbox[idx] = current.copyWith(id: realId, status: status);
    }
  }

  void removeFromOutbox(String clientMessageId) {
    _outbox.removeWhere((m) => m.clientMessageId == clientMessageId);
  }

  void purgeMessage(String messageId) {
    _outbox.removeWhere((m) => m.id == messageId);
  }

  List<VorynMessage> getOutboxForThread(String threadId) {
    return _outbox.where((m) => m.threadId == threadId).toList();
  }
}
