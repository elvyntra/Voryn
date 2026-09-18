import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_card.dart';
import '../contacts/voryn_contact_service.dart';

class BlockedUsersLiveScreen extends StatefulWidget {
  const BlockedUsersLiveScreen({super.key});

  @override
  State<BlockedUsersLiveScreen> createState() => _BlockedUsersLiveScreenState();
}

class _BlockedUsersLiveScreenState extends State<BlockedUsersLiveScreen> {
  final _contactService = const VorynContactService();
  late Future<List<VorynBlockedUser>> _future = _load();
  List<VorynBlockedUser>? _users;

  Future<List<VorynBlockedUser>> _load() async {
    final list = await _contactService.loadBlockedUsers();
    if (mounted) {
      setState(() => _users = list);
    }
    return list;
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _unblock(VorynBlockedUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unblock ${user.displayName}?'),
        content: Text(
          '${user.displayName} will be able to call you and see your presence.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final previous = List<VorynBlockedUser>.from(_users ?? []);
    setState(() {
      _users = (_users ?? []).where((u) => u.uid != user.uid).toList();
    });

    try {
      final candidate = user.vorynId.isNotEmpty ? user.vorynId : user.uid;
      await _contactService.unblockUser(candidate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.displayName} unblocked')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _users = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unblock user. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: FutureBuilder<List<VorynBlockedUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _users == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _users == null) {
            return Center(
              child: VorynSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load blocked users.'),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final list = _users ?? snapshot.data ?? const [];

          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(spacing.screen),
                child: VorynSurface(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        size: 44,
                        color: context.vorynColors.iconMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No blocked users',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Contacts you block won\'t be able to call you and will appear here.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: EdgeInsets.all(spacing.screen),
              itemCount: list.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final user = list[index];
                final initials = user.displayName
                    .split(RegExp(r'\s+'))
                    .where((part) => part.isNotEmpty)
                    .take(2)
                    .map((part) => part[0].toUpperCase())
                    .join();

                return VorynCard(
                  child: Row(
                    children: [
                      VorynAvatar(
                        initials: initials.isEmpty ? '?' : initials,
                        size: VorynAvatarSize.medium,
                        imageProvider: user.avatarUrl?.isNotEmpty == true
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (user.vorynId.isNotEmpty)
                              Text(
                                '@${user.vorynId}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _unblock(user),
                        child: const Text('Unblock'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
