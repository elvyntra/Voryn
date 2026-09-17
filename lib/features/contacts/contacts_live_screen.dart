import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_card.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import '../connect/voryn_live_user.dart';
import '../v2/v2_shared.dart';
import 'contacts_screen.dart' show AddContactScreen;
import 'voryn_contact_service.dart';

class ContactsLiveScreen extends StatefulWidget {
  const ContactsLiveScreen({super.key});

  @override
  State<ContactsLiveScreen> createState() => _ContactsLiveScreenState();
}

class _ContactsLiveScreenState extends State<ContactsLiveScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  List<VorynStoredContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contacts = await const VorynContactService().loadContacts();
      if (mounted) setState(() => _contacts = contacts);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load contacts.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final result = await const VorynContactService().syncDeviceContacts();
    if (!mounted) return;
    setState(() => _syncing = false);
    if (result.permissionDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Allow contact access to sync your phone contacts.'),
        ),
      );
      return;
    }
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not sync contacts.')),
      );
      return;
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.contacts.length} Voryn contacts synced'),
        ),
      );
    }
  }

  List<VorynStoredContact> get _filtered {
    final value = _search.text.trim().toLowerCase();
    if (value.isEmpty) return _contacts;
    return _contacts
        .where(
          (contact) =>
              contact.displayName.toLowerCase().contains(value) ||
              contact.name.toLowerCase().contains(value) ||
              contact.vorynId.toLowerCase().contains(value) ||
              (contact.phone ?? '').contains(value),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final contacts = _filtered;
    final favorites = contacts.where((contact) => contact.favorite).toList();
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(spacing.screen),
        children: [
          const VorynGlobalHeader(
            title: 'Contacts',
            subtitle: 'Your people on Voryn',
          ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              IconButton(
                tooltip: 'Add contact',
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddContactScreen()),
                  );
                  _load();
                },
              ),
              IconButton(
                tooltip: 'Sync phone contacts',
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                onPressed: _syncing ? null : _sync,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search contacts',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          SizedBox(height: spacing.xl),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            _ContactsState(message: _error!, action: _load)
          else ...[
            Text('Favorites', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.sm),
            if (favorites.isEmpty)
              const _ContactsState(
                message: 'Favorite contacts will appear here.',
              )
            else
              ...favorites.map(
                (contact) => _ContactRow(contact: contact, onChanged: _load),
              ),
            SizedBox(height: spacing.xl),
            Text('Contacts', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.sm),
            if (contacts.isEmpty)
              _ContactsState(
                message: _search.text.isEmpty
                    ? 'No contacts yet.'
                    : 'No contacts match your search.',
                action: _search.text.isEmpty
                    ? () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddContactScreen(),
                          ),
                        );
                        _load();
                      }
                    : null,
                actionLabel: 'Add contact',
              )
            else
              ...contacts.map(
                (contact) => _ContactRow(contact: contact, onChanged: _load),
              ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onChanged});
  final VorynStoredContact contact;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final VorynMockUser user = liveUserFromContact(contact);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: VorynCard(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserPreviewScreen(user: user)),
          );
          onChanged();
        },
        child: Row(
          children: [
            VorynAvatar(initials: user.initials, size: VorynAvatarSize.medium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '@${contact.vorynId}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (contact.favorite) const Icon(Icons.star_rounded),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _ContactsState extends StatelessWidget {
  const _ContactsState({
    required this.message,
    this.action,
    this.actionLabel = 'Try again',
  });
  final String message;
  final VoidCallback? action;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => VorynSurface(
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        if (action != null)
          TextButton(onPressed: action, child: Text(actionLabel)),
      ],
    ),
  );
}
