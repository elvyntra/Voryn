import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/notifications/lock_screen_service.dart';
import 'voryn_call_latency_tracker.dart';
import 'voryn_call_service.dart';
import 'voryn_livekit_service.dart';

/// Central coordinator managing active call runtime, single Realtime subscription,
/// single LiveKit session, and idempotent single teardown across screens.
class VorynCallRuntimeCoordinator {
  VorynCallRuntimeCoordinator._(this.callId);

  static final Map<String, VorynCallRuntimeCoordinator> _instances = {};
  static final Set<String> _acceptingCalls = {};

  static bool isAcceptInFlight(String callId) =>
      _acceptingCalls.contains(callId);

  static Future<T> runAcceptOnce<T>(
    String callId,
    Future<T> Function() action,
  ) async {
    if (_acceptingCalls.contains(callId)) {
      debugPrint(
        '[CALL $callId] [COORDINATOR] accept already in flight, skipping duplicate invocation',
      );
      throw StateError('Accept already in flight for $callId');
    }
    _acceptingCalls.add(callId);
    try {
      return await action();
    } finally {
      Timer(const Duration(seconds: 4), () => _acceptingCalls.remove(callId));
    }
  }

  static VorynCallRuntimeCoordinator forCall(String callId) {
    return _instances.putIfAbsent(
      callId,
      () => VorynCallRuntimeCoordinator._(callId),
    );
  }

  static void remove(String callId) {
    _instances.remove(callId);
  }

  final String callId;

  VorynLiveKitSession? session;
  RealtimeChannel? _subscription;
  Future<VorynLiveKitSession>? _connectFuture;
  Future<void>? _teardownFuture;

  bool _isTearingDown = false;
  bool _isEnded = false;
  bool _routeExitIssued = false;

  bool _isConnected = false;
  String _mediaMode = 'audio';
  bool _isHeld = false;

  /// Flag set when switching between Audio and Video screens to prevent
  /// the disposing screen from triggering teardown.
  bool isTransitioning = false;

  bool get isTearingDown => _isTearingDown;
  bool get isEnded => _isEnded;
  bool get routeExitIssued => _routeExitIssued;

  void Function(String status)? _onStatusChanged;
  FutureOr<void> Function()? _onRouteExit;

  void attachScreen({
    required void Function(String status) onStatusChanged,
    required FutureOr<void> Function() onRouteExit,
  }) {
    _onStatusChanged = onStatusChanged;
    _onRouteExit = onRouteExit;
    isTransitioning = false;
    _ensureSubscription();
  }

  void detachScreen() {
    _onStatusChanged = null;
    _onRouteExit = null;
  }

  void updateProximity({
    bool? isConnected,
    String? mediaMode,
    bool? isHeld,
    bool? isEnding,
  }) {
    if (isConnected != null) _isConnected = isConnected;
    if (mediaMode != null) _mediaMode = mediaMode;
    if (isHeld != null) _isHeld = isHeld;
    final ending = isEnding ?? (_isEnded || _isTearingDown);

    unawaited(
      LockScreenService.updateProximityState(
        callId: callId,
        isConnected: _isConnected,
        mediaMode: _mediaMode,
        isHeld: _isHeld,
        isEnding: ending,
      ),
    );
  }

  Future<void> prepareForVideoUpgrade() async {
    _mediaMode = 'video';
    await LockScreenService.updateProximityState(
      callId: callId,
      isConnected: _isConnected,
      mediaMode: 'video',
      isHeld: _isHeld,
      isEnding: false,
    );
  }

  void _ensureSubscription() {
    if (_subscription != null || _isEnded || _isTearingDown) return;
    _subscription = const VorynCallService().subscribeToCallState(callId, (
      status,
    ) {
      debugPrint('[CALL $callId] [COORDINATOR] realtime status: $status');
      _onStatusChanged?.call(status);
      if ([
        'completed',
        'cancelled',
        'declined',
        'missed',
        'failed',
      ].contains(status)) {
        debugPrint(
          '[CALL $callId] [COORDINATOR] remote terminal status=$status',
        );
        performTeardown(isLocalInitiator: false);
      }
    });
  }

  Future<VorynLiveKitSession> connect({
    required bool video,
    VorynCallLatencyTracker? latencyTracker,
  }) {
    _mediaMode = video ? 'video' : 'audio';
    if (session != null) {
      _isConnected = true;
      updateProximity();
      return Future.value(session!);
    }
    return _connectFuture ??= const VorynLiveKitService()
        .connect(callId: callId, video: video, latencyTracker: latencyTracker)
        .then((s) {
          session = s;
          _isConnected = true;
          updateProximity();
          return s;
        });
  }

  Future<void> performTeardown({
    bool isLocalInitiator = false,
    FutureOr<void> Function()? onRouteExit,
  }) {
    if (_isEnded) return Future<void>.value();
    return _teardownFuture ??= _executeTeardown(
      isLocalInitiator: isLocalInitiator,
      onRouteExit: onRouteExit,
    );
  }

  Future<void> _executeTeardown({
    bool isLocalInitiator = false,
    FutureOr<void> Function()? onRouteExit,
  }) async {
    if (_isEnded) return;
    _isTearingDown = true;
    updateProximity(isEnding: true);
    debugPrint(
      '[CALL $callId] [COORDINATOR] teardown begin (local=$isLocalInitiator)',
    );

    try {
      _subscription?.unsubscribe();
      _subscription = null;
    } catch (_) {}

    if (isLocalInitiator) {
      try {
        await const VorynCallService().end(callId);
        debugPrint(
          '[CALL $callId] [COORDINATOR] backend terminal update success',
        );
      } catch (e) {
        debugPrint(
          '[CALL $callId] [COORDINATOR] backend terminal update error: $e',
        );
      }
    }

    try {
      if (session != null) {
        await session!.disconnect();
        debugPrint('[CALL $callId] [COORDINATOR] room disconnect complete');
      }
    } catch (e) {
      debugPrint('[CALL $callId] [COORDINATOR] room disconnect error: $e');
    }

    _isEnded = true;
    await const VorynCallService().clearActiveCall(callId);
    session = null;
    debugPrint('[CALL $callId] [COORDINATOR] teardown complete');

    await LockScreenService.setCallPresentationVisible(false);
    await LockScreenService.markDartTeardownComplete(callId);

    if (!_routeExitIssued) {
      _routeExitIssued = true;
      final isLocked = await LockScreenService.isKeyguardLocked();
      if (isLocked || LockScreenService.isCallHostApp) {
        debugPrint(
          '[CALL $callId] [COORDINATOR] route exit (locked=$isLocked, callHost=${LockScreenService.isCallHostApp})',
        );
        await LockScreenService.moveCallTaskBehindKeyguard();
      } else {
        debugPrint('[CALL $callId] [COORDINATOR] route exit');
        try {
          final exitFn = onRouteExit ?? _onRouteExit;
          await exitFn?.call();
        } catch (e) {
          debugPrint(
            '[CALL $callId] [COORDINATOR] route exit callback error: $e',
          );
        }
      }
    }

    VorynCallRuntimeCoordinator.remove(callId);
  }
}
