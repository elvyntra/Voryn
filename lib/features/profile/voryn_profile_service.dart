import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import 'voryn_profile.dart';

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
}
