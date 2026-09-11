import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';

class VorynDiscoveryResult {
  const VorynDiscoveryResult({
    required this.uid,
    required this.displayName,
    required this.vorynId,
    this.phone,
    this.presence,
  });

  final String uid;
  final String displayName;
  final String vorynId;
  final String? phone;
  final String? presence;

  factory VorynDiscoveryResult.fromMap(Map<String, dynamic> map) {
    return VorynDiscoveryResult(
      uid: map['uid'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      vorynId: map['voryn_id'] as String? ?? '',
      phone: map['phone'] as String?,
      presence: map['presence'] as String?,
    );
  }
}

class VorynDiscoveryService {
  const VorynDiscoveryService();

  SupabaseClient? get _client => VorynBackend.client;

  Future<VorynDiscoveryResult?> findByVorynId(String value) async {
    final normalized = _normalizeVorynId(value);
    if (normalized == null) return null;
    final row = await _client?.rpc(
      'find_user_by_voryn_id',
      params: {'candidate': normalized},
    );
    return _resultFromRpc(row);
  }

  Future<VorynDiscoveryResult?> findByPhone(String value) async {
    final normalized = _normalizePhone(value);
    if (normalized.isEmpty) return null;
    final row = await _client?.rpc(
      'find_user_by_phone',
      params: {'normalized_phone': normalized},
    );
    return _resultFromRpc(row);
  }

  VorynDiscoveryResult? _resultFromRpc(dynamic value) {
    if (value is List && value.isNotEmpty && value.first is Map) {
      return VorynDiscoveryResult.fromMap(
        Map<String, dynamic>.from(value.first as Map),
      );
    }
    if (value is Map) {
      return VorynDiscoveryResult.fromMap(Map<String, dynamic>.from(value));
    }
    return null;
  }

  String? _normalizeVorynId(String value) {
    final normalized = value.trim().replaceFirst('@', '').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(normalized)) return null;
    return normalized;
  }

  String _normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9+]'), '');
}
