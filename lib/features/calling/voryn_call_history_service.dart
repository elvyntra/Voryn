import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/backend/voryn_backend.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../connect/mock_voryn_state.dart';

class VorynCallHistoryItem {
  const VorynCallHistoryItem({
    required this.id,
    required this.otherUid,
    required this.displayName,
    required this.vorynId,
    required this.callType,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.endedAt,
  });

  final String id;
  final String otherUid;
  final String displayName;
  final String vorynId;
  final String callType;
  final String direction;
  final String status;
  final DateTime createdAt;
  final DateTime? endedAt;

  factory VorynCallHistoryItem.fromMap(Map<String, dynamic> map) =>
      VorynCallHistoryItem(
        id: map['id'] as String,
        otherUid: map['other_uid'] as String,
        displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
            ? map['display_name'] as String
            : map['voryn_id'] as String? ?? 'Voryn User',
        vorynId: map['voryn_id'] as String? ?? '',
        callType: map['call_type'] as String? ?? 'audio',
        direction: map['direction'] as String? ?? 'outgoing',
        status: map['status'] as String? ?? 'completed',
        createdAt:
            DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        endedAt: DateTime.tryParse(map['ended_at'] as String? ?? '')?.toLocal(),
      );

  bool get isMissed =>
      status == 'missed' ||
      (direction == 'incoming' &&
          (status == 'declined' || status == 'cancelled' || status == 'failed'));

  String get group {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final itemDate = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (itemDate == today) return 'Today';
    if (itemDate == yesterday) return 'Yesterday';
    return 'Earlier';
  }

  String get initials {
    final parts = displayName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'VU';
    return parts.map((p) => p[0].toUpperCase()).join();
  }

  String get timeFormatted {
    final hour = createdAt.hour == 0
        ? 12
        : (createdAt.hour > 12 ? createdAt.hour - 12 : createdAt.hour);
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String? get durationFormatted {
    if (endedAt == null || status != 'completed') return null;
    final diff = endedAt!.difference(createdAt);
    if (diff.isNegative || diff.inSeconds == 0) return null;
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  VorynMockUser toMockUser() => VorynMockUser(
        backendUid: otherUid,
        customName: null,
        name: displayName,
        id: vorynId.startsWith('@') ? vorynId : (vorynId.isNotEmpty ? '@$vorynId' : '@user'),
        phone: '',
        email: '',
        presence: VorynPresenceStatus.online,
        initials: initials,
      );
}

class VorynCallHistoryService {
  const VorynCallHistoryService({this.clientOverride});

  final SupabaseClient? clientOverride;

  Future<List<VorynCallHistoryItem>> load() async {
    final client = clientOverride ?? VorynBackend.client;
    if (client == null || client.auth.currentUser == null) {
      return const [];
    }
    final dynamic rows = await client.rpc('list_my_recent_calls');
    if (rows is! List) return const [];
    return rows
        .map(
          (row) => VorynCallHistoryItem.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  Future<VorynCallHistoryItem?> loadIncomingActiveCall({String? callId}) async {
    final calls = await load();
    for (final call in calls) {
      if ((callId == null || call.id == callId) &&
          call.direction == 'incoming' &&
          (call.status == 'calling' || call.status == 'ringing')) {
        return call;
      }
    }
    if (callId != null) {
      for (final call in calls) {
        if (call.direction == 'incoming' &&
            (call.status == 'calling' || call.status == 'ringing')) {
          return call;
        }
      }
    }
    return null;
  }

  Future<bool> deleteCall(String callId) async {
    final client = clientOverride ?? VorynBackend.client;
    if (client == null || client.auth.currentUser == null) return false;
    try {
      final dynamic res = await client.rpc(
        'delete_call_history_item',
        params: {'p_call_id': callId},
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearAll() async {
    final client = clientOverride ?? VorynBackend.client;
    if (client == null || client.auth.currentUser == null) return false;
    try {
      await client.rpc('clear_my_call_history');
      return true;
    } catch (_) {
      return false;
    }
  }
}
