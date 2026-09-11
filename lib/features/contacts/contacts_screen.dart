import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../../shared/widgets/voryn_text_input.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import '../connect/voryn_discovery_service.dart';
import '../v2/v2_shared.dart';
import 'voryn_contact_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _searching = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadStoredContacts();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<VorynMockUser> get _contacts {
    final query = _search.text.trim().toLowerCase();
    final users = savedMockUsers().where((user) {
      if (query.isEmpty) {
        return true;
      }
      return user.displayName.toLowerCase().contains(query) ||
          user.name.toLowerCase().contains(query) ||
          user.id.toLowerCase().contains(query) ||
          user.phone.toLowerCase().contains(query);
    }).toList();
    return users;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final contacts = _contacts;
    final favorites = savedMockUsers()
        .where((user) => user.isFavorite)
        .toList();
    final grouped = _groupContacts(contacts);

    return SafeArea(
      child: Stack(
        children: [
          ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              spacing.screen,
              spacing.screen,
              spacing.screen + 24,
              spacing.screen,
            ),
            children: [
              VorynGlobalHeader(
                title: 'Contacts',
                subtitle: 'Your people on Voryn',
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Add contact',
                    onPressed: () => _openAddContact(context),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
                  IconButton(
                    tooltip: 'Search contacts',
                    onPressed: () => setState(() => _searching = !_searching),
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Refresh contacts',
                    onPressed: _syncing ? null : _syncContacts,
                    icon: _syncing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                ],
              ),
              if (_searching) ...[
                SizedBox(height: spacing.md),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search contacts',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
              SizedBox(height: spacing.lg),
              Text('Favorites', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: spacing.sm),
              if (favorites.isEmpty)
                Text(
                  'Favorite contacts will appear here.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                SizedBox(
                  height: 102,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) => _FavoriteContact(
                      user: favorites[index],
                      onChanged: () => setState(() {}),
                    ),
                    separatorBuilder: (_, _) => SizedBox(width: spacing.sm),
                    itemCount: favorites.length,
                  ),
                ),
              SizedBox(height: spacing.xl),
              Text('Contacts', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: spacing.sm),
              if (contacts.isEmpty)
                _EmptyContacts(onAdd: () => _openAddContact(context))
              else
                for (final entry in grouped.entries) ...[
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  SizedBox(height: spacing.xs),
                  VorynSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final user in entry.value)
                          _ContactRow(
                            user: user,
                            onChanged: () => setState(() {}),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing.md),
                ],
            ],
          ),
          Positioned(
            top: 154,
            right: 4,
            bottom: 16,
            child: _AlphabetIndex(
              available: grouped.keys.toSet(),
              onTap: (letter) => _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<VorynMockUser>> _groupContacts(
    List<VorynMockUser> contacts,
  ) {
    final grouped = <String, List<VorynMockUser>>{};
    for (final user in contacts) {
      final letter = user.displayName.characters.first.toUpperCase();
      grouped.putIfAbsent(letter, () => []).add(user);
    }
    return grouped;
  }

  void _openAddContact(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddContactScreen()));
    setState(() {});
  }

  Future<void> _syncContacts() async {
    setState(() => _syncing = true);
    final result = await const VorynContactService().syncDeviceContacts();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      if (result.isSuccess) mergeSyncedContacts(result.contacts);
    });
    if (result.permissionDenied) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Contacts permission needed'),
          content: const Text(
            'Allow contact access in system settings to find people you already know. Voryn remains usable without it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                const VorynContactService().openContactSettings();
              },
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      return;
    }
    final message =
        result.error ??
        '${result.contacts.length} Voryn contact${result.contacts.length == 1 ? '' : 's'} synced';
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _loadStoredContacts() async {
    final contacts = await const VorynContactService().loadContacts();
    if (!mounted || contacts.isEmpty) return;
    setState(() => mergeSyncedContacts(contacts));
  }
}

class _FavoriteContact extends StatelessWidget {
  const _FavoriteContact({required this.user, required this.onChanged});

  final VorynMockUser user;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 82,
    child: InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserPreviewScreen(user: user)),
        );
        onChanged();
      },
      child: Column(
        children: [
          VorynAvatar(
            initials: user.initials,
            size: VorynAvatarSize.medium,
            presenceStatus: user.presence,
          ),
          const SizedBox(height: 8),
          Text(
            user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          VorynPresenceIndicator(
            status: user.presence,
            label: user.presence.name,
          ),
        ],
      ),
    ),
  );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.user, required this.onChanged});

  final VorynMockUser user;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final colors = context.vorynColors;

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserPreviewScreen(user: user)),
        );
        onChanged();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.sm,
        ),
        child: Row(
          children: [
            VorynAvatar(
              initials: user.initials,
              size: VorynAvatarSize.medium,
              presenceStatus: user.presence,
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: spacing.xxs),
                  Text(
                    '${user.name} · ${user.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: spacing.xxs),
                  VorynPresenceIndicator(
                    status: user.presence,
                    label: user.presence.name,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.iconMuted),
          ],
        ),
      ),
    );
  }
}

class _AlphabetIndex extends StatelessWidget {
  const _AlphabetIndex({required this.available, required this.onTap});

  final Set<String> available;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final letter in letters.characters)
          Semantics(
            button: available.contains(letter),
            label: 'Jump to $letter contacts',
            child: InkWell(
              onTap: available.contains(letter) ? () => onTap(letter) : null,
              child: SizedBox(
                width: 24,
                height: 13,
                child: Center(
                  child: Text(
                    letter,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: available.contains(letter)
                          ? colors.accent
                          : colors.textMuted.withValues(alpha: 0.35),
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  VorynMockUser? _result;
  bool _searched = false;
  bool _searching = false;
  _SearchType _searchType = _SearchType.vorynId;

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    return Scaffold(
      appBar: AppBar(title: const Text('Add contact')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            spacing.screen,
            spacing.screen,
            spacing.screen,
            MediaQuery.viewInsetsOf(context).bottom + spacing.screen,
          ),
          children: [
            Text(
              'Find someone on Voryn',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Search using their Voryn ID or phone number.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.lg),
            SegmentedButton<_SearchType>(
              segments: const [
                ButtonSegment(
                  value: _SearchType.vorynId,
                  label: Text('Voryn ID'),
                ),
                ButtonSegment(value: _SearchType.phone, label: Text('Phone')),
              ],
              selected: {_searchType},
              onSelectionChanged: _searching
                  ? null
                  : (selection) {
                      _queryFocus.unfocus();
                      setState(() {
                        _searchType = selection.first;
                        _query.clear();
                        _result = null;
                        _searched = false;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _queryFocus.requestFocus();
                      });
                    },
            ),
            SizedBox(height: spacing.md),
            VorynTextInput(
              key: ValueKey(_searchType),
              label: _searchType == _SearchType.vorynId
                  ? 'Voryn ID'
                  : 'Phone number',
              controller: _query,
              focusNode: _queryFocus,
              keyboardType: _searchType == _SearchType.phone
                  ? TextInputType.phone
                  : TextInputType.text,
              onChanged: (_) => setState(() {
                _result = null;
                _searched = false;
              }),
            ),
            SizedBox(height: spacing.md),
            VorynButton.primary(
              label: 'Search',
              isLoading: _searching,
              onPressed: _searching ? null : _search,
            ),
            SizedBox(height: spacing.xl),
            if (_searched && _result == null) const _NoContactFound(),
            if (_result != null)
              _AddContactResult(
                user: _result!,
                onSaved: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searched = true;
      _searching = true;
      _result = null;
    });
    try {
      final result = _searchType == _SearchType.vorynId
          ? await const VorynDiscoveryService().findByVorynId(query)
          : await const VorynDiscoveryService().findByPhone(query);
      if (!mounted) return;
      setState(() {
        _result = result == null ? null : VorynMockUser.fromDiscovery(result);
        if (_result != null &&
            !mockVorynUsers.any((user) => user.id == _result!.id)) {
          mockVorynUsers.add(_result!);
        }
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }
}

enum _SearchType { vorynId, phone }

class _AddContactResult extends StatefulWidget {
  const _AddContactResult({required this.user, required this.onSaved});

  final VorynMockUser user;
  final VoidCallback onSaved;

  @override
  State<_AddContactResult> createState() => _AddContactResultState();
}

class _AddContactResultState extends State<_AddContactResult> {
  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final user = widget.user;

    return VorynSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              VorynAvatar(
                initials: user.initials,
                size: VorynAvatarSize.large,
                presenceStatus: user.presence,
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      user.id,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    VorynPresenceIndicator(
                      status: user.presence,
                      label: user.presence.name,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Text('Phone:', style: Theme.of(context).textTheme.labelMedium),
          Text(user.phone, style: Theme.of(context).textTheme.bodyMedium),
          SizedBox(height: spacing.sm),
          Text('Email:', style: Theme.of(context).textTheme.labelMedium),
          Text(user.email, style: Theme.of(context).textTheme.bodyMedium),
          SizedBox(height: spacing.lg),
          if (user.isSaved) ...[
            Text(
              'Already in your contacts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Saved as ${user.displayName}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ] else
            VorynButton.primary(
              label: 'Save contact',
              leadingIcon: Icons.person_add_alt_1_outlined,
              onPressed: () => _showSave(context),
            ),
        ],
      ),
    );
  }

  void _showSave(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SaveContactSheet(
      user: widget.user,
      onSaved: (name) {
        saveMockContact(widget.user, name);
        widget.onSaved();
      },
    ),
  );
}

class _NoContactFound extends StatelessWidget {
  const _NoContactFound();

  @override
  Widget build(BuildContext context) => VorynSurface(
    child: Column(
      children: [
        Icon(
          Icons.person_search_outlined,
          size: 36,
          color: context.vorynColors.textMuted,
        ),
        const SizedBox(height: 12),
        Text(
          'No Voryn user found',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Check the Voryn ID, phone number, or email.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => VorynSurface(
    child: Column(
      children: [
        Icon(
          Icons.contacts_outlined,
          size: 36,
          color: context.vorynColors.textMuted,
        ),
        const SizedBox(height: 12),
        Text('No contacts yet', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Find someone on Voryn and save them to your contacts.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        VorynButton.secondary(label: 'Add contact', onPressed: onAdd),
      ],
    ),
  );
}
