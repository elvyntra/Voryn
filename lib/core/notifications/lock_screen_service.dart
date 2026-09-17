import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LockScreenService {
  LockScreenService._();

  static const _channel = MethodChannel('com.voryn.app/lock_screen');

  /// Checks if the device's secure keyguard is currently locked.
  static Future<bool> isKeyguardLocked() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final locked = await _channel.invokeMethod<bool>('isKeyguardLocked');
      return locked ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves initial call launch payload and action captured by MainActivity on cold start.
  static Future<Map<String, String>?> getInitialCallLaunch() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getInitialCallLaunch',
      );
      if (res == null) return null;
      return res.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    } catch (_) {
      return null;
    }
  }

  /// Sets a listener for call launch intents received while the app is already running (warm start).
  static void setCallLaunchListener(
    void Function(Map<String, String> data) listener, {
    void Function(String callId)? onDeclined,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCallLaunchIntent') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final data = arguments.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          );
          listener(data);
        }
      } else if (call.method == 'onCallDeclined') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final callId = arguments['callId']?.toString() ?? '';
          onDeclined?.call(callId);
        }
      }
    });
  }

  /// Displays native high-importance call notification with full-screen intent targeting IncomingCallActivity.
  static Future<void> showNativeIncomingCall({
    required String callId,
    required String callerName,
    required String callType,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('showNativeIncomingCall', {
        'callId': callId,
        'callerName': callerName,
        'callType': callType,
      });
    } catch (_) {}
  }

  /// Cancels native incoming call notification.
  static Future<void> cancelNativeIncomingCall(String callId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancelNativeIncomingCall', {
        'callId': callId,
      });
    } catch (_) {}
  }

  /// Sets whether the current activity can show over the lock screen.
  static Future<void> setCallPresentationVisible(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setCallPresentationVisible', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  /// Clears lock-screen presentation flags and moves the task behind the keyguard
  /// if the keyguard is currently locked.
  static Future<void> moveCallTaskBehindKeyguard() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('moveCallTaskBehindKeyguard');
    } catch (_) {}
  }
}
