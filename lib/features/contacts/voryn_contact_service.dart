import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';

class VorynStoredContact {
  const VorynStoredContact({
    required this.uid,
    required this.name,
    required this.vorynId,
    required this.displayName,
    required this.favorite,
    required this.blocked,
    this.phone,
  });

  final String uid;
  final String name;
  final String vorynId;
  final String displayName;
  final String? phone;
  final bool favorite;
  final bool blocked;

  factory VorynStoredContact.fromMap(Map<String, dynamic> map) {
    return VorynStoredContact(
      uid: map['uid'] as String,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? map['name'] as String
          : map['voryn_id'] as String,
      vorynId: map['voryn_id'] as String,
      displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
          ? map['display_name'] as String
          : map['name'] as String? ?? map['voryn_id'] as String,
      phone: map['phone'] as String?,
      favorite: map['favorite'] == true,
      blocked: map['blocked'] == true,
    );
  }
}

class VorynContactSyncResult {
  const VorynContactSyncResult({
    required this.contacts,
    this.permissionDenied = false,
    this.error,
  });

  final List<VorynStoredContact> contacts;
  final bool permissionDenied;
  final String? error;

  bool get isSuccess => error == null && !permissionDenied;
}

class VorynContactService {
  const VorynContactService();

  SupabaseClient? get _client => VorynBackend.client;

  Future<List<VorynStoredContact>> loadContacts() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return const [];
    try {
      final rows = await client.rpc('list_my_contacts');
      return (rows as List<dynamic>)
          .map(
            (row) => VorynStoredContact.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveContact({
    required String vorynId,
    required String customName,
    required bool favorite,
  }) async {
    await _rpc('save_voryn_contact', {
      'candidate': vorynId,
      'saved_name': customName,
      'is_favorite': favorite,
    });
  }

  Future<void> setFavorite(String vorynId, bool favorite) async {
    await _rpc('set_voryn_contact_favorite', {
      'candidate': vorynId,
      'is_favorite': favorite,
    });
  }

  Future<void> removeContact(String vorynId) async {
    await _rpc('remove_voryn_contact', {'candidate': vorynId});
  }

  Future<void> setBlocked(String vorynId, bool blocked) async {
    await _rpc('set_voryn_user_blocked', {
      'candidate': vorynId,
      'is_blocked': blocked,
    });
  }

  Future<VorynContactSyncResult> syncDeviceContacts() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return const VorynContactSyncResult(
        contacts: [],
        error: 'Sign in before syncing contacts.',
      );
    }
    final permission = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (permission != PermissionStatus.granted) {
      return const VorynContactSyncResult(contacts: [], permissionDenied: true);
    }

    try {
      final deviceContacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      final phones = <String>[];
      final names = <String>[];
      final deviceIds = <String>[];
      final seen = <String>{};
      for (final contact in deviceContacts) {
        for (final phone in contact.phones) {
          final normalized = _normalizePhone(phone.number);
          if (normalized.length < 7 || !seen.add(normalized)) continue;
          phones.add(normalized);
          names.add(contact.displayName ?? '');
          deviceIds.add(contact.id ?? '');
        }
      }
      final rows = await client.rpc(
        'sync_phone_contacts',
        params: {
          'phone_numbers': phones,
          'device_names': names,
          'device_ids': deviceIds,
        },
      );
      final contacts = (rows as List<dynamic>)
          .map(
            (row) => VorynStoredContact.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      return VorynContactSyncResult(contacts: contacts);
    } on PostgrestException catch (error) {
      return VorynContactSyncResult(contacts: const [], error: error.message);
    } catch (_) {
      return const VorynContactSyncResult(
        contacts: [],
        error: 'Could not sync contacts. Please try again.',
      );
    }
  }

  Future<void> openContactSettings() =>
      FlutterContacts.permissions.openSettings();

  Future<void> _rpc(String function, Map<String, dynamic> params) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return;
    try {
      await client.rpc(function, params: params);
    } catch (_) {
      // Local state remains usable and will be reconciled on a later sync.
    }
  }

  String _normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
