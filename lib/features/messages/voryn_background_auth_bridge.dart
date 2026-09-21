import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/backend/voryn_backend.dart';

class VorynBackgroundAuthBridge {
  VorynBackgroundAuthBridge._();
  static final VorynBackgroundAuthBridge instance =
      VorynBackgroundAuthBridge._();

  static const _channel = MethodChannel('com.voryn.app/messages');

  final _openThreadController = StreamController<String>.broadcast();
  final _openInboxController = StreamController<void>.broadcast();
  final _incomingMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<String> get onOpenThread => _openThreadController.stream;
  Stream<void> get onOpenInbox => _openInboxController.stream;
  Stream<Map<String, dynamic>> get onIncomingMessage =>
      _incomingMessageController.stream;

  bool _initialized = false;

  void initialize() {
    if (_initialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onOpenThread':
          final threadId = call.arguments?['threadId'] as String?;
          if (threadId != null && threadId.isNotEmpty) {
            debugPrint('[AUTH_BRIDGE] onOpenThread: $threadId');
            _openThreadController.add(threadId);
          }
          break;
        case 'onOpenInbox':
          debugPrint('[AUTH_BRIDGE] onOpenInbox');
          _openInboxController.add(null);
          break;
        case 'onIncomingMessage':
          final data = Map<String, dynamic>.from(call.arguments as Map);
          debugPrint('[AUTH_BRIDGE] onIncomingMessage: ${data['messageId']}');
          _incomingMessageController.add(data);
          break;
      }
    });
  }

  Future<void> syncSession(Session session) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final user = session.user;
      final accessToken = session.accessToken;
      final refreshToken = session.refreshToken ?? '';
      final expiresAt = session.expiresAt;
      final expiresAtMs = expiresAt != null
          ? expiresAt * 1000
          : DateTime.now().millisecondsSinceEpoch + 3600000;

      final supabaseUrl = VorynBackend.supabaseUrl;
      final anonKey = VorynBackend.anonKey;

      if (supabaseUrl.isEmpty || anonKey.isEmpty) return;

      await _channel.invokeMethod('syncBackgroundAuth', {
        'userUid': user.id,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAtMs': expiresAtMs,
        'supabaseUrl': supabaseUrl,
        'anonKey': anonKey,
      });
      debugPrint('[AUTH_BRIDGE] background auth synced for ${user.id}');
    } catch (e) {
      debugPrint('[AUTH_BRIDGE] error syncing background auth: $e');
    }
  }

  Future<void> clearSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('clearBackgroundAuth');
      debugPrint('[AUTH_BRIDGE] background auth cleared');
    } catch (e) {
      debugPrint('[AUTH_BRIDGE] error clearing background auth: $e');
    }
  }

  Future<String?> getPendingMessageThread() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final threadId = await _channel.invokeMethod<String>(
        'getPendingMessageThread',
      );
      return threadId;
    } catch (_) {
      return null;
    }
  }

  Future<void> dismissMessageNotification(String threadId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('dismissMessageNotification', {
        'threadId': threadId,
      });
    } catch (_) {}
  }
}
