import '../../shared/widgets/voryn_presence.dart';

enum VorynCallType { audio, video }

enum VorynCallDirection { incoming, outgoing }

enum VorynCallStatus { completed, missed, declined, failed }

class VorynMockUser {
  const VorynMockUser({
    required this.customName,
    required this.name,
    required this.id,
    required this.phone,
    required this.email,
    required this.presence,
    required this.initials,
  });

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
}

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

final mockContacts = <String, VorynMockContact>{
  '@rahul': const VorynMockContact(
    userId: '@rahul',
    customName: 'Bhai',
    isFavorite: true,
  ),
  '@aman': const VorynMockContact(
    userId: '@aman',
    customName: 'College Aman',
    isFavorite: true,
  ),
  '@rahul_work': const VorynMockContact(
    userId: '@rahul_work',
    customName: 'Rahul Office',
  ),
};

final mockBlockedIds = <String>{};
final mockRemovedHistoryUserIds = <String>{};

const mockVorynUsers = [
  VorynMockUser(
    customName: 'Bhai',
    name: 'Rahul Sharma',
    id: '@rahul',
    phone: '+91 99123 45678',
    email: 'rahul@example.com',
    presence: VorynPresenceStatus.online,
    initials: 'RS',
  ),
  VorynMockUser(
    customName: 'College Aman',
    name: 'Aman Verma',
    id: '@aman',
    phone: '+91 98111 22334',
    email: 'aman@example.com',
    presence: VorynPresenceStatus.online,
    initials: 'AV',
  ),
  VorynMockUser(
    customName: null,
    name: 'Sarah',
    id: '@sarah',
    phone: '+1 202 555 0187',
    email: 'sarah@example.com',
    presence: VorynPresenceStatus.busy,
    initials: 'S',
  ),
  VorynMockUser(
    customName: 'Rahul Office',
    name: 'Rahul Mehta',
    id: '@rahul_work',
    phone: '+91 99887 77665',
    email: 'rahul.work@example.com',
    presence: VorynPresenceStatus.offline,
    initials: 'RM',
  ),
  VorynMockUser(
    customName: null,
    name: 'Alex Johnson',
    id: '@alex',
    phone: '+1 202 555 0144',
    email: 'alex@example.com',
    presence: VorynPresenceStatus.online,
    initials: 'AJ',
  ),
];

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
}

void setMockFavorite(VorynMockUser user, bool isFavorite) {
  final current = mockContacts[user.id];
  if (current == null) {
    mockContacts[user.id] = VorynMockContact(
      userId: user.id,
      customName: user.displayName,
      isFavorite: isFavorite,
    );
    return;
  }
  mockContacts[user.id] = current.copyWith(isFavorite: isFavorite);
}

void removeMockContact(VorynMockUser user) {
  mockContacts.remove(user.id);
}
