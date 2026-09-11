import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/widgets/voryn_presence.dart';
import '../contacts/voryn_contact_service.dart';
import 'voryn_discovery_service.dart';

enum VorynCallType { audio, video }

enum VorynCallDirection { incoming, outgoing }

enum VorynCallStatus { completed, missed, declined, failed }

class VorynMockUser {
  const VorynMockUser({
    this.backendUid,
    required this.customName,
    required this.name,
    required this.id,
    required this.phone,
    required this.email,
    required this.presence,
    required this.initials,
  });

  final String? backendUid;
  final String? customName;
  final String name;
  final String id;
  final String phone;
  final String email;
  final VorynPresenceStatus presence;
  final String initials;

  String get displayName => mockContacts[id]?.customName ?? customName ?? name;
  bool get isSaved => mockContacts.containsKey(id) || customName != null;
  bool get isFavorite => mockContacts[id]?.isFavorite ?? false;

  factory VorynMockUser.fromDiscovery(VorynDiscoveryResult result) {
    final name = result.displayName.trim().isEmpty
        ? result.vorynId
        : result.displayName.trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return VorynMockUser(
      backendUid: result.uid,
      customName: null,
      name: name,
      id: result.vorynId.startsWith('@')
          ? result.vorynId
          : '@${result.vorynId}',
      phone: result.phone ?? '',
      email: '',
      presence: _presenceFromValue(result.presence),
      initials: initials.isEmpty ? '?' : initials,
    );
  }
}

VorynPresenceStatus _presenceFromValue(String? value) => switch (value) {
  'online' => VorynPresenceStatus.online,
  'busy' => VorynPresenceStatus.busy,
  _ => VorynPresenceStatus.offline,
};

class VorynMockContact {
  const VorynMockContact({
    required this.userId,
    required this.customName,
    this.isFavorite = false,
  });

  final String userId;
  final String customName;
  final bool isFavorite;

  VorynMockContact copyWith({String? customName, bool? isFavorite}) {
    return VorynMockContact(
      userId: userId,
      customName: customName ?? this.customName,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class VorynMockCall {
  const VorynMockCall({
    required this.id,
    required this.userId,
    required this.type,
    required this.direction,
    required this.status,
    required this.group,
    required this.time,
    this.duration,
  });

  final String id;
  final String userId;
  final VorynCallType type;
  final VorynCallDirection direction;
  final VorynCallStatus status;
  final String group;
  final String time;
  final String? duration;
}

final mockContacts = <String, VorynMockContact>{};

final mockBlockedIds = <String>{};
final mockRemovedHistoryUserIds = <String>{};

final mockVorynUsers = <VorynMockUser>[];

final mockRecentCalls = <VorynMockCall>[
  const VorynMockCall(
    id: 'today-rahul-audio',
    userId: '@rahul',
    type: VorynCallType.audio,
    direction: VorynCallDirection.outgoing,
    status: VorynCallStatus.completed,
    group: 'Today',
    time: '10:42 AM',
    duration: '08:14',
  ),
  const VorynMockCall(
    id: 'today-sarah-video',
    userId: '@sarah',
    type: VorynCallType.video,
    direction: VorynCallDirection.incoming,
    status: VorynCallStatus.missed,
    group: 'Today',
    time: '9:18 AM',
  ),
  const VorynMockCall(
    id: 'today-aman-video',
    userId: '@aman',
    type: VorynCallType.video,
    direction: VorynCallDirection.incoming,
    status: VorynCallStatus.completed,
    group: 'Today',
    time: '8:05 AM',
    duration: '12:31',
  ),
  const VorynMockCall(
    id: 'yesterday-rahul-office-audio',
    userId: '@rahul_work',
    type: VorynCallType.audio,
    direction: VorynCallDirection.outgoing,
    status: VorynCallStatus.declined,
    group: 'Yesterday',
    time: '7:34 PM',
  ),
  const VorynMockCall(
    id: 'yesterday-rahul-video',
    userId: '@rahul',
    type: VorynCallType.video,
    direction: VorynCallDirection.incoming,
    status: VorynCallStatus.completed,
    group: 'Yesterday',
    time: '4:12 PM',
    duration: '21:06',
  ),
  const VorynMockCall(
    id: 'earlier-alex-audio',
    userId: '@alex',
    type: VorynCallType.audio,
    direction: VorynCallDirection.incoming,
    status: VorynCallStatus.completed,
    group: 'Earlier',
    time: 'Sep 6, 6:40 PM',
    duration: '03:52',
  ),
];

VorynMockUser? findMockUser(String id) {
  for (final user in mockVorynUsers) {
    if (user.id == id) {
      return user;
    }
  }
  return null;
}

List<VorynMockUser> savedMockUsers() {
  final users = mockVorynUsers.where((user) => user.isSaved).toList();
  users.sort(
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
  return users;
}

void saveMockContact(VorynMockUser user, String customName) {
  final current = mockContacts[user.id];
  mockContacts[user.id] = VorynMockContact(
    userId: user.id,
    customName: customName,
    isFavorite: current?.isFavorite ?? false,
  );
  unawaited(_persistContactState());
  unawaited(
    const VorynContactService().saveContact(
      vorynId: user.id,
      customName: customName,
      favorite: current?.isFavorite ?? false,
    ),
  );
}

void setMockFavorite(VorynMockUser user, bool isFavorite) {
  final current = mockContacts[user.id];
  if (current == null) {
    mockContacts[user.id] = VorynMockContact(
      userId: user.id,
      customName: user.displayName,
      isFavorite: isFavorite,
    );
    unawaited(_persistContactState());
    unawaited(
      const VorynContactService().saveContact(
        vorynId: user.id,
        customName: user.displayName,
        favorite: isFavorite,
      ),
    );
    return;
  }
  mockContacts[user.id] = current.copyWith(isFavorite: isFavorite);
  unawaited(_persistContactState());
  unawaited(const VorynContactService().setFavorite(user.id, isFavorite));
}

void removeMockContact(VorynMockUser user) {
  mockContacts.remove(user.id);
  unawaited(_persistContactState());
  unawaited(const VorynContactService().removeContact(user.id));
}

void setMockBlocked(VorynMockUser user, bool blocked) {
  if (blocked) {
    mockBlockedIds.add(user.id);
  } else {
    mockBlockedIds.remove(user.id);
  }
  unawaited(_persistContactState());
  unawaited(const VorynContactService().setBlocked(user.id, blocked));
}

Future<void> initializeVorynContactState() async {
  final preferences = await SharedPreferences.getInstance();
  final encoded = preferences.getString(_contactCacheKey);
  if (encoded != null) {
    try {
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      final contacts = data['contacts'] as Map<String, dynamic>?;
      if (contacts != null) {
        for (final entry in contacts.entries) {
          final value = Map<String, dynamic>.from(entry.value as Map);
          mockContacts[entry.key] = VorynMockContact(
            userId: entry.key,
            customName: value['customName'] as String? ?? entry.key,
            isFavorite: value['favorite'] == true,
          );
        }
      }
      mockBlockedIds.addAll(
        (data['blocked'] as List<dynamic>? ?? const []).cast<String>(),
      );
    } catch (_) {
      // Ignore malformed cache and recover from Supabase when available.
    }
  }
}

void mergeSyncedContacts(List<VorynStoredContact> contacts) {
  for (final contact in contacts) {
    final id = contact.vorynId.startsWith('@')
        ? contact.vorynId
        : '@${contact.vorynId}';
    var user = findMockUser(id);
    if (user == null) {
      final initials = contact.name
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part[0].toUpperCase())
          .join();
      user = VorynMockUser(
        backendUid: contact.uid,
        customName: contact.displayName,
        name: contact.name,
        id: id,
        phone: contact.phone ?? '',
        email: '',
        presence: VorynPresenceStatus.offline,
        initials: initials.isEmpty ? '?' : initials,
      );
      mockVorynUsers.add(user);
    }
    mockContacts[id] = VorynMockContact(
      userId: id,
      customName: contact.displayName,
      isFavorite: contact.favorite,
    );
    if (contact.blocked) mockBlockedIds.add(id);
  }
  unawaited(_persistContactState());
}

const _contactCacheKey = 'voryn.contacts.v2';

Future<void> _persistContactState() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    _contactCacheKey,
    jsonEncode({
      'contacts': {
        for (final entry in mockContacts.entries)
          entry.key: {
            'customName': entry.value.customName,
            'favorite': entry.value.isFavorite,
          },
      },
      'blocked': mockBlockedIds.toList(),
    }),
  );
}
