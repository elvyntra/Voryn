import '../../core/backend/voryn_backend.dart';

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
            : map['voryn_id'] as String? ?? 'Voryn user',
        vorynId: map['voryn_id'] as String? ?? '',
        callType: map['call_type'] as String? ?? 'audio',
        direction: map['direction'] as String? ?? 'outgoing',
        status: map['status'] as String? ?? 'completed',
        createdAt:
            DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        endedAt: DateTime.tryParse(map['ended_at'] as String? ?? ''),
      );
}

class VorynCallHistoryService {
  const VorynCallHistoryService();

  Future<List<VorynCallHistoryItem>> load() async {
    final client = VorynBackend.client;
    if (client == null || client.auth.currentUser == null) {
      return const [];
    }
    final rows = await client.rpc('list_my_recent_calls');
    return (rows as List<dynamic>)
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
}
