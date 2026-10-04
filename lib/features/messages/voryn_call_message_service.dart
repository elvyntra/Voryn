import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import 'voryn_message_repository.dart';

String _generateUuidV4() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

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
    String? clientMessageId,
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

    final cId = clientMessageId ?? _generateUuidV4();

    debugPrint(
      '[MESSAGE_SEND] action=quick_send_start candidate=$recipientVorynId remind=$remindToCall clientMessageId=$cId',
    );

    try {
      final messageId =
          await client.rpc(
                'send_call_message',
                params: {
                  'candidate': recipientVorynId,
                  'message_body': message,
                  'remind': remindToCall,
                  'p_client_message_id': cId,
                },
              )
              as String?;

      debugPrint(
        '[MESSAGE_SEND] action=quick_send_success messageId=$messageId candidate=$recipientVorynId',
      );

      if (messageId != null) {
        VorynMessageRepository.instance.notifyThreadsChanged();
      }
      return const VorynCallMessageResult();
    } on PostgrestException catch (error, st) {
      debugPrint(
        '[MESSAGE_SEND] action=quick_send_error postgrestError=${error.message} code=${error.code}\n$st',
      );
      final rawMsg = error.message.toLowerCase();
      String friendlyError;
      if (rawMsg.contains('user not found')) {
        friendlyError = 'User not found.';
      } else if (rawMsg.contains('messaging unavailable') || rawMsg.contains('blocked')) {
        friendlyError = 'Messaging is unavailable for this user.';
      } else if (rawMsg.contains('authentication required')) {
        friendlyError = 'Sign in before sending a message.';
      } else if (rawMsg.contains('invalid message')) {
        friendlyError = 'Messages must be between 1 and 120 characters.';
      } else {
        friendlyError = "Couldn't send message. Please try again.";
      }
      return VorynCallMessageResult(error: friendlyError);
    } catch (e, st) {
      debugPrint('[MESSAGE_SEND] action=quick_send_error error=$e\n$st');
      return const VorynCallMessageResult(
        error: "Couldn't send message. Please try again.",
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
