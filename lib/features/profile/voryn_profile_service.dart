import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import 'voryn_profile.dart';

class VorynPrivacySettings {
  const VorynPrivacySettings({
    required this.dndEnabled,
    required this.whoCanCall,
    required this.showOnlineStatus,
  });

  final bool dndEnabled;
  final String whoCanCall; // 'everyone', 'saved_contacts', 'nobody'
  final bool showOnlineStatus;

  factory VorynPrivacySettings.fromMap(Map<String, dynamic> map) {
    return VorynPrivacySettings(
      dndEnabled: (map['dnd_enabled'] as bool?) ?? false,
      whoCanCall: (map['who_can_call'] as String?) ?? 'everyone',
      showOnlineStatus: (map['show_online_status'] as bool?) ?? true,
    );
  }

  VorynPrivacySettings copyWith({
    bool? dndEnabled,
    String? whoCanCall,
    bool? showOnlineStatus,
  }) {
    return VorynPrivacySettings(
      dndEnabled: dndEnabled ?? this.dndEnabled,
      whoCanCall: whoCanCall ?? this.whoCanCall,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
    );
  }
}

class VorynIdAvailability {
  const VorynIdAvailability({this.isAvailable, this.error});

  final bool? isAvailable;
  final String? error;
}

class VorynProfileService {
  const VorynProfileService();

  SupabaseClient? get _client => VorynBackend.client;

  User? get currentUser => _client?.auth.currentUser;

  Future<VorynProfile?> currentProfile() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    final row = await client
        .from('profiles')
        .select()
        .eq('uid', user.id)
        .maybeSingle();
    return row == null ? null : VorynProfile.fromMap(row);
  }

  Future<String?> uploadAvatar(Uint8List bytes) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    final path = '${user.id}/profile.jpg';
    await client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    final url = client.storage.from('avatars').getPublicUrl(path);
    await client
        .from('profiles')
        .update({'avatar_url': url})
        .eq('uid', user.id);
    return url;
  }

  Future<VorynProfile?> upsertProfile({
    required String fullName,
    String? phone,
    bool? phoneVerified,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    final row = await client
        .from('profiles')
        .upsert({
          'uid': user.id,
          'email': user.email,
          'full_name': fullName,
          'phone': ?phone,
          'phone_verified': ?phoneVerified,
        })
        .select()
        .single();
    return VorynProfile.fromMap(row);
  }

  Future<String?> savePhone({
    required String fullName,
    required String phone,
  }) async {
    try {
      final profile = await upsertProfile(
        fullName: fullName,
        phone: phone,
        phoneVerified: false,
      );
      return profile == null ? 'Sign in again before continuing.' : null;
    } on PostgrestException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not save your phone number. Please try again.';
    }
  }

  Future<VorynIdAvailability> checkVorynIdAvailability(String candidate) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return const VorynIdAvailability(
        error: 'Sign in again before choosing a Voryn ID.',
      );
    }
    final normalized = _normalizeVorynId(candidate);
    if (normalized == null) {
      return const VorynIdAvailability(isAvailable: false);
    }
    try {
      final result = await client.rpc(
        'is_voryn_id_available',
        params: {'candidate': normalized},
      );
      return VorynIdAvailability(isAvailable: result == true);
    } on PostgrestException catch (error) {
      return VorynIdAvailability(error: error.message);
    } catch (_) {
      return const VorynIdAvailability(
        error: 'Could not check this Voryn ID. Please try again.',
      );
    }
  }

  Future<String?> claimVorynId(String candidate) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return 'Sign in again before creating your Voryn ID.';
    }
    final normalized = _normalizeVorynId(candidate);
    if (normalized == null) return 'Enter a valid Voryn ID.';
    try {
      final claimed = await client.rpc(
        'claim_voryn_id',
        params: {'candidate': normalized},
      );
      if (claimed != true) return 'This Voryn ID was just taken.';
      await client.auth.updateUser(
        UserAttributes(
          data: {
            ...?user.userMetadata,
            'voryn_id': normalized,
            'onboarding_completed': true,
          },
        ),
      );
      return null;
    } on PostgrestException catch (error) {
      return error.message;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not create your Voryn ID. Please try again.';
    }
  }

  String? _normalizeVorynId(String value) {
    final normalized = value.trim().replaceFirst('@', '').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(normalized)) return null;
    return normalized;
  }

  Future<VorynPrivacySettings?> loadPrivacySettings() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    try {
      final res = await client.rpc('get_my_settings');
      if (res is List && res.isNotEmpty) {
        return VorynPrivacySettings.fromMap(
          Map<String, dynamic>.from(res.first as Map),
        );
      } else if (res is Map) {
        return VorynPrivacySettings.fromMap(Map<String, dynamic>.from(res));
      }
      return const VorynPrivacySettings(
        dndEnabled: false,
        whoCanCall: 'everyone',
        showOnlineStatus: true,
      );
    } catch (e) {
      debugPrint('[PROFILE] Failed to load privacy settings: $e');
      return null;
    }
  }

  Future<bool> updatePrivacySettings({
    bool? dndEnabled,
    String? whoCanCall,
    bool? showOnlineStatus,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return false;
    try {
      final res = await client.rpc(
        'update_my_privacy_settings',
        params: {
          'new_dnd': ?dndEnabled,
          'new_who_can_call': ?whoCanCall,
          'new_show_online': ?showOnlineStatus,
        },
      );
      return res == true;
    } catch (e) {
      debugPrint('[PROFILE] Failed to update privacy settings: $e');
      return false;
    }
  }
}
