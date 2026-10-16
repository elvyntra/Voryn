import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import '../../core/presence/voryn_presence_service.dart';
import 'models/video_upgrade_models.dart';
import 'voryn_active_call_presentation_service.dart';
import 'voryn_call_latency_tracker.dart';
import 'voryn_call_runtime_coordinator.dart';

class VorynCallRequest {
  const VorynCallRequest({this.id, this.error});
  final String? id;
  final String? error;
  bool get isSuccess => id != null && error == null;
}

class VorynPendingIncomingCall {
  const VorynPendingIncomingCall({
    required this.id,
    required this.callerUid,
    required this.displayName,
    required this.vorynId,
    required this.callType,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String callerUid;
  final String displayName;
  final String vorynId;
  final String callType;
  final String status;
  final DateTime createdAt;

  factory VorynPendingIncomingCall.fromMap(Map<String, dynamic> map) {
    return VorynPendingIncomingCall(
      id: map['id']?.toString() ?? '',
      callerUid: map['other_uid']?.toString() ?? '',
      displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
          ? map['display_name'] as String
          : map['voryn_id'] as String? ?? 'Voryn user',
      vorynId: map['voryn_id'] as String? ?? '',
      callType: map['call_type'] as String? ?? 'audio',
      status: map['status'] as String? ?? 'calling',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class VorynCallService {
  const VorynCallService();

  Future<VorynCallRequest> start({
    required String vorynId,
    required bool video,
  }) async {
    final client = VorynBackend.client;
    if (client == null || client.auth.currentUser == null) {
      return const VorynCallRequest(error: 'Sign in before starting a call.');
    }
    try {
      final id = await client.rpc(
        'start_direct_call',
        params: {
          'candidate': vorynId,
          'requested_type': video ? 'video' : 'audio',
        },
      );
      final callId = id as String?;
      if (callId != null) {
        final tracker = VorynCallLatencyTracker.start(callId: callId);
        unawaited(tracker.stage('backend_start_direct_call'));
        // Non-blocking FCM dispatch with durable bounded retry for transient errors.
        unawaited(
          dispatchCallNotificationWithRetry(
            callId: callId,
            tracker: tracker,
          ),
        );
      }
      return VorynCallRequest(id: callId);
    } on PostgrestException catch (error) {
      final msg = error.message.toLowerCase();
      if (msg.contains('dnd_enabled')) {
        return const VorynCallRequest(
          error: 'This user has Do Not Disturb turned on.',
        );
      } else if (msg.contains('contacts_only')) {
        return const VorynCallRequest(
          error: 'This user only accepts calls from saved contacts.',
        );
      } else if (msg.contains('calls_disabled')) {
        return const VorynCallRequest(
          error: 'This user is not accepting calls right now.',
        );
      } else if (msg.contains('calling_unavailable')) {
        return const VorynCallRequest(
          error: 'Calling is unavailable for this user.',
        );
      } else if (msg.contains('already_on_call')) {
        return const VorynCallRequest(
          error: "You're already on a call.",
        );
      } else if (msg.contains('user_busy')) {
        return const VorynCallRequest(
          error: 'This user is currently busy on another call.',
        );
      } else if (msg.contains('user not found')) {
        return const VorynCallRequest(error: 'User not found.');
      }
      return const VorynCallRequest(error: 'Could not start this call.');
    } catch (_) {
      return const VorynCallRequest(error: 'Could not start this call.');
    }
  }

  static const String _activeCallKey = 'voryn.active_call_id';

  Future<void> markActiveCall(String callId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeCallKey, callId);
      await LockScreenService.clearPendingIncomingCall(callId);
    } catch (_) {}
  }

  Future<void> clearActiveCall(String callId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getString(_activeCallKey);
      if (current == callId) {
        await prefs.remove(_activeCallKey);
      }
      await LockScreenService.clearPendingIncomingCall(callId);
    } catch (_) {}
  }

  /// Retrieves a pending ringing call from Supabase RPC or native SharedPreferences.
  Future<VorynPendingIncomingCall?> getPendingIncomingCall({
    String? callId,
  }) async {
    final activeSnapshot =
        VorynActiveCallPresentationService.instance.currentSnapshot;
    final currentActiveId = activeSnapshot?.callId;

    final client = VorynBackend.client;
    if (client != null && client.auth.currentUser != null) {
      try {
        final dynamic res = await client.rpc('get_my_pending_incoming_call');
        if (res is List && res.isNotEmpty && res.first is Map) {
          final row = Map<String, dynamic>.from(res.first as Map);
          final rowId = row['id']?.toString() ?? '';
          if (rowId.isNotEmpty) {
            if (activeSnapshot != null &&
                activeSnapshot.isActive &&
                (currentActiveId == rowId || currentActiveId != null)) {
              debugPrint(
                '[CALL_RECOVERY] RPC rowId=$rowId suppressed because active call present ($currentActiveId)',
              );
              return null;
            }
            if (VorynCallRuntimeCoordinator.isCallActive(rowId)) {
              debugPrint(
                '[CALL_RECOVERY] RPC rowId=$rowId suppressed because call is already active in coordinator',
              );
              return null;
            }
            if (callId == null || rowId == callId) {
              return VorynPendingIncomingCall.fromMap(row);
            }
          }
        }
      } catch (e) {
        debugPrint(
          '[CALL_RECOVERY] RPC get_my_pending_incoming_call error: $e',
        );
      }
    }

    // Native SharedPreferences fallback (strictly RINGING only)
    try {
      final nativePending = await LockScreenService.getPendingIncomingCall();
      if (nativePending != null) {
        final nCallId = nativePending['callId']?.toString();
        final nState = nativePending['state']?.toString();
        if (nCallId != null && nCallId.isNotEmpty && nState == 'RINGING') {
          if (activeSnapshot != null &&
              activeSnapshot.isActive &&
              (currentActiveId == nCallId || currentActiveId != null)) {
            return null;
          }
          if (VorynCallRuntimeCoordinator.isCallActive(nCallId)) {
            return null;
          }
          if (callId == null || nCallId == callId) {
            final receivedAt =
                int.tryParse(nativePending['receivedAt']?.toString() ?? '') ??
                0;
            final now = DateTime.now().millisecondsSinceEpoch;
            // Only consider valid if received within last 60 seconds
            if (receivedAt == 0 || (now - receivedAt) < 60000) {
              return VorynPendingIncomingCall(
                id: nCallId,
                callerUid: '',
                displayName:
                    nativePending['callerName']?.toString() ?? 'Voryn user',
                vorynId: '',
                callType: nativePending['callType']?.toString() ?? 'audio',
                status: 'ringing',
                createdAt: receivedAt > 0
                    ? DateTime.fromMillisecondsSinceEpoch(receivedAt)
                    : DateTime.now(),
              );
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Reconciles an active call if the process was killed during the call.
  Future<void> reconcileStaleActiveCallOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final staleCallId = prefs.getString(_activeCallKey);
      if (staleCallId == null || staleCallId.isEmpty) return;

      await LockScreenService.cancelNativeIncomingCall(
        staleCallId,
        reason: 'stale',
      );

      final call = await getCall(staleCallId);
      final status = call?['status'] as String?;
      if (status != null &&
          ['calling', 'ringing', 'connected'].contains(status)) {
        debugPrint(
          '[STARTUP] Reconciling stale active call $staleCallId -> ending on backend',
        );
        await end(staleCallId);
      }
      await prefs.remove(_activeCallKey);
    } catch (e) {
      debugPrint('[STARTUP] Error reconciling stale call: $e');
    }
  }

  Future<void> end(String callId) async {
    await clearActiveCall(callId);
    await LockScreenService.cancelNativeIncomingCall(
      callId,
      reason: 'remote_terminal',
    );
    VorynPresenceService.onCallEnded();
    final client = VorynBackend.client;
    if (client == null) return;
    try {
      await client.rpc(
        'update_call_state',
        params: {'call_uuid': callId, 'new_status': 'completed'},
      );
      final user = client.auth.currentUser?.id ?? 'local';
      debugPrint('[CALL $callId] backend status -> completed by $user');
    } catch (e) {
      debugPrint('[CALL $callId] error updating call status: $e');
    }

    try {
      final channel = client.channel('call_room_$callId');
      await channel.sendBroadcastMessage(
        event: 'call_ended',
        payload: {'callId': callId, 'status': 'completed'},
      );
    } catch (_) {}

    unawaited(
      dispatchCallNotificationWithRetry(
        callId: callId,
        extraBody: {'action': 'end'},
        maxAttempts: 2,
      ),
    );
  }

  Future<void> cancel(String callId) async {
    await clearActiveCall(callId);
    await LockScreenService.cancelNativeIncomingCall(
      callId,
      reason: 'remote_terminal',
    );
    VorynPresenceService.onCallEnded();
    final client = VorynBackend.client;
    if (client == null) return;
    try {
      await client.rpc(
        'update_call_state',
        params: {'call_uuid': callId, 'new_status': 'cancelled'},
      );
      debugPrint('[CALL $callId] backend status -> cancelled by caller');
    } catch (_) {}

    try {
      final channel = client.channel('call_room_$callId');
      await channel.sendBroadcastMessage(
        event: 'call_ended',
        payload: {'callId': callId, 'status': 'cancelled'},
      );
    } catch (_) {}

    unawaited(
      dispatchCallNotificationWithRetry(
        callId: callId,
        extraBody: {'action': 'cancel'},
        maxAttempts: 2,
      ),
    );
  }

  Future<void> setConnected(String callId) async {
    await markActiveCall(callId);
    VorynPresenceService.onCallConnected();
    final client = VorynBackend.client;
    if (client == null) return;
    await client.rpc(
      'update_call_state',
      params: {'call_uuid': callId, 'new_status': 'connected'},
    );
  }

  Future<Map<String, dynamic>?> getCall(String callId) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final res = await client
          .from('calls')
          .select('id, status, call_type, initiated_by, held_by, merged_into_call_id')
          .eq('id', callId)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<int> getParticipantCount(String callId) async {
    final client = VorynBackend.client;
    if (client == null) return 2;
    try {
      final res = await client
          .from('call_participants')
          .select('user_uid')
          .eq('call_id', callId);
      return res.length;
    } catch (_) {
      return 2;
    }
  }

  Future<void> decline(String callId) async {
    await clearActiveCall(callId);
    await LockScreenService.cancelNativeIncomingCall(callId, reason: 'decline');
    VorynPresenceService.onCallEnded();
    final client = VorynBackend.client;
    if (client == null) return;
    try {
      await client.rpc(
        'update_call_state',
        params: {'call_uuid': callId, 'new_status': 'declined'},
      );
      debugPrint('[CALL $callId] backend status -> declined by receiver');
    } catch (_) {}

    try {
      final channel = client.channel('call_room_$callId');
      await channel.sendBroadcastMessage(
        event: 'call_ended',
        payload: {'callId': callId, 'status': 'declined'},
      );
    } catch (_) {}

    unawaited(
      dispatchCallNotificationWithRetry(
        callId: callId,
        extraBody: {'action': 'cancel'},
        maxAttempts: 2,
      ),
    );
  }

  Future<Map<String, dynamic>?> holdAndAccept({
    required String activeCallId,
    required String waitingCallId,
  }) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final dynamic res = await client.rpc(
        'hold_and_accept_waiting_call',
        params: {
          'p_active_call_id': activeCallId,
          'p_waiting_call_id': waitingCallId,
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      debugPrint('[MULTI_CALL] hold_and_accept RPC error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> switchHeldCall({
    required String activeCallId,
    required String heldCallId,
  }) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final dynamic res = await client.rpc(
        'switch_held_call',
        params: {
          'p_current_active_call_id': activeCallId,
          'p_current_held_call_id': heldCallId,
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      debugPrint('[MULTI_CALL] switch_held_call RPC error: $e');
      return null;
    }
  }

  /// Initiates two-phase merge preparation via prepare_call_merge RPC.
  Future<Map<String, dynamic>?> prepareCallMerge({
    required String primaryCallId,
    required String secondaryCallId,
  }) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final dynamic res = await client.rpc(
        'prepare_call_merge',
        params: {
          'p_primary_call_id': primaryCallId,
          'p_secondary_call_id': secondaryCallId,
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      debugPrint('[MERGE_CALLS] prepare_call_merge RPC error: $e');
      return null;
    }
  }

  /// Finalizes merge admission via canonical finalize-call-merge Edge Function.
  Future<Map<String, dynamic>?> finalizeCallMerge({
    required String mergeOperationId,
  }) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final response = await client.functions.invoke(
        'finalize-call-merge',
        body: {'mergeOperationId': mergeOperationId},
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      debugPrint('[MERGE_CALLS] finalize-call-merge error: $e');
      return null;
    }
  }

  /// Cancels an in-flight merge operation via canonical cancel-call-merge Edge Function.
  Future<Map<String, dynamic>?> cancelCallMerge({
    required String mergeOperationId,
    String reason = 'client_aborted',
  }) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final response = await client.functions.invoke(
        'cancel-call-merge',
        body: {
          'mergeOperationId': mergeOperationId,
          'reason': reason,
        },
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      debugPrint('[MERGE_CALLS] cancel-call-merge error: $e');
      return null;
    }
  }

  /// Fetches authoritative merge operation record by ID.
  Future<Map<String, dynamic>?> getCallMergeOperation(
    String mergeOperationId,
  ) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final data = await client
          .from('call_merge_operations')
          .select()
          .eq('id', mergeOperationId)
          .maybeSingle();
      if (data != null) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      debugPrint('[MERGE_CALLS] getCallMergeOperation error: $e');
      return null;
    }
  }

  /// Fetches an active prepared/joining merge operation where current user is joining_user_uid.
  Future<Map<String, dynamic>?> getActiveMergeOperationForJoining({
    required String secondaryCallId,
  }) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    final user = client.auth.currentUser;
    if (user == null) return null;
    try {
      final Map<String, dynamic>? data = await client
          .from('call_merge_operations')
          .select()
          .eq('secondary_call_id', secondaryCallId)
          .eq('joining_user_uid', user.id)
          .inFilter('status', ['prepared', 'joining'])
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data != null) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      debugPrint('[MERGE_CALLS] getActiveMergeOperationForJoining error: $e');
      return null;
    }
  }

  Future<bool> setCallHoldState(String callId, bool isHeld) async {
    final client = VorynBackend.client;
    if (client == null) return false;
    try {
      final dynamic res = await client.rpc(
        'set_call_hold_state',
        params: {'call_uuid': callId, 'is_held': isHeld},
      );
      final user = client.auth.currentUser?.id ?? 'local';
      try {
        final channel = client.channel('call_room_$callId');
        await channel.sendBroadcastMessage(
          event: isHeld ? 'call_held' : 'call_resumed',
          payload: {'callId': callId, 'isHeld': isHeld, 'heldBy': user},
        );
      } catch (_) {}
      return res == true;
    } catch (e) {
      debugPrint('[MULTI_CALL] set_call_hold_state error: $e');
      return false;
    }
  }

  RealtimeChannel? subscribeToCallState(
    String callId,
    void Function(String status) onTerminal, {
    void Function(String status, String? heldBy)? onStatusChanged,
    void Function(VideoUpgradeRequest request)? onVideoUpgradeRequested,
    void Function(String requestId, VideoUpgradeStatus status)? onVideoUpgradeStatusChanged,
  }) {
    final client = VorynBackend.client;
    if (client == null) return null;

    final channel = client.channel('call_room_$callId');
    bool terminalTriggered = false;

    void handleTerminal(String status) {
      if (terminalTriggered) return;
      terminalTriggered = true;
      onTerminal(status);
    }

    // 1. Peer broadcast termination as low-latency hint
    channel.onBroadcast(
      event: 'call_ended',
      callback: (payload) {
        debugPrint(
          '[CALL $callId] low-latency terminal hint received via broadcast',
        );
        handleTerminal('completed');
      },
    );

    // 2. Peer broadcast hold state as low-latency hint
    channel.onBroadcast(
      event: 'call_held',
      callback: (payload) {
        final heldBy = payload['heldBy']?.toString();
        debugPrint(
          '[CALL $callId] low-latency call_held hint received (heldBy=$heldBy)',
        );
        onStatusChanged?.call('on_hold', heldBy);
      },
    );

    channel.onBroadcast(
      event: 'call_resumed',
      callback: (payload) {
        debugPrint(
          '[CALL $callId] low-latency call_resumed hint received',
        );
        onStatusChanged?.call('connected', null);
      },
    );

    // 3. Audio-to-Video Upgrade peer broadcast events
    channel.onBroadcast(
      event: 'video_upgrade_requested',
      callback: (payload) {
        debugPrint('[CALL $callId] received video_upgrade_requested broadcast');
        final req = VideoUpgradeRequest.fromJson(payload);
        onVideoUpgradeRequested?.call(req);
      },
    );

    channel.onBroadcast(
      event: 'video_upgrade_accepted',
      callback: (payload) {
        final reqId = payload['requestId']?.toString() ?? '';
        debugPrint('[CALL $callId] received video_upgrade_accepted broadcast (reqId=$reqId)');
        onVideoUpgradeStatusChanged?.call(reqId, VideoUpgradeStatus.accepted);
      },
    );

    channel.onBroadcast(
      event: 'video_upgrade_declined',
      callback: (payload) {
        final reqId = payload['requestId']?.toString() ?? '';
        debugPrint('[CALL $callId] received video_upgrade_declined broadcast (reqId=$reqId)');
        onVideoUpgradeStatusChanged?.call(reqId, VideoUpgradeStatus.declined);
      },
    );

    channel.onBroadcast(
      event: 'video_upgrade_cancelled',
      callback: (payload) {
        final reqId = payload['requestId']?.toString() ?? '';
        debugPrint('[CALL $callId] received video_upgrade_cancelled broadcast (reqId=$reqId)');
        onVideoUpgradeStatusChanged?.call(reqId, VideoUpgradeStatus.cancelled);
      },
    );

    // 4. Authoritative Postgres CDC updates on calls table
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'calls',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: callId,
      ),
      callback: (payload) {
        final status = payload.newRecord['status'] as String?;
        final heldBy = payload.newRecord['held_by'] as String?;
        final callType = payload.newRecord['call_type'] as String?;
        if (status == 'completed' ||
            status == 'cancelled' ||
            status == 'declined' ||
            status == 'missed' ||
            status == 'failed') {
          debugPrint(
            '[CALL $callId] authoritative remote terminal event via postgres CDC: status=$status',
          );
          handleTerminal(status ?? 'completed');
        } else if (status != null) {
          debugPrint(
            '[CALL $callId] authoritative status change via postgres CDC: status=$status heldBy=$heldBy callType=$callType',
          );
          onStatusChanged?.call(status, heldBy);
          if (callType == 'video') {
            onVideoUpgradeStatusChanged?.call('', VideoUpgradeStatus.accepted);
          }
        }
      },
    );

    // 5. Authoritative Postgres CDC on call_video_upgrade_requests
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'call_video_upgrade_requests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'call_id',
        value: callId,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        if (record.isNotEmpty) {
          final req = VideoUpgradeRequest.fromJson(record);
          debugPrint(
            '[CALL $callId] CDC call_video_upgrade_requests event=${payload.eventType} status=${req.status}',
          );
          if (payload.eventType == PostgresChangeEvent.insert && req.status == VideoUpgradeStatus.pending) {
            onVideoUpgradeRequested?.call(req);
          } else {
            onVideoUpgradeStatusChanged?.call(req.id, req.status);
          }
        }
      },
    );

    channel.subscribe();
    return channel;
  }

  /// Initiates an in-call audio-to-video upgrade request with receiver approval.
  Future<VideoUpgradeResult> requestVideoUpgrade(String callId) async {
    final client = VorynBackend.client;
    if (client == null || client.auth.currentUser == null) {
      return const VideoUpgradeResult(
        isSuccess: false,
        errorMessage: 'Unauthenticated',
      );
    }
    try {
      final dynamic res = await client.rpc(
        'request_video_upgrade',
        params: {'p_call_id': callId},
      );
      if (res is Map) {
        final ok = res['ok'] == true;
        if (!ok) {
          return VideoUpgradeResult(
            isSuccess: false,
            errorMessage: res['error']?.toString() ?? 'Failed to request video upgrade',
          );
        }
        final statusStr = res['status']?.toString();
        final coalesced = res['coalesced'] == true;
        final requestId = res['request_id']?.toString();
        final targetUserUid = res['target_user_uid']?.toString();
        final expiresAtStr = res['expires_at']?.toString();
        final expiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr)?.toLocal() : null;

        final status = statusStr == 'accepted'
            ? VideoUpgradeStatus.accepted
            : VideoUpgradeStatus.pending;

        // Broadcast to call room
        try {
          final channel = client.channel('call_room_$callId');
          if (status == VideoUpgradeStatus.accepted) {
            await channel.sendBroadcastMessage(
              event: 'video_upgrade_accepted',
              payload: {'requestId': requestId, 'callId': callId},
            );
          } else {
            await channel.sendBroadcastMessage(
              event: 'video_upgrade_requested',
              payload: {
                'id': requestId,
                'callId': callId,
                'requestedBy': client.auth.currentUser!.id,
                'targetUserUid': targetUserUid,
                'status': 'pending',
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'expiresAt': (expiresAt ?? DateTime.now().add(const Duration(seconds: 30))).toUtc().toIso8601String(),
              },
            );
          }
        } catch (_) {}

        return VideoUpgradeResult(
          isSuccess: true,
          status: status,
          requestId: requestId,
          targetUserUid: targetUserUid,
          expiresAt: expiresAt,
          coalesced: coalesced,
        );
      }
      return const VideoUpgradeResult(
        isSuccess: false,
        errorMessage: 'Invalid server response',
      );
    } catch (e) {
      debugPrint('[CALL $callId] request_video_upgrade RPC error: $e');
      return VideoUpgradeResult(
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Designated recipient responds to an in-call video upgrade request.
  Future<bool> respondVideoUpgrade(
    String requestId,
    bool accept, {
    required String callId,
  }) async {
    final client = VorynBackend.client;
    if (client == null) return false;
    try {
      final dynamic res = await client.rpc(
        'respond_video_upgrade',
        params: {
          'p_request_id': requestId,
          'p_accept': accept,
        },
      );
      if (res is Map && res['ok'] == true) {
        try {
          final channel = client.channel('call_room_$callId');
          await channel.sendBroadcastMessage(
            event: accept ? 'video_upgrade_accepted' : 'video_upgrade_declined',
            payload: {'requestId': requestId, 'callId': callId},
          );
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[VIDEO_UPGRADE] respond_video_upgrade error: $e');
      return false;
    }
  }

  /// Requester cancels an in-flight video upgrade request.
  Future<bool> cancelVideoUpgrade(
    String requestId, {
    required String callId,
  }) async {
    final client = VorynBackend.client;
    if (client == null) return false;
    try {
      final dynamic res = await client.rpc(
        'cancel_video_upgrade',
        params: {'p_request_id': requestId},
      );
      if (res is Map && res['ok'] == true) {
        try {
          final channel = client.channel('call_room_$callId');
          await channel.sendBroadcastMessage(
            event: 'video_upgrade_cancelled',
            payload: {'requestId': requestId, 'callId': callId},
          );
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[VIDEO_UPGRADE] cancel_video_upgrade error: $e');
      return false;
    }
  }

  /// Fetches the currently pending unexpired upgrade request for a call if any.
  Future<VideoUpgradeRequest?> getActiveVideoUpgradeRequest(String callId) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final dynamic res = await client.rpc(
        'get_active_video_upgrade_request',
        params: {'p_call_id': callId},
      );
      if (res is Map) {
        return VideoUpgradeRequest.fromJson(Map<String, dynamic>.from(res));
      }
      return null;
    } catch (e) {
      debugPrint('[VIDEO_UPGRADE] get_active_video_upgrade_request error: $e');
      return null;
    }
  }

  /// Fetches an upgrade request by its specific request ID (regardless of pending/accepted status).
  Future<VideoUpgradeRequest?> getVideoUpgradeRequestById(String requestId) async {
    final client = VorynBackend.client;
    if (client == null) return null;
    try {
      final res = await client
          .from('call_video_upgrade_requests')
          .select()
          .eq('id', requestId)
          .maybeSingle();
      if (res != null) {
        return VideoUpgradeRequest.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('[VIDEO_UPGRADE] getVideoUpgradeRequestById error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> addParticipant({
    required String callId,
    required String candidate,
    String? targetUserId,
  }) async {
    final client = VorynBackend.client;
    if (client == null || client.auth.currentUser == null) return null;

    debugPrint('[CALL $callId] add participant opened');
    debugPrint('[CALL $callId] invite target=$candidate');

    String? resolvedUid = targetUserId;

    // Check if candidate string is already a UUID
    final isCandidateUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(candidate.trim());

    if (resolvedUid == null && isCandidateUuid) {
      resolvedUid = candidate.trim();
    }

    if (resolvedUid == null) {
      final cleanVorynId = candidate.trim().replaceFirst('@', '');
      try {
        final profile = await client
            .from('profiles')
            .select('uid')
            .ilike('voryn_id', cleanVorynId)
            .maybeSingle();
        if (profile != null) {
          resolvedUid = profile['uid'] as String?;
        }
      } catch (e) {
        debugPrint(
          '[CALL $callId] failed to resolve vorynId $cleanVorynId: $e',
        );
      }
    }

    if (resolvedUid == null) {
      debugPrint(
        '[CALL $callId] candidate $candidate could not be resolved to user UUID',
      );
      throw Exception("User '$candidate' not found.");
    }

    debugPrint('[CALL $callId] add participant targetUid=$resolvedUid');
    debugPrint('[CALL $callId] RPC add_call_participant start');

    try {
      final result = await client.rpc(
        'add_call_participant',
        params: {'call_uuid': callId, 'target_user_id': resolvedUid},
      );

      debugPrint('[CALL $callId] RPC success participantId=$resolvedUid');

      // Dispatch invitation notification to the newly added participant
      unawaited(
        dispatchCallNotificationWithRetry(
          callId: callId,
          extraBody: {'recipientUid': resolvedUid},
        ),
      );

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': true, 'user_uid': resolvedUid, 'call_id': callId};
    } catch (e) {
      debugPrint('[CALL $callId] add participant failed: $e');
      throw Exception("Couldn't invite this person. Try again.");
    }
  }

  /// Dispatches call push notification with durable bounded retry for transient errors.
  /// Stops immediately on permanent auth/availability errors (400, 401, 403) or if
  /// backend call state is no longer authoritative ('calling').
  @visibleForTesting
  Future<bool> dispatchCallNotificationWithRetry({
    required String callId,
    Map<String, dynamic>? extraBody,
    VorynCallLatencyTracker? tracker,
    int maxAttempts = 3,
    Future<FunctionResponse> Function(String functionName, {Map<String, dynamic>? body})? invokeOverride,
    bool Function()? isAuthenticatedOverride,
    Future<Map<String, dynamic>?> Function(String callId)? getCallOverride,
    Duration? retryDelayOverride,
  }) async {
    final client = VorynBackend.client;
    final isAuth = isAuthenticatedOverride != null
        ? isAuthenticatedOverride()
        : (client != null && client.auth.currentUser != null);
    if (!isAuth) return false;

    final body = <String, dynamic>{'callId': callId, ...?extraBody};
    final isIncoming = body['action'] == null;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1 && isIncoming) {
        final call = getCallOverride != null
            ? await getCallOverride(callId)
            : await getCall(callId);
        final status = call?['status'] as String?;
        if (status != 'calling') {
          debugPrint(
            '[FCM_CALL] retry aborted: backend call state is $status (callId=$callId)',
          );
          return false;
        }
      }

      try {
        final res = invokeOverride != null
            ? await invokeOverride('send-call-notification', body: body)
            : await client!.functions.invoke(
                'send-call-notification',
                body: body,
              );
        if (res.status == 200 || res.status == 201) {
          tracker?.stage('recipient_signalling_fcm');
          debugPrint(
            '[FCM_CALL] delivered successfully attempt=$attempt callId=$callId',
          );
          return true;
        }
        if (res.status == 400 || res.status == 401 || res.status == 403) {
          debugPrint(
            '[FCM_CALL] permanent status=${res.status} callId=$callId, no retry',
          );
          return false;
        }
      } on FunctionException catch (fe) {
        if (fe.status == 400 || fe.status == 401 || fe.status == 403) {
          debugPrint(
            '[FCM_CALL] permanent error status=${fe.status} callId=$callId: ${fe.details}',
          );
          return false;
        }
        debugPrint(
          '[FCM_CALL] transient function error attempt=$attempt status=${fe.status} callId=$callId: ${fe.details}',
        );
      } catch (e) {
        debugPrint(
          '[FCM_CALL] transient network error attempt=$attempt callId=$callId: $e',
        );
      }

      if (attempt < maxAttempts) {
        await Future.delayed(
          retryDelayOverride ?? Duration(milliseconds: 500 * attempt),
        );
      }
    }
    return false;
  }
}
