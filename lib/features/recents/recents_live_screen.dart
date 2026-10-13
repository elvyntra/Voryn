import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../calling/voryn_call_history_service.dart';
import '../connect/mock_voryn_state.dart';
import '../v2/v2_shared.dart';
import 'recents_screen.dart';

class RecentsLiveScreen extends StatefulWidget {
  const RecentsLiveScreen({super.key});

  @override
  State<RecentsLiveScreen> createState() => _RecentsLiveScreenState();
}

class _RecentsLiveScreenState extends State<RecentsLiveScreen> {
  late Future<List<VorynCallHistoryItem>> _history = _load();
  final _search = TextEditingController();
  final Set<String> _selectedCallIds = {};
  bool _isDeleting = false;

  bool get _isSelectionMode => _selectedCallIds.isNotEmpty;

  Future<List<VorynCallHistoryItem>> _load() =>
      const VorynCallHistoryService().load();
  void _reload() => setState(() {
        _selectedCallIds.clear();
        _history = _load();
      });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSelectCall(String id) {
    setState(() {
      if (_selectedCallIds.contains(id)) {
        _selectedCallIds.remove(id);
      } else {
        _selectedCallIds.add(id);
      }
    });
  }

  void _toggleSelectAll(List<VorynCallHistoryItem> calls) {
    setState(() {
      if (_selectedCallIds.length == calls.length) {
        _selectedCallIds.clear();
      } else {
        _selectedCallIds.addAll(calls.map((c) => c.id));
      }
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedCallIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'call' : 'calls'}?'),
        content: Text(
          'Remove $count selected ${count == 1 ? 'call' : 'calls'} from your personal call history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeleting = true);
      final ids = _selectedCallIds.toList();
      try {
        await Future.wait(
          ids.map((id) => const VorynCallHistoryService().deleteCall(id)),
        );
        if (mounted) {
          _reload();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed $count ${count == 1 ? 'call' : 'calls'} from history.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<List<VorynCallHistoryItem>>(
      future: _history,
      builder: (context, snapshot) {
        final spacing = context.vorynSpacing;
        final colors = context.vorynColors;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _RecentState(
            message: 'Could not load call history.',
            action: _reload,
          );
        }
        final query = _search.text.trim().toLowerCase();
        final calls = (snapshot.data ?? const [])
            .where(
              (call) =>
                  call.displayName.toLowerCase().contains(query) ||
                  call.vorynId.toLowerCase().contains(query),
            )
            .toList();

        final allSelected = calls.isNotEmpty && _selectedCallIds.length == calls.length;

        return Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(
                spacing.screen,
                spacing.screen,
                spacing.screen,
                _isSelectionMode ? 96 : spacing.screen,
              ),
              children: [
                if (_isSelectionMode)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Cancel selection',
                        onPressed: () => setState(() => _selectedCallIds.clear()),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_selectedCallIds.length} selected',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _toggleSelectAll(calls),
                        icon: Icon(
                          allSelected
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                          size: 18,
                        ),
                        label: Text(allSelected ? 'Deselect all' : 'Select all'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.accent,
                        ),
                      ),
                    ],
                  )
                else
                  const VorynGlobalHeader(
                    title: 'Recents',
                    subtitle: 'Your real Voryn call history',
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
                SizedBox(height: spacing.lg),
                if (calls.isEmpty)
                  _RecentState(
                    message: query.isEmpty
                        ? 'No calls yet. Your completed Voryn calls will appear here.'
                        : 'No calls match your search.',
                  )
                else
                  ...calls.map(
                    (call) => _CallRow(
                      call: call,
                      isSelectionMode: _isSelectionMode,
                      isSelected: _selectedCallIds.contains(call.id),
                      onTap: _isSelectionMode
                          ? () => _toggleSelectCall(call.id)
                          : null,
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        _toggleSelectCall(call.id);
                      },
                    ),
                  ),
              ],
            ),

            // Bottom Floating Pip of Delete
            if (_isSelectionMode)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  color: colors.surface,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.border.withValues(alpha: 0.8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_selectedCallIds.length} selected',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() => _selectedCallIds.clear()),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _isDeleting ? null : _confirmDeleteSelected,
                          icon: _isDeleting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_outline_rounded, size: 18),
                          label: Text('Delete (${_selectedCallIds.length})'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.call,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  final VorynCallHistoryItem call;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final initials = call.displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final user = VorynMockUser(
      backendUid: call.otherUid,
      customName: null,
      name: call.displayName,
      id: '@${call.vorynId}',
      phone: '',
      email: '',
      presence: VorynPresenceStatus.offline,
      initials: initials.isEmpty ? '?' : initials,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: VorynCard(
        onPressed: isSelectionMode
            ? onTap
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CallDetailsScreen(user: user)),
                ),
        onLongPress: onLongPress,
        child: Row(
          children: [
            if (isSelectionMode) ...[
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected ? colors.accent : colors.iconMuted,
                size: 22,
              ),
              const SizedBox(width: 12),
            ],
            VorynAvatar(initials: user.initials, size: VorynAvatarSize.medium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${call.status} ${call.callType} call · ${_when(call.createdAt)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Icon(
              call.callType == 'video'
                  ? Icons.videocam_outlined
                  : Icons.phone_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentState extends StatelessWidget {
  const _RecentState({required this.message, this.action});
  final String message;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(
    child: VorynSurface(
      child: Column(
        children: [
          const Icon(Icons.history_rounded, size: 38),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (action != null)
            TextButton(onPressed: action, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

String _when(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime.toLocal());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}
