import 'package:flutter/material.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../messages/call_messages_screen.dart';
import '../messages/voryn_message_repository.dart';
import '../profile/profile_live_screen.dart';
import '../profile/voryn_profile.dart';
import '../profile/voryn_profile_service.dart';

export '../messages/call_messages_screen.dart';

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
      ValueListenableBuilder<int>(
        valueListenable: VorynMessageRepository.instance.totalUnreadCount,
        builder: (context, unread, _) {
          return IconButton(
            tooltip: 'Call Messages',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CallMessagesScreen()),
            ),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : unread.toString()),
              child: const Icon(Icons.mail_outline_rounded),
            ),
          );
        },
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
