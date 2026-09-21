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

  final _threadsChangedController = StreamController<void>.broadcast();
  Stream<void> get onThreadsChanged => _threadsChangedController.stream;

  SupabaseClient? get _client => VorynBackend.client;
  RealtimeChannel? _realtimeChannel;
  bool _subscribed = false;

  void notifyThreadsChanged() {
    _threadsChangedController.add(null);
    unawaited(refreshUnreadCount());
  }

  final _seenMessageIds = <String>{};
  StreamSubscription<Map<String, dynamic>>? _authBridgeIncomingSub;

  void initializeRealtime() {
    if (_subscribed) return;
    final client = _client;
    if (client == null || client.auth.currentUser == null) return;

    _subscribed = true;
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

      await VorynBackgroundAuthBridge.instance.dismissMessageNotification(
        threadId,
      );
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
