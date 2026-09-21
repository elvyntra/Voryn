import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LockScreenService {
  LockScreenService._();

  static const _channel = MethodChannel('com.voryn.app/lock_screen');

  /// Set to true when running inside the isolated VorynCallActivity (callMain entrypoint).
  static bool isCallHostApp = false;

  /// Checks whether a call is currently owned by another host Activity (e.g. VorynCallActivity).
  static Future<bool> isCallOwnedByOtherHost(String callId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final owned = await _channel.invokeMethod<bool>(
        'isCallOwnedByOtherHost',
        {'callId': callId},
      );
      return owned ?? false;
    } catch (_) {
      return false;
    }
  }

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

  /// Retrieves device monotonic elapsed realtime in milliseconds (Android SystemClock.elapsedRealtime).
  static Future<int> getElapsedRealtimeMs() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return DateTime.now().millisecondsSinceEpoch;
    }
    try {
      final ms = await _channel.invokeMethod<int>('getElapsedRealtimeMs');
      return ms ?? DateTime.now().millisecondsSinceEpoch;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// Retrieves minimal native pending incoming call if persisted by Android notification manager.
  static Future<Map<String, dynamic>?> getPendingIncomingCall() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getPendingIncomingCall',
      );
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Clears native pending call record in SharedPreferences.
  static Future<void> clearPendingIncomingCall([String? callId]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('clearPendingIncomingCall', {
        'callId': callId,
      });
    } catch (_) {}
  }

  /// Checks if full-screen intent permission is granted (Android 14+).
  static Future<bool> canUseFullScreenIntent() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final allowed = await _channel.invokeMethod<bool>(
        'canUseFullScreenIntent',
      );
      return allowed ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens Android 14+ full-screen intent settings screen for Voryn.
  static Future<void> openFullScreenIntentSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openFullScreenIntentSettings');
    } catch (_) {}
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
    void Function(Map<String, String> data)? onIncoming,
    void Function(String callId, String type)? onTerminal,
    void Function(Map<String, dynamic>? snapshot)? onActiveCallStateChanged,
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
      } else if (call.method == 'onIncomingCall') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final data = arguments.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
          );
          onIncoming?.call(data);
        }
      } else if (call.method == 'onCallTerminal') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final callId = arguments['callId']?.toString() ?? '';
          final type = arguments['type']?.toString() ?? '';
          onTerminal?.call(callId, type);
        }
      } else if (call.method == 'onActiveCallStateChanged') {
        final arguments = call.arguments;
        final snapshot = arguments is Map
            ? Map<String, dynamic>.from(arguments)
            : null;
        onActiveCallStateChanged?.call(snapshot);
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

  /// Transitions native call session state to ACTIVE and starts the ongoing foreground notification.
  static Future<void> markCallActive({
    required String callId,
    String? callerName,
    String? callType,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('markCallActive', {
        'callId': callId,
        'callerName': callerName ?? 'Voryn User',
        'callType': callType ?? 'audio',
      });
    } catch (_) {}
  }

  /// Signals native engine manager that Dart/LiveKit teardown is complete.
  static Future<void> markDartTeardownComplete(String callId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('markDartTeardownComplete', {
        'callId': callId,
      });
    } catch (_) {}
  }

  /// Minimizes VorynCallActivity to the background while keeping the call active.
  static Future<void> minimizeActiveCall() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('minimizeActiveCall');
    } catch (_) {}
  }

  /// Claims and launches VorynCallActivity for an incoming call answered in foreground.
  static Future<void> acceptIncomingCall({
    required String callId,
    required String callType,
    required String callerName,
    String origin = 'IN_APP',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('acceptIncomingCall', {
        'callId': callId,
        'callType': callType,
        'callerName': callerName,
        'origin': origin,
      });
    } catch (_) {}
  }

  /// Cancels native incoming call notification and stops ringtone.
  static Future<void> cancelNativeIncomingCall(
    String callId, {
    String reason = 'remote_terminal',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancelNativeIncomingCall', {
        'callId': callId,
        'reason': reason,
      });
    } catch (_) {}
  }

  /// Explicitly stops native incoming call ringtone.
  static Future<void> stopRingtone({
    String reason = 'remote_terminal',
    String? callId,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopRingtone', {
        'reason': reason,
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

  /// Checks if proximity screen-off wake lock is supported on this device.
  static Future<bool> isProximitySupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final supported = await _channel.invokeMethod<bool>(
        'isProximitySupported',
      );
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Updates centralized call state for proximity sensor wake lock evaluation.
  static Future<void> updateProximityState({
    required String callId,
    required bool isConnected,
    required String mediaMode,
    required bool isHeld,
    required bool isEnding,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateProximityState', {
        'callId': callId,
        'connected': isConnected,
        'mediaMode': mediaMode,
        'held': isHeld,
        'ending': isEnding,
      });
    } catch (_) {}
  }

  /// Retrieves active call UI snapshot for mini-call bar presentation.
  static Future<Map<String, dynamic>?> getActiveCallSnapshot() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getActiveCallSnapshot',
      );
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Returns to existing fullscreen active call Activity.
  static Future<void> returnToActiveCall(String callId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('returnToActiveCall', {
        'callId': callId,
      });
    } catch (_) {}
  }
}
