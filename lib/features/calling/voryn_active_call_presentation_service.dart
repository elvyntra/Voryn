import 'package:flutter/foundation.dart';
import '../../core/notifications/lock_screen_service.dart';

/// Lightweight, read-only UI snapshot representing the active call state.
///
/// Contains NO media objects or LiveKit instances. Authoritative media ownership
/// remains strictly inside the dedicated call host engine.
@immutable
class ActiveCallSnapshot {
  const ActiveCallSnapshot({
    required this.callId,
    required this.state,
    required this.presentation,
    required this.callType,
    required this.displayName,
    required this.startedAt,
  });

  final String callId;
  final String state;
  final String presentation;
  final String callType;
  final String displayName;
  final int startedAt;

  bool get isActive => state == 'ACTIVE';
  bool get isMinimized => presentation == 'MINIMIZED';
  bool get shouldShowMiniBar => isActive && isMinimized;

  factory ActiveCallSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return ActiveCallSnapshot(
      callId: map['callId']?.toString() ?? '',
      state: map['state']?.toString() ?? '',
      presentation: map['presentation']?.toString() ?? 'FULLSCREEN',
      callType: map['callType']?.toString() ?? 'audio',
      displayName: map['displayName']?.toString() ?? 'Voryn User',
      startedAt: (map['startedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'state': state,
      'presentation': presentation,
      'callType': callType,
      'displayName': displayName,
      'startedAt': startedAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveCallSnapshot &&
          runtimeType == other.runtimeType &&
          callId == other.callId &&
          state == other.state &&
          presentation == other.presentation &&
          callType == other.callType &&
          displayName == other.displayName &&
          startedAt == other.startedAt;

  @override
  int get hashCode => Object.hash(
    callId,
    state,
    presentation,
    callType,
    displayName,
    startedAt,
  );

  @override
  String toString() =>
      'ActiveCallSnapshot(callId: $callId, state: $state, presentation: $presentation, callType: $callType, displayName: $displayName, startedAt: $startedAt)';
}

/// Cross-platform presentation coordinator managing the mini-call bar UI state.
class VorynActiveCallPresentationService {
  VorynActiveCallPresentationService._();

  static final VorynActiveCallPresentationService instance =
      VorynActiveCallPresentationService._();

  final ValueNotifier<ActiveCallSnapshot?> snapshotNotifier =
      ValueNotifier<ActiveCallSnapshot?>(null);

  bool _isRestoring = false;

  ActiveCallSnapshot? get currentSnapshot => snapshotNotifier.value;

  /// Refreshes the active call snapshot from the native platform bridge.
  Future<void> refreshSnapshot() async {
    try {
      final map = await LockScreenService.getActiveCallSnapshot();
      updateSnapshotFromMap(map);
    } catch (_) {
      // Platform bridge or network query error
    }
  }

  /// Updates the snapshot notifier from a raw map or null.
  void updateSnapshotFromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      clearSnapshot();
      return;
    }
    final snapshot = ActiveCallSnapshot.fromMap(map);
    snapshotNotifier.value = snapshot;
  }

  /// Explicitly sets the active snapshot (useful for testing or direct events).
  void setSnapshot(ActiveCallSnapshot? snapshot) {
    snapshotNotifier.value = snapshot;
  }

  /// Clears active call presentation.
  void clearSnapshot() {
    snapshotNotifier.value = null;
    _isRestoring = false;
  }

  /// Requests the platform to restore the active call to fullscreen.
  ///
  /// Idempotent: repeated rapid taps while restore is in progress are ignored.
  Future<void> returnToActiveCall(String callId) async {
    if (_isRestoring) {
      debugPrint(
        '[CALL_RESTORE] returnToActiveCall already in flight, ignoring duplicate tap',
      );
      return;
    }
    _isRestoring = true;
    try {
      final current = snapshotNotifier.value;
      if (current != null && current.callId == callId) {
        // Optimistically hide the mini bar in Flutter shell while Activity re-fronts
        snapshotNotifier.value = ActiveCallSnapshot(
          callId: current.callId,
          state: current.state,
          presentation: 'FULLSCREEN',
          callType: current.callType,
          displayName: current.displayName,
          startedAt: current.startedAt,
        );
      }
      await LockScreenService.returnToActiveCall(callId);
    } finally {
      // Release idempotency lock after transition
      Future.delayed(const Duration(milliseconds: 600), () {
        _isRestoring = false;
      });
    }
  }

  /// Requests minimization of the currently active call.
  Future<void> minimizeActiveCall() async {
    await LockScreenService.minimizeActiveCall();
  }
}
