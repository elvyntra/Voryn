import 'package:flutter/material.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import '../messages/voryn_call_message_service.dart';
import '../profile/profile_live_screen.dart';
import '../profile/voryn_profile.dart';
import '../profile/voryn_profile_service.dart';

bool mockDoNotDisturb = false;

class VorynGlobalHeader extends StatelessWidget {
  const VorynGlobalHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Call Messages',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CallMessagesScreen()),
        ),
        icon: const Icon(Icons.mail_outline_rounded),
      ),
      GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileLiveScreen()),
        ),
        child: const _CurrentProfileAvatar(),
      ),
    ],
  );
}

class _CurrentProfileAvatar extends StatelessWidget {
  const _CurrentProfileAvatar();

  @override
  Widget build(BuildContext context) => FutureBuilder<VorynProfile?>(
    future: const VorynProfileService().currentProfile(),
    builder: (context, snapshot) {
      final profile = snapshot.data;
      final name = profile?.fullName.trim();
      final initials = (name?.isNotEmpty == true ? name! : 'Voryn user')
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part[0].toUpperCase())
          .join();
      return VorynAvatar(
        initials: initials.isEmpty ? '?' : initials,
        size: VorynAvatarSize.small,
        imageProvider: profile?.avatarUrl?.isNotEmpty == true
            ? NetworkImage(profile!.avatarUrl!)
            : null,
      );
    },
  );
}

class CallMessagesScreen extends StatefulWidget {
  const CallMessagesScreen({super.key});
  @override
  State<CallMessagesScreen> createState() => _MessagesState();
}

class _MessagesState extends State<CallMessagesScreen> {
  late Future<List<VorynCallMessage>> _messages = _loadMessages();

  Future<List<VorynCallMessage>> _loadMessages() =>
      const VorynCallMessageService().loadInbox();

  void _reload() {
    setState(() {
      _messages = _loadMessages();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Call Messages'),
      actions: [
        IconButton(
          tooltip: 'Refresh messages',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<VorynCallMessage>>(
      future: _messages,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MessageState(
            icon: Icons.cloud_off_outlined,
            title: 'Messages are unavailable',
            detail: snapshot.error.toString(),
            actionLabel: 'Try again',
            onAction: _reload,
          );
        }
        final messages = snapshot.data ?? const [];
        if (messages.isEmpty) {
          return const _MessageState(
            icon: Icons.mail_outline_rounded,
            title: 'No call messages yet',
            detail:
                'Messages from people who want to connect will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: EdgeInsets.all(context.vorynSpacing.screen),
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _MessageRow(message: messages[index], onChanged: _reload),
          ),
        );
      },
    ),
  );
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.onChanged});

  final VorynCallMessage message;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final nameParts = message.senderName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    final initials = nameParts.map((part) => part[0].toUpperCase()).join();
    return VorynCard(
      onPressed: () async {
        if (!message.isRead) {
          await const VorynCallMessageService().markRead(message.id);
          onChanged();
        }
      },
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VorynAvatar(
            initials: initials.isEmpty ? '?' : initials,
            size: VorynAvatarSize.medium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        message.senderName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!message.isRead)
                      Icon(Icons.circle, size: 9, color: colors.accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text('@${message.senderVorynId}'),
                const SizedBox(height: 6),
                Text(message.body),
                if (message.remindToCall) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Requested a call back',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: colors.accent),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _formatTime(message.createdAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reply',
            icon: const Icon(Icons.reply_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => QuickMessageSheet(
                user: VorynMockUser(
                  backendUid: message.senderUid,
                  customName: null,
                  name: message.senderName,
                  id: '@${message.senderVorynId}',
                  phone: '',
                  email: '',
                  presence: VorynPresenceStatus.offline,
                  initials: initials.isEmpty ? '?' : initials,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(context.vorynSpacing.screen),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: context.vorynColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(detail, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _formatTime(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime.toLocal());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays == 1) return 'Yesterday';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}
