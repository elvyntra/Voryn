import 'dart:async';
import 'package:flutter/widgets.dart';

import '../backend/voryn_backend.dart';

class VorynPresenceService {
  const VorynPresenceService._();

  static bool _isInCall = false;
  static AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;
  static Timer? _debounceTimer;
  static String? _lastReportedStatus;

  static bool get isInCall => _isInCall;

  static Future<void> setPresence(String status) async {
    final client = VorynBackend.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    if (_lastReportedStatus == status) return;

    try {
      await client.rpc('set_my_presence', params: {'new_status': status});
      _lastReportedStatus = status;
      debugPrint('[PRESENCE] Updated presence -> $status');
    } catch (e) {
      debugPrint('[PRESENCE] Failed to update presence ($status): $e');
    }
  }

  static Future<void> setOnline() async {
    _debounceTimer?.cancel();
    if (_isInCall) {
      await setPresence('busy');
    } else {
      await setPresence('online');
    }
  }

  static Future<void> setOffline() async {
    _debounceTimer?.cancel();
    await setPresence('offline');
  }

  static Future<void> setBusy() async {
    _debounceTimer?.cancel();
    await setPresence('busy');
  }

  /// Hook for when a call connects
  static void onCallConnected() {
    _debounceTimer?.cancel();
    _isInCall = true;
    unawaited(setBusy());
  }

  /// Hook for when a call ends
  static void onCallEnded() {
    _debounceTimer?.cancel();
    _isInCall = false;
    if (_lastLifecycleState == AppLifecycleState.resumed) {
      unawaited(setPresence('online'));
    } else {
      unawaited(setPresence('offline'));
    }
  }

  /// Handles AppLifecycleState transitions safely.
  /// Ignores AppLifecycleState.inactive to prevent flicker from dialogs & system overlays.
  static void onLifecycleChanged(AppLifecycleState state) {
    _lastLifecycleState = state;
    if (_isInCall) {
      return; // Busy call state is authoritative during an active call
    }

    if (state == AppLifecycleState.resumed) {
      _debounceTimer?.cancel();
      unawaited(setPresence('online'));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _debounceTimer?.cancel();
      // Debounce slightly to avoid rapid toggling during Activity launches
      _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!_isInCall && _lastLifecycleState != AppLifecycleState.resumed) {
          unawaited(setPresence('offline'));
        }
      });
    }
  }
}
