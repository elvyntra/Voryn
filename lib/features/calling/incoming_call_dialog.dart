import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import 'voryn_call_history_service.dart';
import 'voryn_call_service.dart';
import '../../core/notifications/voryn_firebase_messaging.dart';

class IncomingCallDialog extends StatelessWidget {
  const IncomingCallDialog({super.key, required this.call});

  final VorynCallHistoryItem call;

  VorynMockUser _caller() {
    final parts = call.displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    final initials = parts.map((part) => part[0].toUpperCase()).join();
    return VorynMockUser(
      backendUid: call.otherUid,
      customName: null,
      name: call.displayName,
      id: call.vorynId.startsWith('@') ? call.vorynId : '@${call.vorynId}',
      phone: '',
      email: '',
      presence: VorynPresenceStatus.online,
      initials: initials.isEmpty ? '?' : initials,
    );
  }

  @override
  Widget build(BuildContext context) {
    final caller = _caller();
    final video = call.callType == 'video';
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: SizedBox.expand(
        child: Material(
          color: colors.background,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.screen),
              child: Column(
                children: [
                  SizedBox(height: spacing.xl),
                  Text(
                    caller.displayName,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.displayLarge?.copyWith(fontSize: 40),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    caller.id,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: spacing.xl),
                  _CallerRings(caller: caller),
                  const Spacer(),
                  Icon(
                    video ? Icons.videocam_outlined : Icons.call_outlined,
                    size: 24,
                    color: colors.textSecondary,
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    video ? 'Incoming video call' : 'Incoming audio call',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: spacing.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallAction(
                        color: colors.success,
                        icon: video
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        label: 'Accept',
                        onPressed: () => Navigator.pop(context, caller),
                      ),
                      _CallAction(
                        color: colors.danger,
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        onPressed: () async {
                          await const VorynCallService().decline(call.id);
                          if (context.mounted) Navigator.pop(context, false);
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.xl),
                  TextButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => QuickMessageSheet(user: caller),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Send message'),
                  ),
                  SizedBox(height: spacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallerRings extends StatelessWidget {
  const _CallerRings({required this.caller});

  final VorynMockUser caller;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return SizedBox.square(
      dimension: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final size in [220.0, 176.0, 138.0])
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.accent.withValues(
                    alpha: size == 138 ? 0.32 : 0.13,
                  ),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceRaised,
              boxShadow: [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.24),
                  blurRadius: 28,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: VorynAvatar(
              initials: caller.initials,
              size: VorynAvatarSize.xlarge,
              presenceStatus: VorynPresenceStatus.online,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox.square(
        dimension: 68,
        child: IconButton.filled(
          tooltip: label,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 29),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

Future<void> showIncomingCallDialog(
  BuildContext context,
  VorynCallHistoryItem call,
) async {
  context.push('/incoming-call/${call.id}', extra: {'call': call});
}

class IncomingCallLaunchScreen extends StatefulWidget {
  const IncomingCallLaunchScreen({super.key});

  @override
  State<IncomingCallLaunchScreen> createState() =>
      _IncomingCallLaunchScreenState();
}

class _IncomingCallLaunchScreenState extends State<IncomingCallLaunchScreen> {
  @override
  void initState() {
    super.initState();
    _openIncomingCall();
  }

  void _openIncomingCall() {
    final pendingId = VorynFirebaseMessaging.pendingIncomingCallId;
    if (pendingId != null && pendingId.isNotEmpty) {
      context.go('/incoming-call/$pendingId');
    } else {
      context.go('/splash');
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
