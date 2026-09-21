import 'voryn_message_models.dart';

class VorynMessageLocalStore {
  VorynMessageLocalStore._();
  static final VorynMessageLocalStore instance = VorynMessageLocalStore._();

  final Map<String, String> _drafts = {};
  final List<VorynMessage> _outbox = [];

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

  List<VorynMessage> getOutboxForThread(String threadId) {
    return _outbox.where((m) => m.threadId == threadId).toList();
  }
}
