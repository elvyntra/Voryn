import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';

class VorynCallRequest {
  const VorynCallRequest({this.id, this.error});
  final String? id;
  final String? error;
  bool get isSuccess => id != null && error == null;
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
        // Delivery is best-effort; an alert failure must not block the call.
        try {
          await client.functions.invoke(
            'send-call-notification',
            body: {'callId': callId},
          );
        } catch (_) {}
      }
      return VorynCallRequest(id: callId);
    } on PostgrestException catch (error) {
      return VorynCallRequest(error: error.message);
    } catch (_) {
      return const VorynCallRequest(error: 'Could not start this call.');
    }
  }

  static const String _activeCallKey = 'voryn.active_call_id';

  Future<void> markActiveCall(String callId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeCallKey, callId);
    } catch (_) {}
  }

  Future<void> clearActiveCall(String callId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getString(_activeCallKey);
      if (current == callId) {
        await prefs.remove(_activeCallKey);
      }
    } catch (_) {}
  }

  /// Reconciles an active call if the process was killed during the call.
  Future<void> reconcileStaleActiveCallOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final staleCallId = prefs.getString(_activeCallKey);
      if (staleCallId == null || staleCallId.isEmpty) return;

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
  }

  Future<void> cancel(String callId) async {
    await clearActiveCall(callId);
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
  }

  Future<void> setConnected(String callId) async {
    await markActiveCall(callId);
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
          .select('id, status, call_type, initiated_by')
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
  }

  RealtimeChannel? subscribeToCallState(
    String callId,
    void Function(String status) onTerminal,
  ) {
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

    // 2. Authoritative Postgres CDC updates on calls table
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
        if (status == 'completed' ||
            status == 'cancelled' ||
            status == 'declined' ||
            status == 'missed' ||
            status == 'failed') {
          debugPrint(
            '[CALL $callId] authoritative remote terminal event via postgres CDC: status=$status',
          );
          handleTerminal(status ?? 'completed');
        }
      },
    );

    channel.subscribe();
    return channel;
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
      try {
        await client.functions.invoke(
          'send-call-notification',
          body: {'callId': callId, 'recipientUid': resolvedUid},
        );
        debugPrint('[CALL $callId] invitation push sent');
      } catch (e) {
        debugPrint('[CALL $callId] invitation push delivery failed: $e');
      }

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': true, 'user_uid': resolvedUid, 'call_id': callId};
    } catch (e) {
      debugPrint('[CALL $callId] add participant failed: $e');
      throw Exception("Couldn't invite this person. Try again.");
    }
  }
}
