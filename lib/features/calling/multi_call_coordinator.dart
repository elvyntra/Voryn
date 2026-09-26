import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/notifications/lock_screen_service.dart';
import 'voryn_audio_route_service.dart';
import 'voryn_call_runtime_coordinator.dart';
import 'voryn_call_service.dart';
import 'voryn_livekit_service.dart';

class CallMediaState {
  final bool wasMicEnabled;
  final bool wasCameraEnabled;
  final bool wasSpeakerEnabled;

  const CallMediaState({
    required this.wasMicEnabled,
    required this.wasCameraEnabled,
    required this.wasSpeakerEnabled,
  });
}

class MultiCallCoordinator extends ChangeNotifier {
  MultiCallCoordinator._();

  static final MultiCallCoordinator instance = MultiCallCoordinator._();

  final Map<String, VorynLiveKitSession> _sessionsByCallId = {};
  final Map<String, CallMediaState> _mediaStates = {};

  String? _activeCallId;
  String? _heldCallId;
  String? _waitingCallId;
  String? _waitingCallerName;
  String? _waitingCallType;

  // Remote hold state tracking
  final Map<String, String?> _remoteHeldBy = {};

  RealtimeChannel? _waitingSubscription;
  int _revision = 0;
  bool _isTransitionInFlight = false;

  Map<String, VorynLiveKitSession> get sessionsByCallId =>
      Map.unmodifiable(_sessionsByCallId);

  String? get activeCallId => _activeCallId;
  String? get heldCallId => _heldCallId;
  String? get waitingCallId => _waitingCallId;
  String? get waitingCallerName => _waitingCallerName;
  String? get waitingCallType => _waitingCallType;
  bool get hasWaitingCall => _waitingCallId != null && _waitingCallId!.isNotEmpty;
  bool get hasHeldCall => _heldCallId != null && _heldCallId!.isNotEmpty;
  bool get isTransitionInFlight => _isTransitionInFlight;
  int get revision => _revision;

  bool isCallHeldByRemote(String callId) =>
      _remoteHeldBy.containsKey(callId) && _remoteHeldBy[callId] != null;

  String? getRemoteHolder(String callId) => _remoteHeldBy[callId];

  void registerSession(String callId, VorynLiveKitSession session) {
    _sessionsByCallId[callId] = session;
    _activeCallId ??= callId;
    notifyListeners();
  }

  void removeSession(String callId) {
    _sessionsByCallId.remove(callId);
    _mediaStates.remove(callId);
    _remoteHeldBy.remove(callId);
    if (_activeCallId == callId) {
      _activeCallId = null;
    }
    if (_heldCallId == callId) {
      _heldCallId = null;
    }
    if (_waitingCallId == callId) {
      _waitingCallId = null;
      _waitingCallerName = null;
      _waitingCallType = null;
    }
    notifyListeners();
  }

  void recordPreHoldMediaState(
    String callId, {
    required bool micEnabled,
    required bool cameraEnabled,
    required bool speakerEnabled,
  }) {
    _mediaStates[callId] = CallMediaState(
      wasMicEnabled: micEnabled,
      wasCameraEnabled: cameraEnabled,
      wasSpeakerEnabled: speakerEnabled,
    );
  }

  CallMediaState? getPreHoldMediaState(String callId) => _mediaStates[callId];

  void setRemoteHoldState(String callId, String? heldBy) {
    if (heldBy != null) {
      _remoteHeldBy[callId] = heldBy;
    } else {
      _remoteHeldBy.remove(callId);
    }
    notifyListeners();
  }

  /// Handles incoming call waiting notification event.
  void handleIncomingWaitingCall({
    required String callId,
    required String callerName,
    required String callType,
  }) {
    // 1. Idempotent check: if duplicate push for existing waiting call, ignore
    if (_waitingCallId == callId) {
      debugPrint('[CALL_WAITING] duplicate waiting call event ignored: $callId');
      return;
    }

    // 2. Capacity check: Max 2 established calls (1 active + 1 waiting/held)
    if (_activeCallId != null && _heldCallId != null) {
      debugPrint(
        '[CALL_WAITING] rejected 3rd incoming call $callId: capacity full (active=$_activeCallId, held=$_heldCallId)',
      );
      unawaited(const VorynCallService().decline(callId));
      return;
    }

    _waitingCallId = callId;
    _waitingCallerName = callerName;
    _waitingCallType = callType;
    debugPrint(
      '[CALL_WAITING] event=received activeCallId=$_activeCallId waitingCallId=$callId callerName=$callerName type=$callType',
    );

    // 3. Observe canonical state in Supabase to dismiss waiting UI if caller cancels/times out
    _waitingSubscription?.unsubscribe();
    _waitingSubscription = const VorynCallService().subscribeToCallState(
      callId,
      (terminalStatus) {
        debugPrint(
          '[CALL_WAITING] waiting call $callId became terminal ($terminalStatus)',
        );
        dismissWaitingCall(callId);
      },
    );

    notifyListeners();
  }

  /// Dismisses waiting UI and cleans up native notification.
  void dismissWaitingCall(String callId) {
    if (_waitingCallId == callId) {
      _waitingCallId = null;
      _waitingCallerName = null;
      _waitingCallType = null;
      try {
        _waitingSubscription?.unsubscribe();
        _waitingSubscription = null;
      } catch (_) {}
      unawaited(LockScreenService.clearPendingIncomingCall(callId));
      notifyListeners();
    }
  }

  /// Declines the waiting call without affecting the active call.
  Future<void> declineWaitingCall(String callId) async {
    debugPrint('[CALL_WAITING] event=declined waitingCallId=$callId');
    dismissWaitingCall(callId);
    try {
      await const VorynCallService().decline(callId);
    } catch (e) {
      debugPrint('[CALL_WAITING] error declining call $callId: $e');
    }
  }

  /// Puts the active call on hold and accepts the incoming waiting call.
  Future<bool> holdAndAccept(String waitingCallId) async {
    if (_isTransitionInFlight) {
      debugPrint('[MULTI_CALL] transition already in flight, ignoring duplicate tap');
      return false;
    }
    final activeId = _activeCallId;
    if (activeId == null || activeId == waitingCallId) {
      debugPrint('[MULTI_CALL] invalid activeId=$activeId for holdAndAccept');
      return false;
    }

    _isTransitionInFlight = true;
    final currentRev = ++_revision;
    debugPrint(
      '[MULTI_CALL] event=hold_accept_start activeCallId=$activeId waitingCallId=$waitingCallId rev=$currentRev',
    );
    notifyListeners();

    final activeSession = _sessionsByCallId[activeId];
    final preHold = _mediaStates[activeId] ??
        const CallMediaState(
          wasMicEnabled: true,
          wasCameraEnabled: false,
          wasSpeakerEnabled: false,
        );

    // 1. Media suppression: Mute active session mic & silence remote audio BEFORE connecting 2nd call
    try {
      if (activeSession != null) {
        await activeSession.hold();
      }
    } catch (e) {
      debugPrint('[MULTI_CALL] error holding active session: $e');
    }

    // 2. Canonical Backend Atomic Transaction (with row-level locks)
    final rpcResult = await const VorynCallService().holdAndAccept(
      activeCallId: activeId,
      waitingCallId: waitingCallId,
    );

    final resultStatus = rpcResult?['result']?.toString();
    final isSuccess = resultStatus == 'applied' || resultStatus == 'already_applied';

    if (!isSuccess) {
      debugPrint(
        '[MULTI_CALL] hold_and_accept rejected by backend: ${rpcResult?['reason']}',
      );
      // Rollback active call locally
      try {
        if (activeSession != null) {
          await activeSession.resume(
            restoreMic: preHold.wasMicEnabled,
            restoreCamera: preHold.wasCameraEnabled,
          );
        }
      } catch (_) {}
      _isTransitionInFlight = false;
      notifyListeners();
      return false;
    }

    // 3. Dismiss waiting UI & cancel waiting subscription
    dismissWaitingCall(waitingCallId);

    // 4. Update Native MultiCallState
    await LockScreenService.markCallHeldAndAccepted(
      heldCallId: activeId,
      activeCallId: waitingCallId,
      callerName: _waitingCallerName,
      callType: _waitingCallType,
    );

    // 5. Update local state
    _heldCallId = activeId;
    _activeCallId = waitingCallId;

    // 6. Connect waiting call session via coordinator
    try {
      final isVideo = _waitingCallType == 'video';
      final newCoordinator = VorynCallRuntimeCoordinator.forCall(waitingCallId);
      final newSession = await newCoordinator.connect(video: isVideo);
      registerSession(waitingCallId, newSession);

      // Re-apply audio route for new active call
      await VorynAudioRouteService.instance.setDefaultAudioRoute(isVideo: isVideo);
      newCoordinator.updateProximity(isConnected: true, mediaMode: isVideo ? 'video' : 'audio', isHeld: false);

      debugPrint(
        '[MULTI_CALL] event=hold_accept_complete activeCallId=$waitingCallId heldCallId=$activeId rev=$currentRev',
      );
      _isTransitionInFlight = false;
      notifyListeners();
      return true;
    } catch (connectError) {
      debugPrint('[MULTI_CALL] connection error for second call: $connectError');
      // ROLLBACK PATH (Requirement 12 & 20)
      // Mark second call failed
      unawaited(const VorynCallService().end(waitingCallId));
      // Resume held call on backend
      unawaited(const VorynCallService().setCallHoldState(activeId, false));
      // Resume held call locally
      if (activeSession != null) {
        await activeSession.resume(
          restoreMic: preHold.wasMicEnabled,
          restoreCamera: preHold.wasCameraEnabled,
        );
      }
      _activeCallId = activeId;
      _heldCallId = null;
      await LockScreenService.resumeHeldCall(activeId);
      VorynCallRuntimeCoordinator.forCall(activeId).updateProximity(
        isConnected: true,
        mediaMode: 'audio',
        isHeld: false,
      );

      _isTransitionInFlight = false;
      notifyListeners();
      return false;
    }
  }

  /// Switches between the currently active call and the currently held call.
  Future<bool> switchCalls() async {
    if (_isTransitionInFlight) {
      debugPrint('[MULTI_CALL] switch already in flight, ignoring duplicate tap');
      return false;
    }
    final activeId = _activeCallId;
    final heldId = _heldCallId;
    if (activeId == null || heldId == null) {
      debugPrint('[MULTI_CALL] cannot switch without both active ($activeId) and held ($heldId)');
      return false;
    }

    _isTransitionInFlight = true;
    final currentRev = ++_revision;
    debugPrint('[MULTI_CALL] event=switch_start from=$activeId to=$heldId rev=$currentRev');
    notifyListeners();

    final activeSession = _sessionsByCallId[activeId];
    final heldSession = _sessionsByCallId[heldId];

    final preHoldHeld = _mediaStates[heldId] ??
        const CallMediaState(
          wasMicEnabled: true,
          wasCameraEnabled: false,
          wasSpeakerEnabled: false,
        );

    // 1. Silence and mute current active call FIRST to prevent dual mic capture
    try {
      if (activeSession != null) {
        await activeSession.hold();
      }
    } catch (e) {
      debugPrint('[MULTI_CALL] error muting old active session: $e');
    }

    // 2. Canonical Backend Atomic Swap
    final rpcResult = await const VorynCallService().switchHeldCall(
      activeCallId: activeId,
      heldCallId: heldId,
    );

    final resultStatus = rpcResult?['result']?.toString();
    final isSuccess = resultStatus == 'applied' || resultStatus == 'already_applied';

    if (!isSuccess) {
      debugPrint('[MULTI_CALL] switch rejected by backend: ${rpcResult?['reason']}');
      // Rollback old active call
      final preHoldActive = _mediaStates[activeId];
      if (activeSession != null && preHoldActive != null) {
        await activeSession.resume(
          restoreMic: preHoldActive.wasMicEnabled,
          restoreCamera: preHoldActive.wasCameraEnabled,
        );
      }
      _isTransitionInFlight = false;
      notifyListeners();
      return false;
    }

    // 3. Swap roles
    _activeCallId = heldId;
    _heldCallId = activeId;

    // 4. Update Native MultiCallState
    await LockScreenService.markCallSwapped(
      newActiveCallId: heldId,
      newHeldCallId: activeId,
    );

    // 5. Restore media for new active session
    if (heldSession != null) {
      await heldSession.resume(
        restoreMic: preHoldHeld.wasMicEnabled,
        restoreCamera: preHoldHeld.wasCameraEnabled,
      );
    }

    // 6. Transfer proximity & audio focus to new active call
    VorynCallRuntimeCoordinator.forCall(heldId).updateProximity(
      isConnected: true,
      mediaMode: 'audio',
      isHeld: false,
    );

    debugPrint('[MULTI_CALL] event=switch_complete active=$heldId held=$activeId rev=$currentRev');
    _isTransitionInFlight = false;
    notifyListeners();
    return true;
  }

  /// Handles ending a specific call (active or held).
  Future<void> endCall(String callId, {bool isLocalInitiator = true}) async {
    debugPrint('[MULTI_CALL] endCall requested for callId=$callId (active=$_activeCallId, held=$_heldCallId)');

    // 1. If it's the waiting call
    if (callId == _waitingCallId) {
      dismissWaitingCall(callId);
      if (isLocalInitiator) {
        await const VorynCallService().decline(callId);
      }
      return;
    }

    // 2. If it's the held call (Requirement 23: held call termination does not touch active hardware)
    if (callId == _heldCallId) {
      debugPrint('[MULTI_CALL] held call $callId ended. Cleaning up held session only.');
      final session = _sessionsByCallId[callId];
      if (session != null) {
        try {
          await session.disconnect();
        } catch (_) {}
      }
      removeSession(callId);
      _heldCallId = null;
      await LockScreenService.clearHeldCall(callId);
      if (isLocalInitiator) {
        await const VorynCallService().end(callId);
      }
      notifyListeners();
      return;
    }

    // 3. If it's the active call and a held call exists (Requirement 22 & 38: auto-resume held call)
    if (callId == _activeCallId && _heldCallId != null) {
      final resumedId = _heldCallId!;
      debugPrint(
        '[MULTI_CALL] event=resume_after_end ended=$callId resumed=$resumedId',
      );

      final activeSession = _sessionsByCallId[callId];
      if (activeSession != null) {
        try {
          await activeSession.disconnect();
        } catch (_) {}
      }
      removeSession(callId);

      if (isLocalInitiator) {
        unawaited(const VorynCallService().end(callId));
      }

      // Promote held call to active
      _activeCallId = resumedId;
      _heldCallId = null;

      // Unhold resumed call on backend
      unawaited(const VorynCallService().setCallHoldState(resumedId, false));

      // Restore native ongoing notification & state for resumed call
      await LockScreenService.resumeHeldCall(resumedId);

      // Restore media on resumed session
      final resumedSession = _sessionsByCallId[resumedId];
      final preHold = _mediaStates[resumedId] ??
          const CallMediaState(
            wasMicEnabled: true,
            wasCameraEnabled: false,
            wasSpeakerEnabled: false,
          );

      if (resumedSession != null) {
        await resumedSession.resume(
          restoreMic: preHold.wasMicEnabled,
          restoreCamera: preHold.wasCameraEnabled,
        );
      }

      // Reclaim proximity & audio route
      VorynCallRuntimeCoordinator.forCall(resumedId).updateProximity(
        isConnected: true,
        mediaMode: 'audio',
        isHeld: false,
      );

      notifyListeners();
      return;
    }

    // 4. Final call ended (Requirement 40: full call runtime teardown)
    debugPrint('[MULTI_CALL] final call $callId ended. Performing full teardown.');
    final finalSession = _sessionsByCallId[callId];
    if (finalSession != null) {
      try {
        await finalSession.disconnect();
      } catch (_) {}
    }
    removeSession(callId);
    _activeCallId = null;
    _heldCallId = null;
    _waitingCallId = null;

    if (isLocalInitiator) {
      await const VorynCallService().end(callId);
    }
    notifyListeners();
  }
}
