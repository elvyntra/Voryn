import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/notifications/lock_screen_service.dart';

/// Instruments latency across call acceptance to connected state using
/// monotonic kernel clock (SystemClock.elapsedRealtime on Android).
class VorynCallLatencyTracker {
  VorynCallLatencyTracker._({
    required this.callId,
    required this.baseTimestampMs,
  });

  static final Map<String, VorynCallLatencyTracker> _trackers = {};

  static VorynCallLatencyTracker start({
    required String callId,
    int? baseTimestampMs,
  }) {
    final existing = _trackers[callId];
    if (existing != null) {
      if (baseTimestampMs != null && baseTimestampMs > 0) {
        existing.baseTimestampMs = baseTimestampMs;
      }
      return existing;
    }
    final tracker = VorynCallLatencyTracker._(
      callId: callId,
      baseTimestampMs: baseTimestampMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    _trackers[callId] = tracker;
    return tracker;
  }

  static VorynCallLatencyTracker? get(String callId) => _trackers[callId];

  static void dispose(String callId) => _trackers.remove(callId);

  final String callId;
  int baseTimestampMs;
  final Set<String> _recordedStages = {};

  Future<void> stage(String name, {String? extra}) async {
    if (_recordedStages.contains(name)) return;
    _recordedStages.add(name);
    final nowMs = await LockScreenService.getElapsedRealtimeMs();
    final elapsed = (nowMs - baseTimestampMs).clamp(0, 999999);
    final extraStr = extra != null && extra.isNotEmpty ? ' $extra' : '';
    debugPrint(
      '[CALL_LATENCY] $name callId=$callId elapsed=${elapsed}ms$extraStr',
    );
  }
}
