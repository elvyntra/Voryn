import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import '../calling/voryn_call_history_service.dart';
import '../calling/voryn_call_service.dart';
import '../contacts/voryn_contact_service.dart';
import '../v2/v2_shared.dart';

enum _RecentFilter { all, missed, audio, video }

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  final _search = TextEditingController();
  _RecentFilter _filter = _RecentFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<VorynMockCall> get _calls {
    final query = _search.text.trim().toLowerCase();
    return mockRecentCalls.where((call) {
      if (mockRemovedHistoryUserIds.contains(call.userId)) {
        return false;
      }
      final user = findMockUser(call.userId);
      if (user == null) {
        return false;
      }
      final filterMatch = switch (_filter) {
        _RecentFilter.all => true,
        _RecentFilter.missed => call.status == VorynCallStatus.missed,
        _RecentFilter.audio => call.type == VorynCallType.audio,
        _RecentFilter.video => call.type == VorynCallType.video,
      };
      if (!filterMatch) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return user.displayName.toLowerCase().contains(query) ||
          user.name.toLowerCase().contains(query) ||
          user.id.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final calls = _calls;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(spacing.screen),
        children: [
          VorynGlobalHeader(
            title: 'Recents',
            subtitle: 'Your recent Voryn calls',
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Search recents',
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Filter recents',
                onPressed: () => _showFilterSheet(context),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search recents',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          SizedBox(height: spacing.md),
          if (calls.isEmpty)
            const _EmptyRecents()
          else
            for (final group in const ['Today', 'Yesterday', 'Earlier'])
              if (calls.any((call) => call.group == group)) ...[
                Text(group, style: Theme.of(context).textTheme.labelLarge),
                SizedBox(height: spacing.sm),
                VorynSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final call in calls.where(
                        (item) => item.group == group,
                      ))
                        _RecentCallRow(
                          call: call,
                          onChanged: () => setState(() {}),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.lg),
              ],
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in _RecentFilter.values)
                ChoiceChip(
                  label: Text(_filterLabel(filter)),
                  selected: _filter == filter,
                  onSelected: (_) {
                    setState(() => _filter = filter);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _filterLabel(_RecentFilter filter) => switch (filter) {
    _RecentFilter.all => 'All',
    _RecentFilter.missed => 'Missed',
    _RecentFilter.audio => 'Audio',
    _RecentFilter.video => 'Video',
  };
}

class _RecentCallRow extends StatelessWidget {
  const _RecentCallRow({required this.call, required this.onChanged});

  final VorynMockCall call;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    final user = findMockUser(call.userId)!;
    final missed = call.status == VorynCallStatus.missed;

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CallDetailsScreen(user: user)),
        );
        onChanged();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xs,
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
                    '${_statusText(call)} · ${call.time}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: missed ? colors.danger : colors.textSecondary,
                    ),
                  ),
                  if (call.duration != null) ...[
                    SizedBox(height: spacing.xxs),
                    Text(
                      call.duration!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Semantics(
              button: true,
              label: '${_typeLabel(call.type)} callback',
              child: IconButton(
                tooltip: '${_typeLabel(call.type)} callback',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${_typeLabel(call.type)} callback will connect in the calling phase.',
                    ),
                  ),
                ),
                icon: Icon(_typeIcon(call.type), color: colors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CallDetailsScreen extends StatefulWidget {
  const CallDetailsScreen({super.key, required this.user});

  final VorynMockUser user;

  @override
  State<CallDetailsScreen> createState() => _CallDetailsScreenState();
}

class _CallDetailsScreenState extends State<CallDetailsScreen> {
  late final Future<List<VorynCallHistoryItem>> _historyFuture = _loadHistory();

  Future<List<VorynCallHistoryItem>> _loadHistory() async {
    final allCalls = await const VorynCallHistoryService().load();
    final targetUid = widget.user.backendUid;
    final targetVorynId = widget.user.id.replaceAll('@', '').toLowerCase();
    return allCalls.where((item) {
      if (targetUid != null && item.otherUid == targetUid) return true;
      if (item.vorynId.toLowerCase() == targetVorynId) return true;
      return false;
    }).toList();
  }

  List<VorynMockCall> get _history => mockRecentCalls
      .where(
        (call) =>
            call.userId == widget.user.id &&
            !mockRemovedHistoryUserIds.contains(call.userId),
      )
      .toList();

  void _feedback(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _startDirectCall({required bool video}) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Text('Calling ${widget.user.displayName}…'),
        duration: const Duration(seconds: 2),
      ),
    );

    final candidate = widget.user.backendUid ?? widget.user.id;
    final req = await const VorynCallService().start(
      vorynId: candidate,
      video: video,
    );

    if (!mounted) return;
    if (req.isSuccess && req.id != null) {
      final loc = video
          ? '/active-video-call/${req.id}'
          : '/active-audio-call/${req.id}';
      context.push(loc, extra: {'user': widget.user});
    } else {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(req.error ?? 'Could not start call. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final colors = context.vorynColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Call Details')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(spacing.screen),
          children: [
            Center(
              child: VorynAvatar(
                initials: widget.user.initials,
                size: VorynAvatarSize.xlarge,
                presenceStatus: widget.user.presence,
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              widget.user.displayName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.xxs),
            Text(
              '${widget.user.name} · ${widget.user.id}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.xs),
            Center(
              child: VorynPresenceIndicator(
                status: widget.user.presence,
                label: widget.user.presence.name,
              ),
            ),
            SizedBox(height: spacing.xl),
            Row(
              children: [
                Expanded(
                  child: _ConnectActionTile(
                    icon: Icons.phone_outlined,
                    label: 'Audio call',
                    onPressed: () => _startDirectCall(video: false),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: _ConnectActionTile(
                    icon: Icons.videocam_outlined,
                    label: 'Video call',
                    onPressed: () => _startDirectCall(video: true),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: _ConnectActionTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Message',
                    onPressed: () => _showMessageSheet(context),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            Text('Call history', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.sm),
            FutureBuilder<List<VorynCallHistoryItem>>(
              future: _historyFuture,
              builder: (context, snapshot) {
                final items = snapshot.data;
                if (items != null && items.isNotEmpty) {
                  return VorynSurface(
                    child: Column(
                      children: [
                        for (final item in items) _LiveTimelineRow(item: item),
                      ],
                    ),
                  );
                }
                if (_history.isNotEmpty) {
                  return VorynSurface(
                    child: Column(
                      children: [
                        for (final call in _history) _TimelineRow(call: call),
                      ],
                    ),
                  );
                }
                return const VorynSurface(child: Text('No recent calls'));
              },
            ),
            SizedBox(height: spacing.xl),
            VorynCard(
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => UserPreviewScreen(user: widget.user),
                    ),
                  )
                  .then((_) => setState(() {})),
              child: const _DetailsAction(
                icon: Icons.person_outline,
                label: 'View profile',
              ),
            ),
            if (widget.user.isSaved)
              VorynCard(
                onPressed: () => _showEditSheet(context),
                child: const _DetailsAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit contact',
                ),
              ),
            VorynCard(
              onPressed: () => _confirmRemoveHistory(context),
              child: const _DetailsAction(
                icon: Icons.delete_outline,
                label: 'Remove history',
                destructive: true,
              ),
            ),
            VorynCard(
              onPressed: () => _confirmBlock(context),
              child: const _DetailsAction(
                icon: Icons.block,
                label: 'Block user',
                destructive: true,
              ),
            ),
            VorynCard(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => ReportUserSheet(user: widget.user),
              ),
              child: const _DetailsAction(
                icon: Icons.flag_outlined,
                label: 'Report user',
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              'History changes are local mock data only.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SaveContactSheet(
      user: widget.user,
      title: 'Edit contact',
      label: 'Saved as',
      initialName: widget.user.displayName,
      onSaved: (name) {
        setState(() => saveMockContact(widget.user, name));
      },
    ),
  );

  void _showMessageSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => QuickMessageSheet(user: widget.user),
  );

  void _confirmRemoveHistory(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove call history?'),
      content: Text(
        'This will remove your call history with ${widget.user.displayName} from this device\'s current mock data.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            mockRemovedHistoryUserIds.add(widget.user.id);
            Navigator.pop(dialogContext);
            setState(() {});
            _feedback('Call history removed');
          },
          child: Text(
            'Remove',
            style: TextStyle(color: context.vorynColors.danger),
          ),
        ),
      ],
    ),
  );

  void _confirmBlock(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Block this user?'),
      content: Text(
        '${widget.user.displayName} won\'t be able to contact you on Voryn while blocked.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            setMockBlocked(widget.user, true);
            final candidate = widget.user.backendUid ?? widget.user.id;
            await const VorynContactService().setBlocked(candidate, true);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            _feedback('User blocked');
          },
          child: Text(
            'Block',
            style: TextStyle(color: context.vorynColors.danger),
          ),
        ),
      ],
    ),
  );
}

class _LiveTimelineRow extends StatelessWidget {
  const _LiveTimelineRow({required this.item});

  final VorynCallHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final isVideo = item.callType == 'video';
    final isOutgoing = item.direction == 'outgoing';
    final statusText = switch (item.status) {
      'missed' => 'Missed ${item.callType} call',
      'declined' => 'Declined ${item.callType} call',
      'cancelled' => 'Cancelled ${item.callType} call',
      'failed' => 'Failed ${item.callType} call',
      _ => '${isOutgoing ? '↗ Outgoing' : '↙ Incoming'} ${item.callType}',
    };

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        children: [
          Icon(
            isVideo ? Icons.videocam_outlined : Icons.phone_outlined,
            color: context.vorynColors.accent,
            size: 20,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  _formatCallTime(item.createdAt),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCallTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.call});

  final VorynMockCall call;

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        children: [
          Icon(
            _typeIcon(call.type),
            color: context.vorynColors.accent,
            size: 20,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusText(call),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${call.group} · ${call.time}${call.duration == null ? '' : ' · ${call.duration}'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsAction extends StatelessWidget {
  const _DetailsAction({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return Row(
      children: [
        Icon(icon, color: destructive ? colors.danger : colors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: destructive ? colors.danger : colors.textPrimary,
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: colors.iconMuted),
      ],
    );
  }
}

class _ConnectActionTile extends StatelessWidget {
  const _ConnectActionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colors.accent, size: 28),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecents extends StatelessWidget {
  const _EmptyRecents();

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return VorynSurface(
      child: Column(
        children: [
          Icon(Icons.history_rounded, color: colors.textMuted, size: 36),
          const SizedBox(height: 12),
          Text(
            'No recent calls',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Your Voryn calls will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

String _statusText(VorynMockCall call) {
  final type = call.type == VorynCallType.audio ? 'audio' : 'video';
  return switch (call.status) {
    VorynCallStatus.missed => 'Missed $type call',
    VorynCallStatus.declined => 'Declined $type call',
    VorynCallStatus.failed => 'Failed $type call',
    VorynCallStatus.completed =>
      '${call.direction == VorynCallDirection.outgoing ? '↗ Outgoing' : '↙ Incoming'} $type',
  };
}

String _typeLabel(VorynCallType type) =>
    type == VorynCallType.audio ? 'Audio' : 'Video';

IconData _typeIcon(VorynCallType type) => type == VorynCallType.audio
    ? Icons.phone_outlined
    : Icons.videocam_outlined;
