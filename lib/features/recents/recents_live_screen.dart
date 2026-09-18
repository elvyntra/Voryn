import 'package:flutter/material.dart';

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

  Future<List<VorynCallHistoryItem>> _load() =>
      const VorynCallHistoryService().load();
  void _reload() => setState(() => _history = _load());

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<List<VorynCallHistoryItem>>(
      future: _history,
      builder: (context, snapshot) {
        final spacing = context.vorynSpacing;
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
        return ListView(
          padding: EdgeInsets.all(spacing.screen),
          children: [
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
              ...calls.map((call) => _CallRow(call: call)),
          ],
        );
      },
    ),
  );
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call});
  final VorynCallHistoryItem call;

  @override
  Widget build(BuildContext context) {
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
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CallDetailsScreen(user: user)),
        ),
        child: Row(
          children: [
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
