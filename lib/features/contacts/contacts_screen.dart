import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../../shared/widgets/voryn_text_input.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import '../v2/v2_shared.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _searching = false;

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
                subtitle: 'Your people on VoRyn',
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
              VorynSurface(
                child: _MyProfileCard(
                  onTap: () => _feedback(
                    'Profile will be available in a later UI phase.',
                  ),
                ),
              ),
              SizedBox(height: spacing.xl),
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

  void _feedback(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _MyProfileCard extends StatelessWidget {
  const _MyProfileCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: const Row(
      children: [
        VorynAvatar(
          initials: 'VM',
          size: VorynAvatarSize.medium,
          presenceStatus: VorynPresenceStatus.online,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My profile'),
              SizedBox(height: 4),
              Text('Vikash Mishra'),
              Text('@vikash'),
              VorynPresenceIndicator(
                status: VorynPresenceStatus.online,
                label: 'Online',
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
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
  VorynMockUser? _result;
  bool _searched = false;

  @override
  void dispose() {
    _query.dispose();
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
              'Find someone on VoRyn',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Search using their VoRyn ID, phone number, or email.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.lg),
            VorynTextInput(
              label: 'VoRyn ID, phone or email',
              controller: _query,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {
                _result = null;
                _searched = false;
              }),
            ),
            SizedBox(height: spacing.md),
            VorynButton.primary(label: 'Search', onPressed: _search),
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

  void _search() {
    final query = _query.text.trim().toLowerCase();
    final numeric = query.replaceAll(RegExp(r'[^0-9]'), '');
    VorynMockUser? match;
    for (final user in mockVorynUsers) {
      final phone = user.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (user.id.toLowerCase() == query ||
          user.email.toLowerCase() == query ||
          (numeric.isNotEmpty && phone.endsWith(numeric))) {
        match = user;
        break;
      }
    }
    setState(() {
      _searched = true;
      _result = match;
    });
  }
}

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
          'No VoRyn user found',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Check the VoRyn ID, phone number, or email.',
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
          'Find someone on VoRyn and save them to your contacts.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        VorynButton.secondary(label: 'Add contact', onPressed: onAdd),
      ],
    ),
  );
}
