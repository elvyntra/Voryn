import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';

enum MockCallState {
  checking,
  calling,
  ringing,
  connecting,
  connected,
  onHold,
  offline,
  busy,
  failed,
  ended,
}

class AudioCallScreen extends StatefulWidget {
  const AudioCallScreen({super.key, required this.user});
  final VorynMockUser user;
  @override
  State<AudioCallScreen> createState() => _AudioState();
}

class _AudioState extends State<AudioCallScreen> {
  MockCallState state = MockCallState.checking;
  Timer? transition, clock;
  int seconds = 0;
  bool muted = false, sharing = false;
  @override
  void initState() {
    super.initState();
    _next();
  }

  @override
  void dispose() {
    transition?.cancel();
    clock?.cancel();
    super.dispose();
  }

  void _next() {
    if (widget.user.id == '@rahul_work') {
      transition = Timer(
        const Duration(milliseconds: 700),
        () => setState(() => state = MockCallState.offline),
      );
      return;
    }
    if (widget.user.id == '@sarah') {
      transition = Timer(
        const Duration(milliseconds: 700),
        () => setState(() => state = MockCallState.busy),
      );
      return;
    }
    final next = switch (state) {
      MockCallState.checking => MockCallState.calling,
      MockCallState.calling => MockCallState.ringing,
      MockCallState.ringing => MockCallState.connecting,
      _ => MockCallState.connected,
    };
    transition = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => state = next);
      if (next == MockCallState.connected) {
        clock = Timer.periodic(
          const Duration(seconds: 1),
          (_) => setState(() => seconds++),
        );
      } else {
        _next();
      }
    });
  }

  String get status => switch (state) {
    MockCallState.checking => 'Checking availability...',
    MockCallState.calling => 'Calling...',
    MockCallState.ringing => 'Ringing...',
    MockCallState.connecting => 'Connecting...',
    MockCallState.connected => _time(seconds),
    MockCallState.onHold => 'Call on hold',
    MockCallState.offline => '${widget.user.displayName} is offline',
    MockCallState.busy => '${widget.user.displayName} is busy',
    _ => 'Call ended',
  };
  @override
  Widget build(BuildContext c) {
    final terminal =
        state == MockCallState.offline || state == MockCallState.busy;
    return _RoomShell(
      title: 'Audio call',
      top: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(c),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            tooltip: 'Minimize call',
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _addPeople(c),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'Add person',
          ),
          IconButton(
            onPressed: () => _message(c),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: 'Message',
          ),
        ],
      ),
      body: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VorynAvatar(
                  initials: widget.user.initials,
                  size: VorynAvatarSize.xlarge,
                  presenceStatus: widget.user.presence,
                ),
                const SizedBox(height: 20),
                Text(
                  widget.user.displayName,
                  style: Theme.of(c).textTheme.headlineMedium,
                ),
                Text('${widget.user.name} · ${widget.user.id}'),
                const SizedBox(height: 16),
                Text(status, style: Theme.of(c).textTheme.titleMedium),
                if (terminal)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      state == MockCallState.offline
                          ? "They aren't available for a Voryn call right now."
                          : "They're already on another call.",
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (terminal)
          Row(
            children: [
              Expanded(
                child: VorynButton.secondary(
                  label: 'Message',
                  onPressed: () => Navigator.pop(c),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VorynButton.primary(
                  label: 'Close',
                  onPressed: () => Navigator.pop(c),
                ),
              ),
            ],
          )
        else
          _Tray(
            items: [
              _Ctl(Icons.volume_up_rounded, 'Audio', () => _audio(c)),
              _Ctl(Icons.videocam_outlined, 'Video', () => _video(c)),
              _Ctl(
                muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                muted ? 'Muted' : 'Mute',
                () => setState(() => muted = !muted),
                active: !muted,
              ),
              _Ctl(
                state == MockCallState.onHold
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                state == MockCallState.onHold ? 'Resume' : 'Hold',
                () => setState(
                  () => state = state == MockCallState.onHold
                      ? MockCallState.connected
                      : MockCallState.onHold,
                ),
              ),
              _Ctl(Icons.screen_share_outlined, 'Share', () => _share(c)),
              _Ctl(
                Icons.call_end_rounded,
                'End',
                () => Navigator.pushReplacement(
                  c,
                  MaterialPageRoute(
                    builder: (_) => PostCallScreen(
                      user: widget.user,
                      video: false,
                      duration: _time(seconds),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _audio(BuildContext c) => showModalBottomSheet<void>(
    context: c,
    builder: (_) => const _AudioRoutes(),
  );
  void _video(BuildContext c) => showDialog<void>(
    context: c,
    builder: (_) => AlertDialog(
      title: const Text('Switch to video?'),
      content: const Text('Your camera will remain off until you enable it.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(c);
            Navigator.pushReplacement(
              c,
              MaterialPageRoute(
                builder: (_) => VideoCallScreen(user: widget.user),
              ),
            );
          },
          child: const Text('Switch to video'),
        ),
      ],
    ),
  );
  void _share(BuildContext c) => showDialog<void>(
    context: c,
    builder: (_) => AlertDialog(
      title: const Text('Share your screen?'),
      content: const Text(
        'People in this call will be able to see your screen.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(c);
            setState(() => sharing = true);
          },
          child: const Text('Start sharing'),
        ),
      ],
    ),
  );
  void _addPeople(BuildContext c) => showModalBottomSheet<void>(
    context: c,
    builder: (_) => const _PeopleSheet(),
  );

  void _message(BuildContext c) => showModalBottomSheet<void>(
    context: c,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => QuickMessageSheet(user: widget.user),
  );
}

class VideoPreCallScreen extends StatefulWidget {
  const VideoPreCallScreen({super.key, required this.user});
  final VorynMockUser user;
  @override
  State<VideoPreCallScreen> createState() => _PreVideoState();
}

class _PreVideoState extends State<VideoPreCallScreen> {
  bool camera = false, muted = false;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Video pre-call')),
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.all(c.vorynSpacing.screen),
        child: Column(
          children: [
            Text(
              widget.user.displayName,
              style: Theme.of(c).textTheme.headlineMedium,
            ),
            Text('${widget.user.name} · ${widget.user.id}'),
            const SizedBox(height: 22),
            Expanded(
              child: VorynSurface(
                child: Center(
                  child: camera
                      ? const Text('Camera preview')
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VorynAvatar(
                              initials: widget.user.initials,
                              size: VorynAvatarSize.xlarge,
                            ),
                            const SizedBox(height: 10),
                            const Text('Camera is off'),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Ctl(
                  camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  'Camera',
                  () => setState(() => camera = !camera),
                  active: camera,
                ),
                _Ctl(
                  muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  'Mute',
                  () => setState(() => muted = !muted),
                  active: !muted,
                ),
                _Ctl(
                  Icons.flip_camera_android_rounded,
                  'Flip',
                  camera ? () {} : null,
                  active: camera,
                ),
              ],
            ),
            const SizedBox(height: 18),
            VorynButton.primary(
              label: 'Start Video Call',
              onPressed: () => Navigator.pushReplacement(
                c,
                MaterialPageRoute(
                  builder: (_) => VideoCallScreen(
                    user: widget.user,
                    camera: camera,
                    muted: muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.user,
    this.camera = false,
    this.muted = false,
  });
  final VorynMockUser user;
  final bool camera, muted;
  @override
  State<VideoCallScreen> createState() => _VideoState();
}

class _VideoState extends State<VideoCallScreen> {
  late bool camera = widget.camera, muted = widget.muted, sharing = false;
  int seconds = 0;
  Timer? clock;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => seconds++),
    );
  }

  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _RoomShell(
    title: 'Video call',
    top: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(c),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: 'Minimize call',
        ),
        const Spacer(),
        Text(_time(seconds)),
        const Spacer(),
        IconButton(
          onPressed: () => showModalBottomSheet<void>(
            context: c,
            builder: (_) => const _PeopleSheet(),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          tooltip: 'Add person',
        ),
        IconButton(
          onPressed: () => showModalBottomSheet<void>(
            context: c,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => QuickMessageSheet(user: widget.user),
          ),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          tooltip: 'Message',
        ),
      ],
    ),
    body: [
      Expanded(
        child: VorynSurface(
          child: Center(
            child: sharing
                ? const Text("You're sharing your screen")
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VorynAvatar(
                        initials: widget.user.initials,
                        size: VorynAvatarSize.xlarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.user.displayName,
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                      const Text('Connected'),
                    ],
                  ),
          ),
        ),
      ),
      _Tray(
        items: [
          _Ctl(
            muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            'Mute',
            () => setState(() => muted = !muted),
            active: !muted,
          ),
          _Ctl(
            camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            'Camera',
            () => setState(() => camera = !camera),
            active: camera,
          ),
          _Ctl(
            Icons.flip_camera_android_rounded,
            'Flip',
            camera ? () {} : null,
            active: camera,
          ),
          _Ctl(
            Icons.volume_up_rounded,
            'Audio',
            () => showModalBottomSheet<void>(
              context: c,
              builder: (_) => const _AudioRoutes(),
            ),
          ),
          _Ctl(
            Icons.screen_share_outlined,
            sharing ? 'Stop sharing' : 'Share',
            () => setState(() => sharing = !sharing),
          ),
          _Ctl(
            Icons.call_end_rounded,
            'End',
            () => Navigator.pushReplacement(
              c,
              MaterialPageRoute(
                builder: (_) => PostCallScreen(
                  user: widget.user,
                  video: true,
                  duration: _time(seconds),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key, required this.user, this.video = false});
  final VorynMockUser user;
  final bool video;
  @override
  State<IncomingCallScreen> createState() => _IncomingState();
}

class _IncomingState extends State<IncomingCallScreen> {
  bool silenced = false;
  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: c.vorynColors.background,
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Voryn', style: TextStyle(letterSpacing: 3)),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VorynAvatar(
                    initials: widget.user.initials,
                    size: VorynAvatarSize.xlarge,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.user.displayName,
                    style: Theme.of(c).textTheme.headlineMedium,
                  ),
                  Text('${widget.user.name} · ${widget.user.id}'),
                  const SizedBox(height: 14),
                  Text(
                    widget.video
                        ? 'Incoming video call'
                        : 'Incoming audio call',
                  ),
                  if (silenced) const Text('Ringtone silenced'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: VorynButton.secondary(
                        label: 'Decline',
                        onPressed: () => Navigator.pop(c),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VorynButton.primary(
                        label: 'Accept',
                        onPressed: () => Navigator.pushReplacement(
                          c,
                          MaterialPageRoute(
                            builder: (_) => widget.video
                                ? VideoCallScreen(user: widget.user)
                                : AudioCallScreen(user: widget.user),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: VorynButton.secondary(
                        label: silenced ? 'Silenced' : 'Silence',
                        onPressed: () => setState(() => silenced = true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VorynButton.secondary(
                        label: 'Message',
                        onPressed: () => showModalBottomSheet<void>(
                          context: c,
                          builder: (_) => const _QuickReply(),
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

class MockMeetingRoomScreen extends StatefulWidget {
  const MockMeetingRoomScreen({
    super.key,
    required this.title,
    this.participants = 5,
    this.host = true,
  });
  final String title;
  final int participants;
  final bool host;
  @override
  State<MockMeetingRoomScreen> createState() => _RoomState();
}

class _RoomState extends State<MockMeetingRoomScreen> {
  bool muted = false, camera = false, sharing = false;
  @override
  Widget build(BuildContext c) => _RoomShell(
    title: widget.title,
    top: Row(
      children: [
        IconButton(
          onPressed: () => _leave(c),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: 'Minimize meeting',
        ),
        Expanded(
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          onPressed: () => showModalBottomSheet<void>(
            context: c,
            builder: (_) => const _PeopleSheet(title: 'Participants'),
          ),
          icon: const Icon(Icons.groups_outlined),
          tooltip: 'Participants',
        ),
      ],
    ),
    body: [
      Expanded(
        child: VorynSurface(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const VorynAvatar(initials: 'RS', size: VorynAvatarSize.xlarge),
                const SizedBox(height: 12),
                const Text('Rahul Sharma'),
                Text('${widget.participants} participants'),
              ],
            ),
          ),
        ),
      ),
      _Tray(
        items: [
          _Ctl(
            Icons.mic_rounded,
            'Mute',
            () => setState(() => muted = !muted),
            active: !muted,
          ),
          _Ctl(
            Icons.videocam_outlined,
            'Camera',
            () => setState(() => camera = !camera),
            active: camera,
          ),
          _Ctl(Icons.flip_camera_android_rounded, 'Flip', null, active: camera),
          _Ctl(
            Icons.volume_up_rounded,
            'Audio',
            () => showModalBottomSheet<void>(
              context: c,
              builder: (_) => const _AudioRoutes(),
            ),
          ),
          _Ctl(
            Icons.screen_share_outlined,
            sharing ? 'Stop sharing' : 'Share',
            () => setState(() => sharing = !sharing),
          ),
          _Ctl(
            Icons.call_end_rounded,
            widget.host ? 'End' : 'Leave',
            () => _leave(c),
            danger: true,
          ),
        ],
      ),
    ],
  );
  void _leave(BuildContext c) => showModalBottomSheet<void>(
    context: c,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Leave meeting'),
            onTap: () => Navigator.popUntil(c, (r) => r.isFirst),
          ),
          if (widget.host)
            ListTile(
              title: const Text('End meeting for everyone'),
              onTap: () => Navigator.popUntil(c, (r) => r.isFirst),
            ),
          ListTile(title: const Text('Cancel'), onTap: () => Navigator.pop(c)),
        ],
      ),
    ),
  );
}

class PostCallScreen extends StatelessWidget {
  const PostCallScreen({
    super.key,
    required this.user,
    required this.video,
    required this.duration,
  });
  final VorynMockUser user;
  final bool video;
  final String duration;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Call ended')),
    body: ListView(
      padding: EdgeInsets.all(c.vorynSpacing.screen),
      children: [
        const SizedBox(height: 30),
        Center(
          child: VorynAvatar(
            initials: user.initials,
            size: VorynAvatarSize.xlarge,
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            user.displayName,
            style: Theme.of(c).textTheme.headlineMedium,
          ),
        ),
        Center(child: Text('${user.name} · ${user.id}')),
        const SizedBox(height: 20),
        Center(child: Text('Duration: $duration')),
        const SizedBox(height: 24),
        VorynButton.primary(
          label: 'Call again',
          onPressed: () => Navigator.pushReplacement(
            c,
            MaterialPageRoute(
              builder: (_) => video
                  ? VideoPreCallScreen(user: user)
                  : AudioCallScreen(user: user),
            ),
          ),
        ),
        const SizedBox(height: 10),
        VorynButton.secondary(label: 'Done', onPressed: () => Navigator.pop(c)),
      ],
    ),
  );
}

class _RoomShell extends StatelessWidget {
  const _RoomShell({
    required this.title,
    required this.top,
    required this.body,
  });
  final String title;
  final Widget top;
  final List<Widget> body;
  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: c.vorynColors.background,
    body: SafeArea(
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.all(10), child: top),
          ...body,
        ],
      ),
    ),
  );
}

class _Tray extends StatelessWidget {
  const _Tray({required this.items});
  final List<Widget> items;
  @override
  Widget build(BuildContext c) => VorynSurface(
    padding: const EdgeInsets.all(12),
    child: GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.15,
      children: items,
    ),
  );
}

class _Ctl extends StatelessWidget {
  const _Ctl(
    this.icon,
    this.label,
    this.onTap, {
    this.active = true,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active, danger;
  @override
  Widget build(BuildContext c) => Semantics(
    label: label,
    button: true,
    enabled: onTap != null,
    child: Column(
      children: [
        IconButton.filled(
          onPressed: onTap,
          icon: Icon(icon),
          tooltip: label,
          style: IconButton.styleFrom(
            backgroundColor: danger
                ? c.vorynColors.danger
                : active
                ? c.vorynColors.accent
                : c.vorynColors.surfaceRaised,
            minimumSize: const Size(52, 52),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(c).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

class _AudioRoutes extends StatelessWidget {
  const _AudioRoutes();
  @override
  Widget build(BuildContext c) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: ['Phone', 'Speaker', 'Galaxy Buds']
          .map(
            (x) => ListTile(
              title: Text(x),
              trailing: x == 'Speaker' ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(c),
            ),
          )
          .toList(),
    ),
  );
}

class _QuickReply extends StatelessWidget {
  const _QuickReply();
  @override
  Widget build(BuildContext c) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final x in [
          "Can't talk right now.",
          "I'll call you back.",
          'Can I call you later?',
          "I'm in a meeting.",
          'Custom message',
        ])
          ListTile(
            title: Text(x),
            onTap: () {
              Navigator.pop(c);
              ScaffoldMessenger.of(
                c,
              ).showSnackBar(const SnackBar(content: Text('Reply sent')));
            },
          ),
      ],
    ),
  );
}

class _PeopleSheet extends StatelessWidget {
  const _PeopleSheet({this.title = 'Add people'});
  final String title;
  @override
  Widget build(BuildContext c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final u in mockVorynUsers.take(3))
            ListTile(
              leading: VorynAvatar(
                initials: u.initials,
                size: VorynAvatarSize.small,
              ),
              title: Text(u.displayName),
              trailing: TextButton(
                onPressed: () => ScaffoldMessenger.of(
                  c,
                ).showSnackBar(const SnackBar(content: Text('Invited ✓'))),
                child: const Text('+ Add'),
              ),
            ),
        ],
      ),
    ),
  );
}

String _time(int s) =>
    '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
