import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/voryn_backend.dart';
import 'lock_screen_service.dart';

@pragma('vm:entry-point')
Future<void> vorynFirebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await VorynFirebaseMessaging.showIncomingCallNotification(message);
}

@pragma('vm:entry-point')
void vorynNotificationResponseBackground(NotificationResponse response) {
  VorynFirebaseMessaging.handleBackgroundNotificationResponse(response);
}

enum VorynNotificationActionType {
  incoming,
  notificationTap,
  accept,
  decline,
  foregroundTap,
}

class VorynPendingCallLaunch {
  const VorynPendingCallLaunch({
    required this.callId,
    required this.action,
    this.callType = 'audio',
  });

  final String callId;
  final VorynNotificationActionType action;
  final String callType;
}

class VorynFirebaseMessaging {
  const VorynFirebaseMessaging._();

  static bool _isInitialized = false;
  static VorynPendingCallLaunch? _pendingLaunch;
  static const _callChannel = AndroidNotificationChannel(
    'voryn_incoming_calls_v2',
    'Incoming calls',
    description: 'Incoming Voryn call alerts',
    importance: Importance.max,
    playSound: true,
  );
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase is optional on development platforms until their config is added.
      return;
    }
    FirebaseMessaging.onBackgroundMessage(vorynFirebaseBackgroundHandler);
    _isInitialized = true;

    await _initializeLocalNotifications(requestFullScreenPermission: true);
    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails?.notificationResponse;
      final callId = response?.payload;
      if (callId != null && callId.isNotEmpty) {
        final actionId = response?.actionId;
        if (actionId == 'decline') {
          await handleDeclineAction(callId);
        } else if (actionId == 'accept') {
          _pendingLaunch = VorynPendingCallLaunch(
            callId: callId,
            action: VorynNotificationActionType.accept,
          );
        } else {
          _pendingLaunch = VorynPendingCallLaunch(
            callId: callId,
            action: VorynNotificationActionType.notificationTap,
          );
        }
      }
    }

    final messaging = FirebaseMessaging.instance;
    messaging.onTokenRefresh.listen(_registerToken);
    FirebaseMessaging.onMessage.listen(showIncomingCallNotification);
  }

  static Future<void> _initializeLocalNotifications({
    bool requestFullScreenPermission = false,
  }) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          vorynNotificationResponseBackground,
    );
    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.createNotificationChannel(_callChannel);
    if (requestFullScreenPermission) {
      // Request this only while the user is opening Voryn. Triggering the
      // Android settings screen from a background push hides the call UI.
      await androidNotifications?.requestFullScreenIntentPermission();
    }
  }

  static Future<void> showIncomingCallNotification(
    RemoteMessage message,
  ) async {
    final data = message.data;
    if (data['type'] != 'incoming_call') return;

    await _initializeLocalNotifications();
    final callId = data['call_id'];
    if (callId == null || callId.isEmpty) return;
    final callerName = data['caller_name']?.trim().isNotEmpty == true
        ? data['caller_name']!
        : 'Voryn user';
    final isVideo = data['call_type'] == 'video';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await LockScreenService.showNativeIncomingCall(
        callId: callId,
        callerName: callerName,
        callType: isVideo ? 'video' : 'audio',
      );
      return;
    }
    await _localNotifications.show(
      callId.hashCode,
      isVideo ? 'Incoming video call' : 'Incoming call',
      callerName,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannel.id,
          _callChannel.name,
          channelDescription: _callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          ongoing: true,
          autoCancel: true,
          actions: const [
            AndroidNotificationAction('decline', 'Decline'),
            AndroidNotificationAction(
              'accept',
              'Accept',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      payload: callId,
    );
  }

  static Future<void> registerTokenAfterSplash() async {
    if (!_isInitialized) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      if (token != null) {
        await _registerToken(token);
      }
      await _applyDeferredNotificationAction();
    } catch (e) {
      debugPrint('[FCM] registerTokenAfterSplash skipped/failed: $e');
    }
  }

  static final Set<String> _handledCallIds = {};
  static void markCallLaunchHandled(String callId) =>
      _handledCallIds.add(callId);
  static bool isCallLaunchHandled(String callId) =>
      _handledCallIds.contains(callId);

  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final callId = response.payload;
    if (callId == null || callId.isEmpty) return;
    if (_handledCallIds.contains(callId)) return;

    final actionId = response.actionId;
    if (actionId == 'decline') {
      await handleDeclineAction(callId);
    } else if (actionId == 'accept') {
      _pendingLaunch = VorynPendingCallLaunch(
        callId: callId,
        action: VorynNotificationActionType.accept,
      );
    } else {
      // Notification body clicked / fullScreenIntent incoming
      _pendingLaunch = VorynPendingCallLaunch(
        callId: callId,
        action: VorynNotificationActionType.notificationTap,
      );
    }
  }

  static Future<void> handleDeclineAction(String callId) async {
    clearPendingIncomingCall(callId);
    final client = VorynBackend.client;
    if (client?.auth.currentUser != null) {
      try {
        await client!.rpc(
          'update_call_state',
          params: {'call_uuid': callId, 'new_status': 'declined'},
        );
      } catch (_) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString('voryn.pending_call_decline', callId);
      }
    } else {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('voryn.pending_call_decline', callId);
    }

    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) {
      await LockScreenService.moveCallTaskBehindKeyguard();
    }
  }

  static VorynPendingCallLaunch? get pendingLaunch => _pendingLaunch;
  static String? get pendingIncomingCallId => _pendingLaunch?.callId;

  static void clearPendingIncomingCall(String callId) {
    if (_pendingLaunch?.callId == callId) {
      _pendingLaunch = null;
    }
  }

  static Future<void> handleBackgroundNotificationResponse(
    NotificationResponse response,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();
    await VorynBackend.initialize();
    await handleNotificationResponse(response);
  }

  static Future<void> _applyDeferredNotificationAction() async {
    final preferences = await SharedPreferences.getInstance();
    final callId = preferences.getString('voryn.pending_call_decline');
    final client = VorynBackend.client;
    if (callId == null || client?.auth.currentUser == null) return;
    try {
      await client!.rpc(
        'update_call_state',
        params: {'call_uuid': callId, 'new_status': 'declined'},
      );
      await preferences.remove('voryn.pending_call_decline');
    } catch (_) {
      // Keep the action queued for the next successful app startup.
    }
  }

  static Future<void> _registerToken(String? token) async {
    final client = VorynBackend.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null || token == null || token.isEmpty) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    final installationId =
        preferences.getString('voryn.installation.id') ??
        'android-${DateTime.now().microsecondsSinceEpoch}';
    await preferences.setString('voryn.installation.id', installationId);
    await client.from('user_devices').upsert({
      'user_uid': user.id,
      'installation_id': installationId,
      'platform': 'android',
      'device_name': 'Voryn Android',
      'push_token': token,
      'last_active_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_uid,installation_id');
  }
}
