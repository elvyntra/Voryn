import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../profile/profile_screens.dart';

final mockCallMessages = <Map<String, String>>[
  {
    'name': 'Bhai',
    'message': 'Call me when you\'re free.',
    'time': '2 min ago',
  },
  {
    'name': 'College Aman',
    'message': 'Are you free for a call?',
    'time': '18 min ago',
  },
  {
    'name': 'Rahul Office',
    'message': 'I\'ll call you later.',
    'time': 'Yesterday',
  },
];
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
        icon: Badge(
          label: const Text('2'),
          child: const Icon(Icons.mail_outline_rounded),
        ),
      ),
      GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        child: const VorynAvatar(initials: 'VM', size: VorynAvatarSize.small),
      ),
    ],
  );
}

class CallMessagesScreen extends StatefulWidget {
  const CallMessagesScreen({super.key});
  @override
  State<CallMessagesScreen> createState() => _MessagesState();
}

class _MessagesState extends State<CallMessagesScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Call Messages')),
    body: ListView(
      padding: EdgeInsets.all(context.vorynSpacing.screen),
      children: [
        for (final message in mockCallMessages)
          Card(
            child: ListTile(
              leading: const VorynAvatar(
                initials: 'VM',
                size: VorynAvatarSize.small,
              ),
              title: Text(message['name']!),
              subtitle: Text('${message['message']}\n${message['time']}'),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Reply',
                icon: const Icon(Icons.reply_rounded),
                onPressed: () => _send(context),
              ),
            ),
          ),
      ],
    ),
  );
  void _send(BuildContext c) {
    Clipboard.setData(const ClipboardData(text: 'Call me when you\'re free.'));
    ScaffoldMessenger.of(
      c,
    ).showSnackBar(const SnackBar(content: Text('Message sent')));
  }
}
