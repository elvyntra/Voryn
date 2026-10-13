import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import 'voryn_audio_route_service.dart';
import 'voryn_call_runtime_coordinator.dart';
import 'voryn_call_service.dart';
import 'voryn_livekit_service.dart';

enum MergeStatus {
  idle,
  preparing,
  waitingForParticipant,
  participantJoining,
  finalizing,
  committed,
  cancelling,
  rollingBack,
  failed,
}

class MergeOperationState {
  final MergeStatus status;
  final String? mergeOperationId;
  final String? primaryCallId;
  final String? secondaryCallId;
  final String? joiningUserUid;
  final DateTime? expiresAt;
  final String? failureReason;

  const MergeOperationState({
    required this.status,
    this.mergeOperationId,
    this.primaryCallId,
    this.secondaryCallId,
    this.joiningUserUid,
    this.expiresAt,
    this.failureReason,
  });

  MergeOperationState copyWith({
    MergeStatus? status,
    String? mergeOperationId,
    String? primaryCallId,
    String? secondaryCallId,
    String? joiningUserUid,
    DateTime? expiresAt,
    String? failureReason,
  }) {
    return MergeOperationState(
      status: status ?? this.status,
      mergeOperationId: mergeOperationId ?? this.mergeOperationId,
      primaryCallId: primaryCallId ?? this.primaryCallId,
      secondaryCallId: secondaryCallId ?? this.secondaryCallId,
      joiningUserUid: joiningUserUid ?? this.joiningUserUid,
      expiresAt: expiresAt ?? this.expiresAt,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}

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

  @visibleForTesting
  VorynCallService callService = const VorynCallService();

  @visibleForTesting
  VorynLiveKitService liveKitService = const VorynLiveKitService();

  final Map<String, VorynLiveKitSession> _sessionsByCallId = {};
  final Map<String, CallMediaState> _mediaStates = {};

  String? _activeCallId;
  String? _heldCallId;
  String? _waitingCallId;
  String? _waitingCallerName;
  String? _waitingCallType;

  // Remote hold state tracking
  final Map<String, String?> _remoteHeldBy = {};
  final Map<String, String> _callTypes = {};

  RealtimeChannel? _waitingSubscription;
  int _revision = 0;
  bool _isTransitionInFlight = false;

  // Two-Phase Merge State
  MergeOperationState _mergeState =
      const MergeOperationState(status: MergeStatus.idle);
  Timer? _mergeTimeoutTimer;
  RealtimeChannel? _mergeSubscription;
  VorynLiveKitSession? _provisionalSession;

  final ValueNotifier<String?> mergeErrorNotifier =
      ValueNotifier<String?>(null);

  MergeOperationState get mergeState => _mergeState;
  VorynLiveKitSession? get provisionalSession => _provisionalSession;
  bool get isMerging =>
      _mergeState.status != MergeStatus.idle &&
      _mergeState.status != MergeStatus.failed &&
      _mergeState.status != MergeStatus.committed;

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

  final Set<String> _conferenceCallIds = {};
  final Set<String> _initiatorCallIds = {};

  bool isConference(String callId) => _conferenceCallIds.contains(callId);
  bool isCallInitiator(String callId) => _initiatorCallIds.contains(callId);

  void markConference(String callId, {bool isInitiator = false}) {
    _conferenceCallIds.add(callId);
    if (isInitiator) {
      _initiatorCallIds.add(callId);
    }
    notifyListeners();
  }

  String getCallType(String callId) {
    if (_callTypes.containsKey(callId)) return _callTypes[callId]!;
    if (_mediaStates[callId]?.wasCameraEnabled == true) return 'video';
    final session = _sessionsByCallId[callId];
    if (session?.localVideoTrack != null) return 'video';
    try {
      if (session?.room.localParticipant?.videoTrackPublications.isNotEmpty ?? false) {
        return 'video';
      }
    } catch (_) {}
    return 'audio';
  }

  void recordCallType(String callId, String type) {
    _callTypes[callId] = type;
  }

  void registerSession(String callId, VorynLiveKitSession session, {String? callType}) {
    _sessionsByCallId[callId] = session;
    if (callType != null) {
      _callTypes[callId] = callType;
    }
    _activeCallId ??= callId;
    debugPrint('[AUDIO_OWNER] callId=$_activeCallId');
    debugPrint('[PROXIMITY_OWNER] callId=$_activeCallId');
    debugPrint(
      '[MULTI_CALL_SESSION] callId=$callId roomConnected=true role=${callId == _activeCallId ? "ACTIVE" : "HELD"} engineId=primary',
    );
    notifyListeners();
  }


  void removeSession(String callId) {
    _sessionsByCallId.remove(callId);
    _mediaStates.remove(callId);
    _remoteHeldBy.remove(callId);
    _callTypes.remove(callId);
    _conferenceCallIds.remove(callId);
    _initiatorCallIds.remove(callId);
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
      unawaited(callService.decline(callId));
      return;
    }

    _waitingCallId = callId;
    _waitingCallerName = callerName;
    _waitingCallType = callType;
    _callTypes[callId] = callType;
    debugPrint(
      '[CALL_WAITING] event=received activeCallId=$_activeCallId waitingCallId=$callId callerName=$callerName type=$callType',
    );

    // 3. Observe canonical state in Supabase to dismiss waiting UI if caller cancels/times out
    _waitingSubscription?.unsubscribe();
    _waitingSubscription = callService.subscribeToCallState(
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
      await callService.decline(callId);
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
    final bool isSessionCameraActive = activeSession?.localVideoTrack != null ||
        (activeSession?.room.localParticipant?.videoTrackPublications.any((p) => p.track != null && !p.muted) ?? false);
    final preHold = _mediaStates[activeId] ??
        CallMediaState(
          wasMicEnabled: true,
          wasCameraEnabled: isSessionCameraActive || getCallType(activeId) == 'video',
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
    final rpcResult = await callService.holdAndAccept(
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
      final isVideo = getCallType(waitingCallId) == 'video';
      final newCoordinator = VorynCallRuntimeCoordinator.forCall(waitingCallId);
      final newSession = await newCoordinator.connect(video: isVideo);
      registerSession(waitingCallId, newSession, callType: isVideo ? 'video' : 'audio');

      // Re-apply audio route for new active call
      await VorynAudioRouteService.instance.setDefaultAudioRoute(isVideo: isVideo);
      newCoordinator.updateProximity(isConnected: true, mediaMode: isVideo ? 'video' : 'audio', isHeld: false);

      debugPrint('[AUDIO_OWNER] callId=$waitingCallId');
      debugPrint('[PROXIMITY_OWNER] callId=$waitingCallId');
      for (final entry in _sessionsByCallId.entries) {
        final role = entry.key == _activeCallId ? 'ACTIVE' : 'HELD';
        debugPrint(
          '[MULTI_CALL_SESSION] callId=${entry.key} roomConnected=true role=$role engineId=primary',
        );
      }

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
      unawaited(callService.end(waitingCallId));
      // Resume held call on backend
      unawaited(callService.setCallHoldState(activeId, false));
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

    final isHeldVideo = getCallType(heldId) == 'video';
    final preHoldHeld = _mediaStates[heldId] ??
        CallMediaState(
          wasMicEnabled: true,
          wasCameraEnabled: isHeldVideo,
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
    final rpcResult = await callService.switchHeldCall(
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
        restoreCamera: preHoldHeld.wasCameraEnabled || isHeldVideo,
      );
    }

    // 6. Transfer proximity & audio focus to new active call
    VorynCallRuntimeCoordinator.forCall(heldId).updateProximity(
      isConnected: true,
      mediaMode: isHeldVideo ? 'video' : 'audio',
      isHeld: false,
    );

    debugPrint('[AUDIO_OWNER] callId=$heldId');
    debugPrint('[PROXIMITY_OWNER] callId=$heldId');
    for (final entry in _sessionsByCallId.entries) {
      final role = entry.key == _activeCallId ? 'ACTIVE' : 'HELD';
      debugPrint(
        '[MULTI_CALL_SESSION] callId=${entry.key} roomConnected=true role=$role engineId=primary',
      );
    }

    debugPrint('[MULTI_CALL] event=switch_complete active=$heldId held=$activeId rev=$currentRev');

    _isTransitionInFlight = false;
    notifyListeners();
    return true;
  }

  /// Handles ending a specific call (active or held).
  Future<void> endCall(String callId, {bool isLocalInitiator = true}) async {
    debugPrint('[MULTI_CALL] endCall requested for callId=$callId (active=$_activeCallId, held=$_heldCallId)');

    // Mid-merge call termination safety: cancel any in-flight merge first
    if (isMerging) {
      debugPrint('[MULTI_CALL] call ended while merge in flight; cancelling merge operation');
      await cancelMerge(reason: 'call_ended_mid_merge');
    }

    // 1. If it's the waiting call
    if (callId == _waitingCallId) {
      dismissWaitingCall(callId);
      if (isLocalInitiator) {
        await callService.decline(callId);
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
        await callService.end(callId);
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
        unawaited(callService.end(callId));
      }

      // Promote held call to active
      _activeCallId = resumedId;
      _heldCallId = null;

      // Unhold resumed call on backend
      unawaited(callService.setCallHoldState(resumedId, false));

      // Restore native ongoing notification & state for resumed call
      await LockScreenService.resumeHeldCall(resumedId);

      // Restore media on resumed session
      final resumedSession = _sessionsByCallId[resumedId];
      final isResumedVideo = getCallType(resumedId) == 'video';
      final preHold = _mediaStates[resumedId] ??
          CallMediaState(
            wasMicEnabled: true,
            wasCameraEnabled: isResumedVideo,
            wasSpeakerEnabled: false,
          );

      if (resumedSession != null) {
        await resumedSession.resume(
          restoreMic: preHold.wasMicEnabled,
          restoreCamera: preHold.wasCameraEnabled || isResumedVideo,
        );
      }

      // Reclaim proximity & audio route
      VorynCallRuntimeCoordinator.forCall(resumedId).updateProximity(
        isConnected: true,
        mediaMode: isResumedVideo ? 'video' : 'audio',
        isHeld: false,
      );

      debugPrint('[AUDIO_OWNER] callId=$resumedId');
      debugPrint('[PROXIMITY_OWNER] callId=$resumedId');
      for (final entry in _sessionsByCallId.entries) {
        final role = entry.key == _activeCallId ? 'ACTIVE' : 'HELD';
        debugPrint(
          '[MULTI_CALL_SESSION] callId=${entry.key} roomConnected=true role=$role engineId=primary',
        );
      }

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
      await callService.end(callId);
    }
    notifyListeners();
  }

  void _setMergeStatus(
    MergeStatus newStatus, {
    String? mergeOperationId,
    String? primaryCallId,
    String? secondaryCallId,
    String? joiningUserUid,
    DateTime? expiresAt,
    String? failureReason,
  }) {
    final oldStatus = _mergeState.status;
    _mergeState = _mergeState.copyWith(
      status: newStatus,
      mergeOperationId: mergeOperationId,
      primaryCallId: primaryCallId,
      secondaryCallId: secondaryCallId,
      joiningUserUid: joiningUserUid,
      expiresAt: expiresAt,
      failureReason: failureReason,
    );
    debugPrint(
      '[MERGE_STATE] from=$oldStatus to=$newStatus opId=${_mergeState.mergeOperationId ?? "none"}',
    );
    notifyListeners();
  }

  /// Initiates two-phase merge of held primary call and active secondary call.
  Future<bool> mergeCalls() async {
    if (_isTransitionInFlight || isMerging) {
      debugPrint('[MERGE_CALLS] Merge or transition already in flight, ignoring duplicate tap');
      return false;
    }
    final primaryId = _heldCallId;
    final secondaryId = _activeCallId;
    if (primaryId == null || secondaryId == null) {
      debugPrint(
        '[MERGE_CALLS] Cannot merge without both held ($primaryId) and active ($secondaryId) calls',
      );
      return false;
    }

    _isTransitionInFlight = true;
    _setMergeStatus(
      MergeStatus.preparing,
      primaryCallId: primaryId,
      secondaryCallId: secondaryId,
    );

    final result = await callService.prepareCallMerge(
      primaryCallId: primaryId,
      secondaryCallId: secondaryId,
    );

    final isPrepared =
        result?['result'] == 'prepared' || result?['result'] == 'already_prepared';
    if (!isPrepared) {
      final reason = result?['reason']?.toString() ?? 'prepare_failed';
      debugPrint('[MERGE_CALLS] prepareCallMerge rejected: $reason');
      _setMergeStatus(MergeStatus.failed, failureReason: reason);
      mergeErrorNotifier.value = 'Failed to merge calls: $reason';
      _isTransitionInFlight = false;
      _setMergeStatus(MergeStatus.idle);
      return false;
    }

    final opId = result!['merge_operation_id']?.toString() ??
        result['id']?.toString() ??
        '';
    final joiningUid = result['joining_user_uid']?.toString();
    final expiresAtStr = result['expires_at']?.toString();
    final expiresAt =
        expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;

    _setMergeStatus(
      MergeStatus.waitingForParticipant,
      mergeOperationId: opId,
      joiningUserUid: joiningUid,
      expiresAt: expiresAt,
    );

    _broadcastMergeSignal(
      secondaryCallId: secondaryId,
      mergeOpId: opId,
      primaryCallId: primaryId,
      joiningUid: joiningUid,
    );

    _startMergeTimeout(opId);

    _subscribeToMergeEvents(
      opId: opId,
      secondaryCallId: secondaryId,
      primaryCallId: primaryId,
    );

    return true;
  }

  /// Finalizes the merge operation once server confirms participant presence.
  Future<bool> finalizeMerge(String mergeOperationId) async {
    // Stale operation protection: ignore if not matching active merge operation ID
    if (_mergeState.mergeOperationId != mergeOperationId) {
      debugPrint(
        '[MERGE_CALLS] finalizeMerge ignored stale opId=$mergeOperationId (active=${_mergeState.mergeOperationId})',
      );
      return false;
    }

    if (_mergeState.status == MergeStatus.finalizing ||
        _mergeState.status == MergeStatus.committed) {
      return false;
    }

    _setMergeStatus(MergeStatus.finalizing);

    final result = await callService.finalizeCallMerge(
      mergeOperationId: mergeOperationId,
    );
    final isCommitted =
        result?['result'] == 'committed' || result?['result'] == 'already_committed';

    if (!isCommitted) {
      final reason = result?['reason']?.toString() ??
          result?['error']?.toString() ??
          'finalize_failed';
      if (reason == 'participant_not_in_livekit_room' && isMerging) {
        debugPrint(
          '[MERGE_CALLS] Participant not in LiveKit room yet, returning to waitingForParticipant',
        );
        _setMergeStatus(MergeStatus.waitingForParticipant);
        return false;
      }

      debugPrint('[MERGE_CALLS] finalizeCallMerge rejected: $reason');
      await cancelMerge(mergeOperationId: mergeOperationId, reason: reason);
      return false;
    }

    _cancelMergeTimeout();
    _unsubscribeMergeEvents();

    final primaryId = _mergeState.primaryCallId;
    final secondaryId = _mergeState.secondaryCallId;
    if (primaryId == null || secondaryId == null) {
      _isTransitionInFlight = false;
      _setMergeStatus(MergeStatus.idle);
      return true;
    }

    _setMergeStatus(MergeStatus.committed);

    // 1. Broadcast commit event to participants
    _broadcastMergeCommitted(
      secondaryCallId: secondaryId,
      primaryCallId: primaryId,
      mergeOpId: mergeOperationId,
    );

    // 2. Resume primary session (unhold locally)
    final primarySession = _sessionsByCallId[primaryId];
    final isPrimaryVideo = getCallType(primaryId) == 'video';
    final preHold = _mediaStates[primaryId] ??
        CallMediaState(
          wasMicEnabled: true,
          wasCameraEnabled: isPrimaryVideo,
          wasSpeakerEnabled: false,
        );

    if (primarySession != null) {
      await primarySession.resume(
        restoreMic: preHold.wasMicEnabled,
        restoreCamera: preHold.wasCameraEnabled || isPrimaryVideo,
      );
    }

    // 3. Dispose secondary session locally
    final secondarySession = _sessionsByCallId[secondaryId];
    if (secondarySession != null) {
      try {
        await secondarySession.disconnect();
      } catch (_) {}
    }
    removeSession(secondaryId);

    // 4. Promote primary to active conference call
    _activeCallId = primaryId;
    _heldCallId = null;
    markConference(primaryId, isInitiator: true);

    // 5. Update native lock screen state
    await LockScreenService.resumeHeldCall(primaryId);

    // 6. Transfer proximity & audio focus to primary room
    VorynCallRuntimeCoordinator.forCall(primaryId).updateProximity(
      isConnected: true,
      mediaMode: isPrimaryVideo ? 'video' : 'audio',
      isHeld: false,
    );

    debugPrint('[AUDIO_OWNER] callId=$primaryId (conference)');
    debugPrint('[PROXIMITY_OWNER] callId=$primaryId (conference)');
    for (final entry in _sessionsByCallId.entries) {
      debugPrint(
        '[MULTI_CALL_SESSION] callId=${entry.key} roomConnected=true role=ACTIVE engineId=primary',
      );
    }

    _isTransitionInFlight = false;
    _setMergeStatus(MergeStatus.idle);
    return true;
  }

  /// Cancels in-flight merge and rolls back state.
  Future<void> cancelMerge({
    String? mergeOperationId,
    String reason = 'client_aborted',
  }) async {
    // Stale operation protection: ignore if not matching active merge operation ID
    if (mergeOperationId != null &&
        _mergeState.mergeOperationId != mergeOperationId) {
      debugPrint(
        '[MERGE_CALLS] cancelMerge ignored stale opId=$mergeOperationId (active=${_mergeState.mergeOperationId})',
      );
      return;
    }

    _cancelMergeTimeout();
    _unsubscribeMergeEvents();

    final opId = mergeOperationId ?? _mergeState.mergeOperationId;
    final secondaryId = _mergeState.secondaryCallId;

    _setMergeStatus(MergeStatus.cancelling);

    if (opId != null) {
      unawaited(
        callService.cancelCallMerge(mergeOperationId: opId, reason: reason),
      );
      if (secondaryId != null) {
        _broadcastMergeCancelled(
          secondaryCallId: secondaryId,
          mergeOpId: opId,
        );
      }
    }

    _setMergeStatus(MergeStatus.rollingBack);

    if (_provisionalSession != null) {
      try {
        await _provisionalSession?.disconnect();
      } catch (_) {}
      _provisionalSession = null;
    }

    _isTransitionInFlight = false;
    _setMergeStatus(MergeStatus.idle, failureReason: reason);

    if (reason != 'client_aborted') {
      mergeErrorNotifier.value = 'Call merge could not be completed ($reason).';
    }
  }

  /// Invoked when User C detects a merge request.
  Future<void> handleMergeDetectedForJoining(Map<String, dynamic> mergeOp) async {
    final currentUserId = VorynBackend.client?.auth.currentUser?.id;
    final joiningUid = mergeOp['joining_user_uid']?.toString() ??
        mergeOp['joiningUserUid']?.toString();
    if (currentUserId != null &&
        joiningUid != null &&
        currentUserId != joiningUid) {
      return;
    }

    final opId = mergeOp['id']?.toString() ??
        mergeOp['merge_operation_id']?.toString() ??
        mergeOp['mergeOperationId']?.toString();
    final primaryCallId = mergeOp['primary_call_id']?.toString() ??
        mergeOp['primaryCallId']?.toString();
    final secondaryCallId = mergeOp['secondary_call_id']?.toString() ??
        mergeOp['secondaryCallId']?.toString();
    if (opId == null || primaryCallId == null) return;
    if (_mergeState.status != MergeStatus.idle) return;

    _setMergeStatus(
      MergeStatus.participantJoining,
      mergeOperationId: opId,
      primaryCallId: primaryCallId,
      secondaryCallId: secondaryCallId,
      joiningUserUid: currentUserId,
    );

    try {
      debugPrint(
        '[MERGE_JOIN] connecting provisionally to primary room $primaryCallId for op $opId',
      );
      final session = await liveKitService.connectProvisional(
        primaryCallId: primaryCallId,
        mergeOperationId: opId,
      );
      _provisionalSession = session;
      debugPrint(
        '[MERGE_JOIN] provisional connection established (media-silent)',
      );

      // Notify User A via broadcast on secondary call room
      if (secondaryCallId != null) {
        final client = VorynBackend.client;
        if (client != null) {
          final channel = client.channel('call_room_$secondaryCallId');
          channel.sendBroadcastMessage(
            event: 'merge_participant_joined',
            payload: {
              'mergeOperationId': opId,
              'primaryCallId': primaryCallId,
              'secondaryCallId': secondaryCallId,
            },
          );
        }
      }
    } catch (e) {
      debugPrint('[MERGE_JOIN] provisional connection error: $e');
      await rollbackProvisional(primaryCallId);
    }
  }

  /// Promotes User C's provisional primary session to active conference call on commit.
  Future<void> promoteProvisionalToActiveConference(String primaryCallId) async {
    _setMergeStatus(MergeStatus.committed);

    final secondaryId = _mergeState.secondaryCallId;
    if (secondaryId != null) {
      final secondarySession = _sessionsByCallId[secondaryId];
      if (secondarySession != null) {
        try {
          await secondarySession.disconnect();
        } catch (_) {}
      }
      removeSession(secondaryId);
    }

    final promoted = _provisionalSession;
    _provisionalSession = null;
    if (promoted != null) {
      final isVideo = getCallType(primaryCallId) == 'video';
      registerSession(primaryCallId, promoted, callType: isVideo ? 'video' : 'audio');
      try {
        await promoted.setMicrophoneEnabled(true);
        if (isVideo) {
          await promoted.setCameraEnabled(true);
        }
        await VorynAudioRouteService.instance.setDefaultAudioRoute(isVideo: isVideo);
        VorynCallRuntimeCoordinator.forCall(primaryCallId).updateProximity(
          isConnected: true,
          mediaMode: isVideo ? 'video' : 'audio',
          isHeld: false,
        );
      } catch (_) {}
    }

    _activeCallId = primaryCallId;
    _heldCallId = null;
    markConference(primaryCallId, isInitiator: false);
    _setMergeStatus(MergeStatus.idle);
  }

  /// Rolls back User C's provisional session on merge cancellation or failure.
  Future<void> rollbackProvisional(String? primaryCallId) async {
    _setMergeStatus(MergeStatus.rollingBack);
    if (_provisionalSession != null) {
      try {
        await _provisionalSession?.disconnect();
      } catch (_) {}
      _provisionalSession = null;
    }
    _setMergeStatus(MergeStatus.idle);
  }

  /// Reconciles merge operation state on application resume.
  Future<void> reconcileMergeOnResume() async {
    final opId = _mergeState.mergeOperationId;
    if (opId == null) {
      if (_activeCallId != null) {
        await reconcileCallStateOnResume(_activeCallId!);
      }
      return;
    }

    try {
      final op = await callService.getCallMergeOperation(opId);
      if (op == null) return;

      final status = op['status']?.toString();
      final expiresAtStr = op['expires_at']?.toString();
      final expiresAt =
          expiresAtStr != null ? DateTime.tryParse(expiresAtStr)?.toUtc() : null;
      final nowUtc = DateTime.now().toUtc();
      final isExpired = expiresAt != null && expiresAt.isBefore(nowUtc);

      if (status == 'committed') {
        final primaryId =
            op['primary_call_id']?.toString() ?? _mergeState.primaryCallId;
        if (primaryId != null) {
          if (_provisionalSession != null) {
            await promoteProvisionalToActiveConference(primaryId);
          } else if (_heldCallId == primaryId) {
            await finalizeMerge(opId);
          } else {
            // Passive participant (User B) or already merged
            _setMergeStatus(MergeStatus.idle);
            setRemoteHoldState(primaryId, null);
          }
        }
      } else if (status == 'cancelled' || status == 'expired' || isExpired) {
        await cancelMerge(
          mergeOperationId: opId,
          reason: isExpired ? 'expired' : (status ?? 'expired'),
        );
      } else if (status == 'prepared' || status == 'joining') {
        final remaining = expiresAt != null
            ? expiresAt.difference(nowUtc)
            : const Duration(seconds: 25);
        if (remaining > Duration.zero) {
          _startMergeTimeout(opId, remaining);
        }
        final currentUserId = VorynBackend.client?.auth.currentUser?.id;
        final joiningUid = op['joining_user_uid']?.toString();
        if (currentUserId != null &&
            joiningUid == currentUserId &&
            _provisionalSession == null) {
          await handleMergeDetectedForJoining(op);
        } else if (_heldCallId != null && status == 'joining') {
          await finalizeMerge(opId);
        }
      }
    } catch (e) {
      debugPrint('[MERGE_CALLS] reconcileMergeOnResume error: $e');
    }
  }

  /// Reconciles authoritative call state for participant on resume (e.g., User B held -> conference).
  Future<void> reconcileCallStateOnResume(String callId) async {
    try {
      final callData = await callService.getCall(callId);
      if (callData == null) return;

      final status = callData['status']?.toString();
      final heldBy = callData['held_by']?.toString();
      final mergedInto = callData['merged_into_call_id']?.toString();

      // Case 1: Secondary call was merged into primary conference
      if (mergedInto != null && _sessionsByCallId.containsKey(callId)) {
        if (_provisionalSession != null) {
          await promoteProvisionalToActiveConference(mergedInto);
        } else {
          final oldSession = _sessionsByCallId[callId];
          await oldSession?.disconnect();
          removeSession(callId);
          _activeCallId = mergedInto;
        }
        return;
      }

      // Case 2: Held participant B whose call transitioned to unheld / connected conference
      if (status == 'connected' && heldBy == null) {
        setRemoteHoldState(callId, null);
        final session = _sessionsByCallId[callId];
        if (session != null && session.isHeld) {
          final preHold = _mediaStates[callId] ??
              const CallMediaState(
                wasMicEnabled: true,
                wasCameraEnabled: false,
                wasSpeakerEnabled: false,
              );
          await session.resume(
            restoreMic: preHold.wasMicEnabled,
            restoreCamera: preHold.wasCameraEnabled,
          );
        }
      } else if (status == 'on_hold') {
        setRemoteHoldState(callId, heldBy);
      }
    } catch (e) {
      debugPrint('[CALL_RESUME] reconcileCallStateOnResume error for $callId: $e');
    }
  }

  /// Reconciles call state on app cold start / process restart.
  Future<void> recoverFromColdRestart({
    String? userId,
    Future<List<Map<String, dynamic>>> Function(String uid)? activeCallsFetcher,
  }) async {
    resetMergeState();
    final client = VorynBackend.client;
    final currentUid = userId ?? client?.auth.currentUser?.id;
    if (currentUid == null) return;

    try {
      final List<dynamic> records;
      if (activeCallsFetcher != null) {
        records = await activeCallsFetcher(currentUid);
      } else {
        final dynamic res = await client?.from('call_participants')
            .select('call_id, calls!inner(id, status, held_by, merged_into_call_id)')
            .eq('user_uid', currentUid)
            .isFilter('left_at', null)
            .inFilter('calls.status', ['connected', 'on_hold']);
        records = res is List ? res : const [];
      }

      if (records.isNotEmpty) {
        for (final item in records) {
          final callMap = (item is Map && item['calls'] is Map)
              ? item['calls'] as Map<String, dynamic>
              : (item is Map ? Map<String, dynamic>.from(item) : null);
          if (callMap == null) continue;
          final callId = callMap['id']?.toString() ?? item['call_id']?.toString();
          final status = callMap['status']?.toString();
          final heldBy = callMap['held_by']?.toString();
          final mergedInto = callMap['merged_into_call_id']?.toString();

          if (callId == null) continue;

          final canonicalCallId = mergedInto ?? callId;
          _activeCallId ??= canonicalCallId;
          if (status == 'on_hold' && heldBy != null) {
            _remoteHeldBy[canonicalCallId] = heldBy;
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[COLD_RESTART] recoverFromColdRestart error: $e');
    }
  }

  void _startMergeTimeout(String opId, [Duration duration = const Duration(seconds: 30)]) {
    _cancelMergeTimeout();
    _mergeTimeoutTimer = Timer(duration, () {
      if (isMerging && _mergeState.mergeOperationId == opId) {
        debugPrint(
          '[MERGE_TIMEOUT] TTL expired without commit. Cancelling merge for op $opId.',
        );
        unawaited(cancelMerge(mergeOperationId: opId, reason: 'timeout'));
      }
    });
  }

  void _cancelMergeTimeout() {
    _mergeTimeoutTimer?.cancel();
    _mergeTimeoutTimer = null;
  }

  void _subscribeToMergeEvents({
    required String opId,
    required String secondaryCallId,
    required String primaryCallId,
  }) {
    _unsubscribeMergeEvents();
    final client = VorynBackend.client;
    if (client == null) return;

    final channel = client.channel('merge_op_$opId');
    _mergeSubscription = channel;

    channel.onBroadcast(
      event: 'merge_participant_joined',
      callback: (payload) {
        final payloadOpId = payload['mergeOperationId']?.toString() ??
            payload['merge_operation_id']?.toString();
        if (payloadOpId == opId &&
            _mergeState.status == MergeStatus.waitingForParticipant) {
          debugPrint(
            '[MERGE_CALLS] Received merge_participant_joined broadcast for op $opId',
          );
          unawaited(finalizeMerge(opId));
        }
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'call_merge_operations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: opId,
      ),
      callback: (payload) {
        final status = payload.newRecord['status']?.toString();
        debugPrint(
          '[MERGE_CALLS] Postgres CDC update on call_merge_operations: status=$status',
        );
        if (status == 'joining' &&
            _mergeState.status == MergeStatus.waitingForParticipant) {
          debugPrint('[MERGE_CALLS] Merge op status is joining, finalizing merge $opId');
          unawaited(finalizeMerge(opId));
        } else if (status == 'committed' &&
            _mergeState.status != MergeStatus.committed) {
          unawaited(finalizeMerge(opId));
        } else if (status == 'cancelled' || status == 'expired') {
          unawaited(cancelMerge(reason: status ?? 'expired'));
        }
      },
    );

    channel.subscribe();
  }

  void _unsubscribeMergeEvents() {
    try {
      _mergeSubscription?.unsubscribe();
    } catch (_) {}
    _mergeSubscription = null;
  }

  void _broadcastMergeSignal({
    required String secondaryCallId,
    required String mergeOpId,
    required String primaryCallId,
    String? joiningUid,
  }) {
    final client = VorynBackend.client;
    if (client == null) return;
    try {
      final channel = client.channel('call_room_$secondaryCallId');
      channel.sendBroadcastMessage(
        event: 'call_merging',
        payload: {
          'mergeOperationId': mergeOpId,
          'primaryCallId': primaryCallId,
          'secondaryCallId': secondaryCallId,
          'joiningUserUid': joiningUid,
        },
      );
    } catch (e) {
      debugPrint('[MERGE_CALLS] error broadcasting call_merging: $e');
    }
  }

  void _broadcastMergeCommitted({
    required String secondaryCallId,
    required String primaryCallId,
    required String mergeOpId,
  }) {
    final client = VorynBackend.client;
    if (client == null) return;
    try {
      final secChannel = client.channel('call_room_$secondaryCallId');
      secChannel.sendBroadcastMessage(
        event: 'merge_committed',
        payload: {
          'mergeOperationId': mergeOpId,
          'conferenceCallId': primaryCallId,
        },
      );
    } catch (_) {}
  }

  void _broadcastMergeCancelled({
    required String secondaryCallId,
    required String mergeOpId,
  }) {
    final client = VorynBackend.client;
    if (client == null) return;
    try {
      final secChannel = client.channel('call_room_$secondaryCallId');
      secChannel.sendBroadcastMessage(
        event: 'merge_cancelled',
        payload: {
          'mergeOperationId': mergeOpId,
        },
      );
    } catch (_) {}
  }

  @visibleForTesting
  void setTestCalls({String? activeCallId, String? heldCallId}) {
    _activeCallId = activeCallId;
    _heldCallId = heldCallId;
    notifyListeners();
  }

  @visibleForTesting
  void resetMergeState() {
    _cancelMergeTimeout();
    _unsubscribeMergeEvents();
    _provisionalSession = null;
    _mergeState = const MergeOperationState(status: MergeStatus.idle);
    _isTransitionInFlight = false;
    mergeErrorNotifier.value = null;
  }
}
