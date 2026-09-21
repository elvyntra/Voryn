import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import 'conversation_screen.dart';
import 'voryn_message_models.dart';
import 'voryn_message_repository.dart';

class CallMessagesScreen extends StatefulWidget {
  const CallMessagesScreen({super.key, this.initialThreadId});

  final String? initialThreadId;

  @override
  State<CallMessagesScreen> createState() => _CallMessagesScreenState();
}

class _CallMessagesScreenState extends State<CallMessagesScreen> {
  final _repo = VorynMessageRepository.instance;
  late Future<List<VorynMessageThread>> _threadsFuture = _repo.loadThreads();
  StreamSubscription<void>? _threadsSub;
  String? _selectedThreadId;

  @override
  void initState() {
    super.initState();
    _selectedThreadId = widget.initialThreadId;
    debugPrint('[MESSAGE_NAV] destination=inbox screen=CallMessagesScreen');
    _repo.initializeRealtime();
    _threadsSub = _repo.onThreadsChanged.listen((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _threadsSub?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _threadsFuture = _repo.loadThreads();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktopOrTablet = screenWidth >= 768;

    return FutureBuilder<List<VorynMessageThread>>(
      future: _threadsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[MESSAGE_INBOX] action=ui_error error=${snapshot.error}');
          return Scaffold(
            backgroundColor: colors.background,
            appBar: AppBar(
              title: const Text('Call Messages'),
              actions: [
                IconButton(
                  tooltip: 'Retry',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _reload,
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: colors.danger,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load messages',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final threads = snapshot.data ?? [];
        final isLoading =
            snapshot.connectionState != ConnectionState.done && threads.isEmpty;

        if (snapshot.connectionState == ConnectionState.done) {
          debugPrint(
            '[MESSAGE_INBOX] action=ui_render threads=${threads.length}',
          );
        }

        if (isDesktopOrTablet) {
          // Responsive 2/3-pane layout for desktop / tablet
          return Scaffold(
            backgroundColor: colors.background,
            appBar: AppBar(
              title: const Text('Call Messages'),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _reload,
                ),
              ],
            ),
            body: Row(
              children: [
                SizedBox(
                  width: 360,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: colors.border)),
                    ),
                    child: _buildThreadList(
                      threads,
                      isLoading,
                      colors,
                      isDesktop: true,
                    ),
                  ),
                ),
                Expanded(
                  child: _selectedThreadId != null
                      ? ConversationScreen(
                          key: ValueKey(_selectedThreadId),
                          threadId: _selectedThreadId!,
                          isEmbeddedPane: true,
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 64,
                                color: colors.iconMuted,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Select a conversation',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(color: colors.textMuted),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          );
        }

        // Single-pane phone layout
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            title: const Text('Call Messages'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _reload,
              ),
            ],
          ),
          body: _buildThreadList(threads, isLoading, colors, isDesktop: false),
        );
      },
    );
  }

  Widget _buildThreadList(
    List<VorynMessageThread> threads,
    bool isLoading,
    dynamic colors, {
    required bool isDesktop,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (threads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mail_outline_rounded,
                size: 48,
                color: colors.iconMuted,
              ),
              const SizedBox(height: 12),
              Text(
                'No call messages yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Messages from people who want to connect will appear here.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: threads.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, indent: 72, color: colors.border),
        itemBuilder: (context, index) {
          final thread = threads[index];
          final isSelected = isDesktop && thread.threadId == _selectedThreadId;

          return _ThreadListTile(
            thread: thread,
            isSelected: isSelected,
            onTap: () {
              if (isDesktop) {
                setState(() => _selectedThreadId = thread.threadId);
              } else {
                context
                    .push(
                      '/messages/thread/${thread.threadId}',
                      extra: {
                        'otherUserUid': thread.otherUserUid,
                        'otherUserName': thread.otherUserName,
                        'otherUserVorynId': thread.otherUserVorynId,
                        'otherUserAvatarUrl': thread.otherUserAvatarUrl,
                      },
                    )
                    .then((_) => _reload());
              }
            },
          );
        },
      ),
    );
  }
}

class _ThreadListTile extends StatelessWidget {
  const _ThreadListTile({
    required this.thread,
    required this.isSelected,
    required this.onTap,
  });

  final VorynMessageThread thread;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final nameParts = thread.otherUserName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    final initials = nameParts.map((p) => p[0].toUpperCase()).join();

    final timeText = thread.lastMessageCreatedAt != null
        ? _formatTime(thread.lastMessageCreatedAt!)
        : '';

    final snippet = thread.lastMessageBody ?? 'No messages yet';
    final formattedSnippet = thread.lastMessageRemindToCall
        ? '📞 $snippet'
        : snippet;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? colors.accentSoft : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            VorynAvatar(
              initials: initials.isEmpty ? '?' : initials,
              size: VorynAvatarSize.medium,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.otherUserName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: thread.hasUnread
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                              ),
                        ),
                      ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 11,
                                color: thread.hasUnread
                                    ? colors.accent
                                    : colors.textMuted,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formattedSnippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: thread.hasUnread
                                    ? colors.textPrimary
                                    : colors.textMuted,
                                fontWeight: thread.hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                        ),
                      ),
                      if (thread.hasUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            thread.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  final timeStr = '$displayHour:$minute $period';

  if (now.year == local.year &&
      now.month == local.month &&
      now.day == local.day) {
    return timeStr;
  }
  final difference = now.difference(local);
  if (difference.inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[local.weekday - 1];
  }
  return '${local.month}/${local.day}';
}
