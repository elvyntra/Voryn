// Model classes for Voryn Persistent Call Messages

class VorynMessageThread {
  const VorynMessageThread({
    required this.threadId,
    required this.otherUserUid,
    required this.otherUserName,
    required this.otherUserVorynId,
    this.otherUserAvatarUrl,
    this.lastMessageId,
    this.lastMessageBody,
    this.lastMessageSenderUid,
    this.lastMessageCreatedAt,
    this.lastMessageRemindToCall = false,
    this.unreadCount = 0,
  });

  final String threadId;
  final String otherUserUid;
  final String otherUserName;
  final String otherUserVorynId;
  final String? otherUserAvatarUrl;
  final String? lastMessageId;
  final String? lastMessageBody;
  final String? lastMessageSenderUid;
  final DateTime? lastMessageCreatedAt;
  final bool lastMessageRemindToCall;
  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  factory VorynMessageThread.fromMap(Map<String, dynamic> map) {
    final threadId = (map['thread_id'] ?? '').toString();
    final otherUid = (map['other_user_uid'] ?? '').toString();
    final nameStr = map['other_user_name']?.toString().trim();
    final vorynIdStr = map['other_user_voryn_id']?.toString().trim() ?? '';
    final name = (nameStr != null && nameStr.isNotEmpty)
        ? nameStr
        : (vorynIdStr.isNotEmpty ? vorynIdStr : 'Voryn User');

    return VorynMessageThread(
      threadId: threadId,
      otherUserUid: otherUid,
      otherUserName: name,
      otherUserVorynId: vorynIdStr,
      otherUserAvatarUrl: map['other_user_avatar_url']?.toString(),
      lastMessageId: map['last_message_id']?.toString(),
      lastMessageBody: map['last_message_body']?.toString(),
      lastMessageSenderUid: map['last_message_sender_uid']?.toString(),
      lastMessageCreatedAt: map['last_message_created_at'] != null
          ? DateTime.tryParse(map['last_message_created_at'].toString())
          : null,
      lastMessageRemindToCall: map['last_message_remind_to_call'] == true,
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  VorynMessageThread copyWith({
    String? lastMessageId,
    String? lastMessageBody,
    String? lastMessageSenderUid,
    DateTime? lastMessageCreatedAt,
    bool? lastMessageRemindToCall,
    int? unreadCount,
  }) {
    return VorynMessageThread(
      threadId: threadId,
      otherUserUid: otherUserUid,
      otherUserName: otherUserName,
      otherUserVorynId: otherUserVorynId,
      otherUserAvatarUrl: otherUserAvatarUrl,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageBody: lastMessageBody ?? this.lastMessageBody,
      lastMessageSenderUid: lastMessageSenderUid ?? this.lastMessageSenderUid,
      lastMessageCreatedAt: lastMessageCreatedAt ?? this.lastMessageCreatedAt,
      lastMessageRemindToCall:
          lastMessageRemindToCall ?? this.lastMessageRemindToCall,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

enum VorynMessageDeliveryStatus { sending, sent, failed }

class VorynMessage {
  const VorynMessage({
    required this.id,
    required this.threadId,
    required this.senderUid,
    required this.recipientUid,
    required this.senderName,
    required this.senderVorynId,
    required this.body,
    required this.remindToCall,
    required this.createdAt,
    this.clientMessageId,
    this.status = VorynMessageDeliveryStatus.sent,
  });

  final String id;
  final String threadId;
  final String senderUid;
  final String recipientUid;
  final String senderName;
  final String senderVorynId;
  final String body;
  final bool remindToCall;
  final DateTime createdAt;
  final String? clientMessageId;
  final VorynMessageDeliveryStatus status;

  bool isOutgoing(String currentUid) => senderUid == currentUid;

  factory VorynMessage.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString();
    final threadId = (map['thread_id'] ?? '').toString();
    final senderUid = (map['sender_uid'] ?? '').toString();
    final recipientUid = (map['recipient_uid'] ?? '').toString();
    final nameStr = map['sender_name']?.toString().trim();
    final vorynIdStr = map['sender_voryn_id']?.toString().trim() ?? '';
    final senderName = (nameStr != null && nameStr.isNotEmpty)
        ? nameStr
        : (vorynIdStr.isNotEmpty ? vorynIdStr : 'Voryn User');
    final body = (map['body'] ?? '').toString();
    final remind = map['remind_to_call'] == true;
    final createdAt = map['created_at'] != null
        ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
        : DateTime.now();
    final clientMsgId = map['client_message_id']?.toString();

    return VorynMessage(
      id: id,
      threadId: threadId,
      senderUid: senderUid,
      recipientUid: recipientUid,
      senderName: senderName,
      senderVorynId: vorynIdStr,
      body: body,
      remindToCall: remind,
      createdAt: createdAt,
      clientMessageId: clientMsgId,
      status: VorynMessageDeliveryStatus.sent,
    );
  }

  VorynMessage copyWith({String? id, VorynMessageDeliveryStatus? status}) {
    return VorynMessage(
      id: id ?? this.id,
      threadId: threadId,
      senderUid: senderUid,
      recipientUid: recipientUid,
      senderName: senderName,
      senderVorynId: senderVorynId,
      body: body,
      remindToCall: remindToCall,
      createdAt: createdAt,
      clientMessageId: clientMessageId,
      status: status ?? this.status,
    );
  }
}
