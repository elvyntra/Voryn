import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/backend/voryn_backend.dart';
import 'voryn_background_auth_bridge.dart';
import 'voryn_message_local_store.dart';
import 'voryn_message_models.dart';

class VorynMessageRepository {
  VorynMessageRepository._();
  static final VorynMessageRepository instance = VorynMessageRepository._();

  final ValueNotifier<int> totalUnreadCount = ValueNotifier<int>(0);
  final _messageStreamController = StreamController<VorynMessage>.broadcast();
  Stream<VorynMessage> get onMessageReceived => _messageStreamController.stream;

  final _messageUpdatedStreamController =
      StreamController<VorynMessage>.broadcast();
  Stream<VorynMessage> get onMessageUpdated =>
      _messageUpdatedStreamController.stream;

  final _messageDeletedForMeController =
      StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onMessageDeletedForMe =>
      _messageDeletedForMeController.stream;

  final _threadClearedController = StreamController<String>.broadcast();
  Stream<String> get onThreadCleared => _threadClearedController.stream;

  final _threadsChangedController = StreamController<void>.broadcast();
  Stream<void> get onThreadsChanged => _threadsChangedController.stream;

  SupabaseClient? get _client => VorynBackend.client;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _userHiddenChannel;
  RealtimeChannel? _userStateChannel;
  bool _subscribed = false;

  void notifyThreadsChanged() {
    _threadsChangedController.add(null);
    unawaited(refreshUnreadCount());
  }

  final _seenMessageIds = <String>{};
  StreamSubscription<Map<String, dynamic>>? _authBridgeIncomingSub;

  bool isVisibleToCurrentUser(
    String threadId,
    String messageId,
    DateTime createdAt,
  ) {
    final currentUid = _client?.auth.currentUser?.id;
    if (currentUid == null) return true;

    if (VorynMessageLocalStore.instance.isMessageHidden(
      currentUid,
      messageId,
    )) {
      return false;
    }

    final cursor = VorynMessageLocalStore.instance.getThreadClearCursor(
      currentUid,
      threadId,
    );
    if (cursor != null) {
      if (createdAt.isBefore(cursor.clearedBeforeCreatedAt)) {
        return false;
      }
      if (createdAt.isAtSameMomentAs(cursor.clearedBeforeCreatedAt) &&
          messageId.compareTo(cursor.clearedBeforeMessageId) <= 0) {
        return false;
      }
    }

    return true;
  }

  Future<void> syncUserVisibilityState() async {
    final client = _client;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) return;
    try {
      final stateRows = await client
          .from('message_user_thread_state')
          .select(
            'thread_id, cleared_before_created_at, cleared_before_message_id',
          );
      for (final row in stateRows as List) {
        final tid = row['thread_id'] as String?;
        final dt = row['cleared_before_created_at'] as String?;
        final mid = row['cleared_before_message_id'] as String?;
        if (tid != null && dt != null && mid != null) {
          VorynMessageLocalStore.instance.setThreadClearCursor(
            currentUid,
            tid,
            DateTime.parse(dt),
            mid,
          );
        }
      }

      final hiddenRows = await client
          .from('message_user_hidden_messages')
          .select('message_id');
      for (final row in hiddenRows as List) {
        final mid = row['message_id'] as String?;
        if (mid != null) {
          VorynMessageLocalStore.instance.markMessageHidden(currentUid, mid);
        }
      }
    } catch (e) {
      debugPrint(
        '[MESSAGE_VISIBILITY] error syncing user visibility state: $e',
      );
    }
  }

  void initializeRealtime() {
    if (_subscribed) return;
    final client = _client;
    if (client == null || client.auth.currentUser == null) return;

    _subscribed = true;
    unawaited(syncUserVisibilityState());

    _realtimeChannel = client
        .channel('public:call_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_messages',
          callback: (payload) {
            _handleIncomingRealtimeMessage(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_messages',
          callback: (payload) {
            _handleUpdatedRealtimeMessage(payload.newRecord);
          },
        )
        .subscribe();

    _userHiddenChannel = client
        .channel('public:message_user_hidden_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_user_hidden_messages',
          callback: (payload) {
            _handleIncomingHiddenMessage(payload.newRecord);
          },
        )
        .subscribe();

    _userStateChannel = client
        .channel('public:message_user_thread_state')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_user_thread_state',
          callback: (payload) {
            _handleIncomingThreadState(payload.newRecord);
          },
        )
        .subscribe();

    _authBridgeIncomingSub?.cancel();
    _authBridgeIncomingSub = VorynBackgroundAuthBridge
        .instance
        .onIncomingMessage
        .listen((data) {
          final msgId = data['messageId'] as String?;
          if (msgId != null && !_seenMessageIds.add(msgId)) {
            debugPrint(
              '[MESSAGE_FCM_BRIDGE] dedupe messageId=$msgId already processed',
            );
            return;
          }
          notifyThreadsChanged();
        });
  }

  void disposeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _userHiddenChannel?.unsubscribe();
    _userHiddenChannel = null;
    _userStateChannel?.unsubscribe();
    _userStateChannel = null;
    _authBridgeIncomingSub?.cancel();
    _authBridgeIncomingSub = null;
    _subscribed = false;
  }

  void _handleIncomingRealtimeMessage(Map<String, dynamic> record) {
    try {
      final currentUid = _client?.auth.currentUser?.id;
      final msg = VorynMessage.fromMap(record);
      debugPrint(
        '[MESSAGE_REALTIME] phase=received messageId=${msg.id} threadId=${msg.threadId}',
      );

      final isDuplicate = !_seenMessageIds.add(msg.id);
      debugPrint('[MESSAGE_REALTIME] phase=reconciled dedupe=$isDuplicate');
      if (isDuplicate) return;

      if (_seenMessageIds.length > 200) {
        _seenMessageIds.removeAll(_seenMessageIds.take(50).toList());
      }

      if (!isVisibleToCurrentUser(msg.threadId, msg.id, msg.createdAt)) {
        debugPrint(
          '[MESSAGE_REALTIME] suppressed: not visible to current user messageId=${msg.id}',
        );
        return;
      }

      // Remove from outbox if it matches our clientMessageId
      if (msg.clientMessageId != null) {
        VorynMessageLocalStore.instance.removeFromOutbox(msg.clientMessageId!);
      }

      _messageStreamController.add(msg);

      if (currentUid != null && msg.senderUid != currentUid) {
        totalUnreadCount.value += 1;
      }

      notifyThreadsChanged();
      debugPrint('[MESSAGE_REALTIME] phase=ui_notified');
    } catch (e) {
      debugPrint('[MESSAGE_REALTIME] action=realtime_error error=$e');
    }
  }

  void _handleUpdatedRealtimeMessage(Map<String, dynamic> record) {
    try {
      final msg = VorynMessage.fromMap(record);
      debugPrint(
        '[MESSAGE_REALTIME_UPDATE] messageId=${msg.id} threadId=${msg.threadId} version=${msg.messageVersion} isEdited=${msg.isEdited} isDeleted=${msg.isDeleted}',
      );
      if (!isVisibleToCurrentUser(msg.threadId, msg.id, msg.createdAt)) {
        debugPrint(
          '[MESSAGE_REALTIME_UPDATE] suppressed: not visible to current user messageId=${msg.id}',
        );
        return;
      }
      if (msg.isDeleted) {
        VorynMessageLocalStore.instance.purgeMessage(msg.id);
      }
      _messageUpdatedStreamController.add(msg);
      notifyThreadsChanged();
    } catch (e) {
      debugPrint('[MESSAGE_REALTIME_UPDATE] action=update_error error=$e');
    }
  }

  void _handleIncomingHiddenMessage(Map<String, dynamic> record) {
    try {
      final currentUid = _client?.auth.currentUser?.id;
      final userUid = record['user_uid'] as String?;
      if (currentUid == null || userUid != currentUid) return;

      final messageId = record['message_id'] as String?;
      final threadId = record['thread_id'] as String?;
      if (messageId == null) return;

      VorynMessageLocalStore.instance.markMessageHidden(currentUid, messageId);
      _messageDeletedForMeController.add({
        'threadId': threadId ?? '',
        'messageId': messageId,
      });
      if (threadId != null && threadId.isNotEmpty) {
        unawaited(
          VorynBackgroundAuthBridge.instance.removeMessageFromNotification(
            threadId,
            messageId,
          ),
        );
      }
      notifyThreadsChanged();
    } catch (e) {
      debugPrint('[MESSAGE_VISIBILITY] error handling hidden realtime: $e');
    }
  }

  void _handleIncomingThreadState(Map<String, dynamic> record) {
    try {
      final currentUid = _client?.auth.currentUser?.id;
      final userUid = record['user_uid'] as String?;
      if (currentUid == null || userUid != currentUid) return;

      final threadId = record['thread_id'] as String?;
      final dt = record['cleared_before_created_at'] as String?;
      final mid = record['cleared_before_message_id'] as String?;
      if (threadId == null) return;

      if (dt != null && mid != null) {
        VorynMessageLocalStore.instance.setThreadClearCursor(
          currentUid,
          threadId,
          DateTime.parse(dt),
          mid,
        );
      }
      VorynMessageLocalStore.instance.clearThreadMessages(threadId);
      unawaited(
        VorynBackgroundAuthBridge.instance.dismissMessageNotification(threadId),
      );
      _threadClearedController.add(threadId);
      notifyThreadsChanged();
    } catch (e) {
      debugPrint(
        '[MESSAGE_VISIBILITY] error handling thread state realtime: $e',
      );
    }
  }

  DateTime? _lastReconcileAt;
  Future<void>? _reconcileInFlight;

  Future<void> reconcile({required String reason}) async {
    final now = DateTime.now();
    if (_lastReconcileAt != null &&
        now.difference(_lastReconcileAt!) < const Duration(seconds: 2)) {
      debugPrint('[MESSAGE_RECONCILE] debounced reason=$reason');
      return;
    }
    if (_reconcileInFlight != null) {
      return _reconcileInFlight;
    }

    debugPrint('[MESSAGE_RECONCILE] start reason=$reason');
    _lastReconcileAt = now;
    _reconcileInFlight = () async {
      try {
        await loadThreads();
      } catch (e) {
        debugPrint('[MESSAGE_RECONCILE] error reason=$reason error=$e');
      } finally {
        _reconcileInFlight = null;
      }
    }();
    return _reconcileInFlight;
  }

  Future<void> refreshUnreadCount() async {
    try {
      final threads = await loadThreads();
      totalUnreadCount.value = threads.fold(0, (sum, t) => sum + t.unreadCount);
    } catch (_) {}
  }

  Future<List<VorynMessageThread>> loadThreads() async {
    debugPrint('[MESSAGE_INBOX] action=load_start');
    final client = _client;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      debugPrint('[MESSAGE_INBOX] action=load_aborted reason=no_auth');
      return const [];
    }

    try {
      unawaited(syncUserVisibilityState());
      final rows = await client.rpc('list_my_message_threads');
      final list = rows as List<dynamic>;
      debugPrint('[MESSAGE_INBOX] action=rpc_result rows=${list.length}');

      final threads = list.map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        return VorynMessageThread.fromMap(map);
      }).toList();

      debugPrint(
        '[MESSAGE_INBOX] action=parse_result count=${threads.length} threads=${threads.map((t) => t.threadId).toList()}',
      );
      totalUnreadCount.value = threads.fold(0, (sum, t) => sum + t.unreadCount);
      debugPrint(
        '[MESSAGE_INBOX] action=load_done count=${threads.length} unread=${totalUnreadCount.value}',
      );
      return threads;
    } catch (e, st) {
      debugPrint('[MESSAGE_INBOX] action=load_error error=$e\n$st');
      rethrow;
    }
  }

  Future<String> getOrCreateDirectThread(String targetUserUid) async {
    debugPrint(
      '[MESSAGE_THREAD] action=get_or_create_start targetUid=$targetUserUid',
    );
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentication required');
    }

    final threadId = await client.rpc(
      'get_or_create_direct_thread',
      params: {'target_user_id': targetUserUid},
    );
    final tid = threadId as String;
    debugPrint(
      '[MESSAGE_THREAD] action=get_or_create_done targetUid=$targetUserUid threadId=$tid',
    );
    return tid;
  }

  Future<List<VorynMessage>> loadThreadMessages(
    String threadId, {
    int limit = 50,
    DateTime? beforeCreatedAt,
    String? beforeId,
  }) async {
    debugPrint(
      '[MESSAGE_THREAD] action=load_messages_start threadId=$threadId limit=$limit',
    );
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return const [];
    }

    try {
      final rows = await client.rpc(
        'get_thread_messages',
        params: {
          'p_thread_id': threadId,
          'p_limit': limit,
          'p_before_created_at': ?beforeCreatedAt?.toIso8601String(),
          'p_before_id': ?beforeId,
        },
      );

      final messages = (rows as List<dynamic>)
          .map(
            (row) =>
                VorynMessage.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList();

      debugPrint(
        '[MESSAGE_THREAD] action=load_messages_done threadId=$threadId count=${messages.length}',
      );
      return messages;
    } catch (e, st) {
      debugPrint(
        '[MESSAGE_THREAD] action=load_messages_error threadId=$threadId error=$e\n$st',
      );
      rethrow;
    }
  }

  Future<VorynMessage> sendMessage({
    required String threadId,
    required String recipientUid,
    required String body,
    bool remindToCall = false,
    String? clientMessageId,
  }) async {
    final client = _client;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      throw StateError('Authentication required');
    }

    final text = body.trim();
    if (text.isEmpty || text.length > 120) {
      throw ArgumentError('Message body must be between 1 and 120 characters');
    }

    final cId = clientMessageId ?? _generateClientMessageId();

    final optimisticMessage = VorynMessage(
      id: cId,
      threadId: threadId,
      senderUid: currentUid,
      recipientUid: recipientUid,
      senderName: 'You',
      senderVorynId: '',
      body: text,
      remindToCall: remindToCall,
      createdAt: DateTime.now(),
      clientMessageId: cId,
      status: VorynMessageDeliveryStatus.sending,
    );

    VorynMessageLocalStore.instance.addToOutbox(optimisticMessage);

    debugPrint(
      '[MESSAGE_SEND] action=send_start threadId=$threadId recipientUid=$recipientUid clientMessageId=$cId remind=$remindToCall',
    );

    try {
      final messageId =
          await client.rpc(
                'send_call_message',
                params: {
                  'p_recipient_uid': recipientUid,
                  'p_body': text,
                  'p_remind_to_call': remindToCall,
                  'p_client_message_id': cId,
                },
              )
              as String;

      debugPrint(
        '[MESSAGE_SEND] action=send_success threadId=$threadId messageId=$messageId',
      );

      VorynMessageLocalStore.instance.updateOutboxStatus(
        cId,
        VorynMessageDeliveryStatus.sent,
        realId: messageId,
      );

      final sentMessage = optimisticMessage.copyWith(
        id: messageId,
        status: VorynMessageDeliveryStatus.sent,
      );

      notifyThreadsChanged();
      return sentMessage;
    } catch (e, st) {
      debugPrint(
        '[MESSAGE_SEND] action=send_error threadId=$threadId error=$e\n$st',
      );
      VorynMessageLocalStore.instance.updateOutboxStatus(
        cId,
        VorynMessageDeliveryStatus.failed,
      );
      rethrow;
    }
  }

  Future<VorynMessage> editMessage({
    required String messageId,
    required String newBody,
  }) async {
    final client = _client;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      throw StateError('Authentication required');
    }

    final text = newBody.trim();
    if (text.isEmpty || text.length > 120) {
      throw ArgumentError('Message body must be between 1 and 120 characters');
    }

    debugPrint('[MESSAGE_MUTATION] editMessage id=$messageId');
    final rows = await client.rpc(
      'edit_call_message',
      params: {'p_message_id': messageId, 'p_body': text},
    );

    final list = rows as List<dynamic>;
    if (list.isEmpty) {
      throw StateError('Message edit failed');
    }

    final updated = VorynMessage.fromMap(
      Map<String, dynamic>.from(list.first as Map),
    );
    _messageUpdatedStreamController.add(updated);
    notifyThreadsChanged();
    return updated;
  }

  Future<void> deleteMessage(String messageId) async {
    final client = _client;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      throw StateError('Authentication required');
    }

    debugPrint('[MESSAGE_MUTATION] deleteMessage id=$messageId');
    await client.rpc(
      'delete_call_message',
      params: {'p_message_id': messageId},
    );

    VorynMessageLocalStore.instance.purgeMessage(messageId);
    notifyThreadsChanged();
  }

  Future<void> deleteMessageForMe({
    required String threadId,
    required String messageId,
  }) async {
    final client = _client;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      throw StateError('Authentication required');
    }

    debugPrint(
      '[MESSAGE_VISIBILITY] deleteMessageForMe id=$messageId threadId=$threadId',
    );

    VorynMessageLocalStore.instance.markMessageHidden(currentUid, messageId);
    _messageDeletedForMeController.add({
      'threadId': threadId,
      'messageId': messageId,
    });
    unawaited(
      VorynBackgroundAuthBridge.instance.removeMessageFromNotification(
        threadId,
        messageId,
      ),
    );

    try {
      await client.rpc(
        'delete_call_message_for_me',
        params: {'p_message_id': messageId},
      );
    } catch (e, st) {
      debugPrint('[MESSAGE_VISIBILITY] deleteMessageForMe rpc error: $e\n$st');
      rethrow;
    }

    notifyThreadsChanged();
  }

  Future<void> clearThread(String threadId) async {
    final client = _client;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      throw StateError('Authentication required');
    }

    debugPrint('[MESSAGE_VISIBILITY] clearThread threadId=$threadId');

    try {
      final res = await client.rpc(
        'clear_call_message_thread',
        params: {'p_thread_id': threadId},
      );

      final list = res as List<dynamic>;
      if (list.isNotEmpty) {
        final row = Map<String, dynamic>.from(list.first as Map);
        final rawCreatedAt = row['out_cleared_before_created_at'] as String?;
        final rawMessageId = row['out_cleared_before_message_id'] as String?;
        if (rawCreatedAt != null && rawMessageId != null) {
          final clearedCreatedAt = DateTime.parse(rawCreatedAt);
          VorynMessageLocalStore.instance.setThreadClearCursor(
            currentUid,
            threadId,
            clearedCreatedAt,
            rawMessageId,
          );
        }
      }
    } catch (e, st) {
      debugPrint('[MESSAGE_VISIBILITY] clearThread rpc error: $e\n$st');
      rethrow;
    }

    VorynMessageLocalStore.instance.clearThreadMessages(threadId);
    unawaited(
      VorynBackgroundAuthBridge.instance.dismissMessageNotification(threadId),
    );
    _threadClearedController.add(threadId);
    notifyThreadsChanged();
  }

  Future<void> markThreadRead(
    String threadId, {
    String? lastSeenMessageId,
  }) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return;

    try {
      await client.rpc(
        'mark_thread_read',
        params: {
          'p_thread_id': threadId,
          'p_last_seen_message_id': ?lastSeenMessageId,
        },
      );

      // Do not dismiss Android notification simply because thread is viewed/read in-app.
      // Notifications remain in shade until user swipes, taps, replaces, or explicitly dismisses.
      unawaited(refreshUnreadCount());
    } catch (e) {
      debugPrint('[MSG_REPO] error marking thread read: $e');
    }
  }

  String _generateClientMessageId() {
    final rand = Random();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return [
      bytes
          .sublist(0, 4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(4, 6)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(6, 8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(8, 10)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      bytes
          .sublist(10, 16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    ].join('-');
  }
}
