import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_text_input.dart';
import '../v2/v2_shared.dart';

enum MockMeetingStatus { ready, ended }

class MockMeeting {
  const MockMeeting({
    required this.id,
    required this.title,
    required this.when,
    required this.time,
    required this.participants,
    required this.status,
    this.duration,
    this.joinCode = 'k7q-mzx-p2f',
  });
  final String id, title, when, time, joinCode;
  final int participants;
  final MockMeetingStatus status;
  final String? duration;
  String get link => 'voryn.app/j/$joinCode';
}

final mockMeetings = <MockMeeting>[
  const MockMeeting(
    id: 'design',
    title: 'Design Review',
    when: 'Today',
    time: '11:30 AM',
    participants: 5,
    duration: '42 min',
    status: MockMeetingStatus.ended,
  ),
  const MockMeeting(
    id: 'weekly',
    title: 'Weekly Catch-up',
    when: 'Yesterday',
    time: '4:00 PM',
    participants: 4,
    duration: '28 min',
    status: MockMeetingStatus.ended,
  ),
  const MockMeeting(
    id: 'product',
    title: 'Product Sync',
    when: 'Sep 6',
    time: '2:15 PM',
    participants: 6,
    status: MockMeetingStatus.ready,
  ),
];

class MeetingsScreen extends StatelessWidget {
  const MeetingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.vorynSpacing;
    final readyMeeting = mockMeetings
        .where((meeting) => meeting.status == MockMeetingStatus.ready)
        .firstOrNull;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(s.screen, s.md, s.screen, s.screen),
          children: [
            const VorynGlobalHeader(title: 'Meetings'),
            SizedBox(height: s.xl),
            Text(
              'Meet together,\nwithout the friction.',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(height: 1.08),
            ),
            SizedBox(height: s.sm),
            Text(
              'Start a room for your people or join one in a moment.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: s.lg),
            _MeetingActionPanel(
              onNewMeeting: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewMeetingScreen()),
              ),
              onJoinMeeting: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JoinMeetingScreen()),
              ),
            ),
            if (readyMeeting != null) ...[
              SizedBox(height: s.xl),
              Text(
                'Ready to join',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: s.sm),
              _ReadyMeetingCard(
                meeting: readyMeeting,
                onJoin: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreJoinScreen(
                      meeting: readyMeeting,
                      host: false,
                      mic: true,
                      camera: false,
                    ),
                  ),
                ),
              ),
            ],
            SizedBox(height: s.xl),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent meetings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Icon(
                  Icons.history_rounded,
                  color: context.vorynColors.iconMuted,
                ),
              ],
            ),
            SizedBox(height: s.sm),
            ...mockMeetings.map(
              (m) => Padding(
                padding: EdgeInsets.only(bottom: s.sm),
                child: _MeetingRow(
                  meeting: m,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeetingDetailsScreen(meeting: m),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingActionPanel extends StatelessWidget {
  const _MeetingActionPanel({
    required this.onNewMeeting,
    required this.onJoinMeeting,
  });

  final VoidCallback onNewMeeting;
  final VoidCallback onJoinMeeting;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(context.vorynRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MeetingAction(
              icon: Icons.add_rounded,
              label: 'New meeting',
              detail: 'Create a room',
              primary: true,
              onTap: onNewMeeting,
            ),
          ),
          Container(width: 1, height: 86, color: colors.border),
          Expanded(
            child: _MeetingAction(
              icon: Icons.keyboard_arrow_right_rounded,
              label: 'Join',
              detail: 'Use a code',
              onTap: onJoinMeeting,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingAction extends StatelessWidget {
  const _MeetingAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.vorynRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: primary ? colors.accent : colors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(icon, size: 21, color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 3),
                  Text(detail, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyMeetingCard extends StatelessWidget {
  const _ReadyMeetingCard({required this.meeting, required this.onJoin});

  final MockMeeting meeting;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return VorynCard(
      onPressed: onJoin,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(context.vorynRadii.md),
            ),
            child: SizedBox(
              height: 50,
              width: 50,
              child: Icon(
                Icons.groups_2_outlined,
                color: colors.accent,
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meeting.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${meeting.participants} people waiting',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded, color: colors.accent),
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({required this.meeting, required this.onTap});
  final MockMeeting meeting;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) {
    final colors = c.vorynColors;
    final ready = meeting.status == MockMeetingStatus.ready;
    return VorynCard(
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: ready ? colors.accentSoft : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(c.vorynRadii.md),
            ),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                ready ? Icons.videocam_rounded : Icons.history_rounded,
                color: ready ? colors.accent : colors.iconMuted,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meeting.title, style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${meeting.when} · ${meeting.time}',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${meeting.participants} people${meeting.duration == null ? '' : ' · ${meeting.duration}'}',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ready ? 'Ready' : 'Ended',
                style: Theme.of(c).textTheme.labelMedium?.copyWith(
                  color: ready ? colors.success : colors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Icon(Icons.chevron_right_rounded, color: colors.iconMuted),
            ],
          ),
        ],
      ),
    );
  }
}

class NewMeetingScreen extends StatefulWidget {
  const NewMeetingScreen({super.key});
  @override
  State<NewMeetingScreen> createState() => _NewMeetingState();
}

class _NewMeetingState extends State<NewMeetingScreen> {
  final c = TextEditingController(text: 'Design Review');
  bool mic = true, camera = false;
  String access = 'Anyone with the link';
  String? error;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'New meeting',
    child: ListView(
      padding: EdgeInsets.all(context.vorynSpacing.screen),
      children: [
        Text(
          'Create a Voryn meeting',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Set up your meeting before inviting people.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 28),
        VorynTextInput(
          label: 'Meeting name',
          controller: c,
          hintText: 'Enter meeting name',
          errorText: error,
        ),
        const SizedBox(height: 18),
        VorynSurface(
          child: Column(
            children: [
              _Setting(
                title: 'Microphone',
                detail: 'Join with your microphone ready',
                icon: Icons.mic_none_rounded,
                value: mic,
                onChanged: (v) => setState(() => mic = v),
              ),
              _Setting(
                title: 'Camera',
                detail: 'You can turn it on before joining',
                icon: Icons.videocam_outlined,
                value: camera,
                onChanged: (v) => setState(() => camera = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.link_rounded,
                  color: context.vorynColors.accent,
                ),
                title: const Text('Who can join'),
                subtitle: Text(access),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: ['Anyone with the link', 'Only invited people']
                        .map(
                          (x) => ListTile(
                            title: Text(x),
                            onTap: () {
                              setState(() => access = x);
                              Navigator.pop(context);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        VorynButton.primary(label: 'Create meeting', onPressed: _create),
      ],
    ),
  );
  void _create() {
    if (c.text.trim().isEmpty || c.text.trim().length > 60) {
      setState(() => error = 'Enter a meeting name');
      return;
    }
    final m = MockMeeting(
      id: DateTime.now().toIso8601String(),
      title: c.text.trim(),
      when: 'Today',
      time: 'Now',
      participants: 1,
      status: MockMeetingStatus.ready,
    );
    mockMeetings.insert(0, m);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingCreatedScreen(
          meeting: m,
          mic: mic,
          camera: camera,
          access: access,
        ),
      ),
    );
  }
}

class _Setting extends StatelessWidget {
  const _Setting({
    required this.title,
    required this.detail,
    required this.icon,
    required this.value,
    required this.onChanged,
  });
  final String title, detail;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext c) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    secondary: Icon(icon, color: c.vorynColors.accent),
    title: Text(title),
    subtitle: Text(detail),
    value: value,
    onChanged: onChanged,
  );
}

class MeetingCreatedScreen extends StatelessWidget {
  const MeetingCreatedScreen({
    super.key,
    required this.meeting,
    required this.mic,
    required this.camera,
    required this.access,
  });
  final MockMeeting meeting;
  final bool mic, camera;
  final String access;
  @override
  Widget build(BuildContext c) => _Page(
    title: 'Meeting ready',
    child: ListView(
      padding: EdgeInsets.all(c.vorynSpacing.screen),
      children: [
        const SizedBox(height: 35),
        Icon(
          Icons.check_circle_outline_rounded,
          color: c.vorynColors.success,
          size: 62,
        ),
        const SizedBox(height: 18),
        Text(
          'Meeting is ready',
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          meeting.title,
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.titleLarge,
        ),
        const SizedBox(height: 28),
        VorynSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Meeting link', style: Theme.of(c).textTheme.labelMedium),
              const SizedBox(height: 8),
              SelectableText(
                meeting.link,
                style: Theme.of(c).textTheme.titleMedium,
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(content: Text('Meeting link copied.')),
                    ),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                  TextButton.icon(
                    onPressed: () => ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(
                        content: Text('Share action will be connected later.'),
                      ),
                    ),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ],
              ),
              Text(access, style: Theme.of(c).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: 24),
        VorynButton.primary(
          label: 'Start meeting',
          onPressed: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => PreJoinScreen(
                meeting: meeting,
                host: true,
                mic: mic,
                camera: camera,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        VorynButton.secondary(
          label: 'Done',
          onPressed: () => Navigator.popUntil(c, (r) => r.isFirst),
        ),
      ],
    ),
  );
}

class JoinMeetingScreen extends StatefulWidget {
  const JoinMeetingScreen({super.key});
  @override
  State<JoinMeetingScreen> createState() => _JoinState();
}

class _JoinState extends State<JoinMeetingScreen> {
  final c = TextEditingController();
  String? error;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext x) => _Page(
    title: 'Join meeting',
    child: ListView(
      padding: EdgeInsets.all(x.vorynSpacing.screen),
      children: [
        const SizedBox(height: 20),
        Text(
          'Join a Voryn meeting',
          style: Theme.of(x).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter a meeting link or code.',
          style: Theme.of(x).textTheme.bodyLarge,
        ),
        const SizedBox(height: 26),
        VorynTextInput(
          label: 'Meeting link or code',
          controller: c,
          hintText: 'k7q-mzx-p2f',
          errorText: error,
          onChanged: (_) => setState(() => error = null),
        ),
        const SizedBox(height: 22),
        VorynButton.primary(label: 'Continue', onPressed: _continue),
      ],
    ),
  );
  void _continue() {
    final v = c.text.trim();
    final ok = RegExp(
      r'^(?:voryn\.app/j/)?[a-z0-9]{3}-[a-z0-9]{3}-[a-z0-9]{3}$',
    ).hasMatch(v);
    if (!ok) {
      setState(() => error = 'Enter a valid Voryn meeting link or code');
      return;
    }
    final code = v.split('/').last;
    final m =
        mockMeetings.where((x) => x.joinCode == code).firstOrNull ??
        const MockMeeting(
          id: 'generic',
          title: 'Voryn Meeting',
          when: 'Today',
          time: 'Now',
          participants: 3,
          status: MockMeetingStatus.ready,
        );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PreJoinScreen(meeting: m, host: false, mic: true, camera: false),
      ),
    );
  }
}

class PreJoinScreen extends StatefulWidget {
  const PreJoinScreen({
    super.key,
    required this.meeting,
    required this.host,
    required this.mic,
    required this.camera,
  });
  final MockMeeting meeting;
  final bool host, mic, camera;
  @override
  State<PreJoinScreen> createState() => _PreJoinState();
}

class _PreJoinState extends State<PreJoinScreen> {
  late bool mic = widget.mic;
  late bool camera = widget.camera;

  @override
  Widget build(BuildContext c) {
    return _Page(
      title: widget.meeting.title,
      child: ListView(
        padding: EdgeInsets.all(c.vorynSpacing.screen),
        children: [
          Text(
            widget.meeting.title,
            style: Theme.of(c).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.meeting.participants} participants',
            style: Theme.of(c).textTheme.bodyLarge,
          ),
          const SizedBox(height: 22),
          AspectRatio(
            aspectRatio: 1.3,
            child: VorynSurface(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (camera)
                    Icon(
                      Icons.videocam_outlined,
                      color: c.vorynColors.accent,
                      size: 40,
                    )
                  else
                    const VorynAvatar(
                      initials: 'VM',
                      size: VorynAvatarSize.large,
                    ),
                  const SizedBox(height: 12),
                  Text(camera ? 'Camera preview' : 'Camera is off'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text('Joining as', style: Theme.of(c).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text('Vikash Mishra', style: Theme.of(c).textTheme.titleLarge),
          Text('@vikash', style: Theme.of(c).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Control(
                icon: mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                label: 'Mute',
                active: mic,
                onTap: () => setState(() => mic = !mic),
              ),
              _Control(
                icon: camera
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: 'Camera',
                active: camera,
                onTap: () => setState(() => camera = !camera),
              ),
              _Control(
                icon: Icons.volume_up_rounded,
                label: 'Audio',
                active: true,
                onTap: () => _audio(c),
              ),
            ],
          ),
          const SizedBox(height: 24),
          VorynButton.primary(
            label: widget.host ? 'Start meeting' : 'Join meeting',
            onPressed: () {
              Navigator.pop(c);
              c.push(
                '/group-call/${widget.meeting.id}',
                extra: {'title': widget.meeting.title},
              );
            },
          ),
        ],
      ),
    );
  }

  void _audio(BuildContext c) => showModalBottomSheet<void>(
    context: c,
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: ['Phone', 'Speaker', 'Galaxy Buds']
          .map((x) => ListTile(title: Text(x), onTap: () => Navigator.pop(c)))
          .toList(),
    ),
  );
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => Column(
    children: [
      IconButton.filled(
        onPressed: onTap,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: active
              ? c.vorynColors.accent
              : c.vorynColors.surfaceRaised,
          minimumSize: const Size(52, 52),
        ),
        tooltip: label,
      ),
      Text(label, style: Theme.of(c).textTheme.labelSmall),
    ],
  );
}

class MeetingDetailsScreen extends StatelessWidget {
  const MeetingDetailsScreen({super.key, required this.meeting});
  final MockMeeting meeting;
  @override
  Widget build(BuildContext c) => _Page(
    title: 'Meeting Details',
    child: ListView(
      padding: EdgeInsets.all(c.vorynSpacing.screen),
      children: [
        VorynSurface(
          child: Row(
            children: [
              const VorynAvatar(initials: 'VM', size: VorynAvatarSize.large),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meeting.title,
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      meeting.status == MockMeetingStatus.ready
                          ? 'Ready'
                          : 'Ended',
                      style: Theme.of(c).textTheme.labelMedium?.copyWith(
                        color: meeting.status == MockMeetingStatus.ready
                            ? c.vorynColors.success
                            : c.vorynColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${meeting.when} · ${meeting.time}',
                      style: Theme.of(c).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Info(label: 'Duration', value: meeting.duration ?? 'Not started'),
        _Info(
          label: 'Participants',
          value: '${meeting.participants} participants',
        ),
        const _Info(label: 'Host', value: 'Vikash Mishra'),
        if (meeting.status == MockMeetingStatus.ready)
          _Info(label: 'Meeting link', value: meeting.link),
        const SizedBox(height: 18),
        VorynButton.primary(
          label: meeting.status == MockMeetingStatus.ready
              ? 'Start meeting'
              : 'Start again',
          onPressed: () => Navigator.push(
            c,
            MaterialPageRoute(builder: (_) => NewMeetingScreen()),
          ),
        ),
        const SizedBox(height: 10),
        VorynButton.secondary(
          label: 'View participants',
          onPressed: () => showModalBottomSheet<void>(
            context: c,
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Participants',
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  for (final p in [
                    'Vikash Mishra · Host',
                    'Rahul Sharma · @rahul',
                    'Aman Verma · @aman',
                    'Sarah · @sarah',
                    'Alex Johnson · @alex',
                  ])
                    ListTile(
                      leading: const VorynAvatar(
                        initials: 'VM',
                        size: VorynAvatarSize.small,
                      ),
                      title: Text(p),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => showDialog<void>(
            context: c,
            builder: (_) => AlertDialog(
              title: const Text('Remove this meeting from history?'),
              content: const Text(
                'This removes the meeting from your current local history.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    mockMeetings.removeWhere((m) => m.id == meeting.id);
                    Navigator.popUntil(c, (r) => r.isFirst);
                  },
                  child: const Text('Remove'),
                ),
              ],
            ),
          ),
          child: Text(
            'Remove history',
            style: TextStyle(color: c.vorynColors.danger),
          ),
        ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: Theme.of(c).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}
