import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';

class VorynCallMessage {
  const VorynCallMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.senderVorynId,
    required this.body,
    required this.remindToCall,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String senderVorynId;
  final String body;
  final bool remindToCall;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory VorynCallMessage.fromMap(Map<String, dynamic> map) {
    return VorynCallMessage(
      id: map['id'] as String,
      senderUid: map['sender_uid'] as String,
      senderName: (map['sender_name'] as String?)?.trim().isNotEmpty == true
          ? map['sender_name'] as String
          : map['sender_voryn_id'] as String? ?? 'Voryn user',
      senderVorynId: map['sender_voryn_id'] as String? ?? '',
      body: map['body'] as String? ?? '',
      remindToCall: map['remind_to_call'] == true,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      readAt: DateTime.tryParse(map['read_at'] as String? ?? ''),
    );
  }
}

class VorynCallMessageResult {
  const VorynCallMessageResult({this.error});

  final String? error;
  bool get isSuccess => error == null;
}

class VorynCallMessageService {
  const VorynCallMessageService();

  SupabaseClient? get _client => VorynBackend.client;

  Future<List<VorynCallMessage>> loadInbox() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Sign in to view call messages.');
    }
    final rows = await client.rpc('list_my_call_messages');
    return (rows as List<dynamic>)
        .map(
          (row) =>
              VorynCallMessage.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<VorynCallMessageResult> send({
    required String recipientVorynId,
    required String body,
    required bool remindToCall,
  }) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return const VorynCallMessageResult(
        error: 'Sign in before sending a message.',
      );
    }
    final message = body.trim();
    if (message.isEmpty || message.length > 120) {
      return const VorynCallMessageResult(
        error: 'Messages must be between 1 and 120 characters.',
      );
    }
    try {
      await client.rpc(
        'send_call_message',
        params: {
          'candidate': recipientVorynId,
          'message_body': message,
          'remind': remindToCall,
        },
      );
      return const VorynCallMessageResult();
    } on PostgrestException catch (error) {
      return VorynCallMessageResult(error: error.message);
    } catch (_) {
      return const VorynCallMessageResult(
        error: 'Could not send this message. Please try again.',
      );
    }
  }

  Future<void> markRead(String messageId) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return;
    await client.rpc(
      'mark_call_message_read',
      params: {'message_uuid': messageId},
    );
  }
}
