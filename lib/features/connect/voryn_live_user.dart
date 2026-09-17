import '../../shared/widgets/voryn_presence.dart';
import '../contacts/voryn_contact_service.dart';
import 'mock_voryn_state.dart';
import 'voryn_discovery_service.dart';

VorynMockUser liveUserFromDiscovery(VorynDiscoveryResult result) {
  final name = result.displayName.trim().isEmpty
      ? result.vorynId
      : result.displayName.trim();
  return _liveUser(
    uid: result.uid,
    name: name,
    vorynId: result.vorynId,
    phone: result.phone ?? '',
    presence: switch (result.presence) {
      'online' => VorynPresenceStatus.online,
      'busy' => VorynPresenceStatus.busy,
      _ => VorynPresenceStatus.offline,
    },
  );
}

VorynMockUser liveUserFromContact(VorynStoredContact contact) => _liveUser(
  uid: contact.uid,
  name: contact.name,
  displayName: contact.displayName,
  vorynId: contact.vorynId,
  phone: contact.phone ?? '',
  presence: VorynPresenceStatus.offline,
);

VorynMockUser _liveUser({
  required String uid,
  required String name,
  String? displayName,
  required String vorynId,
  required String phone,
  required VorynPresenceStatus presence,
}) {
  final resolvedName = displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : name.trim();
  final initials = resolvedName
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
  return VorynMockUser(
    backendUid: uid,
    customName: displayName,
    name: name,
    id: vorynId.startsWith('@') ? vorynId : '@$vorynId',
    phone: phone,
    email: '',
    presence: presence,
    initials: initials.isEmpty ? '?' : initials,
  );
}
