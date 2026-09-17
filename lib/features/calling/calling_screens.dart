import 'package:flutter/material.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../connect/mock_voryn_state.dart';
import 'call_request_screen.dart';
import 'group_call_screen.dart';
import 'incoming_call_screen.dart' as stitch_incoming;

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

class AudioCallScreen extends StatelessWidget {
  const AudioCallScreen({super.key, required this.user, this.callId});
  final VorynMockUser user;
  final String? callId;

  @override
  Widget build(BuildContext context) {
    return CallRequestScreen(user: user, video: false, existingCallId: callId);
  }
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

class VideoCallScreen extends StatelessWidget {
  const VideoCallScreen({
    super.key,
    required this.user,
    this.camera = false,
    this.muted = false,
    this.callId,
  });
  final VorynMockUser user;
  final bool camera;
  final bool muted;
  final String? callId;

  @override
  Widget build(BuildContext context) {
    return CallRequestScreen(user: user, video: true, existingCallId: callId);
  }
}

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key, required this.user, this.video = false});
  final VorynMockUser user;
  final bool video;

  @override
  Widget build(BuildContext context) {
    final callId = 'call-${DateTime.now().millisecondsSinceEpoch}';
    return stitch_incoming.IncomingCallScreen(
      callId: callId,
      initialUser: user,
    );
  }
}

class MockMeetingRoomScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final callId = 'meeting-${DateTime.now().millisecondsSinceEpoch}';
    return GroupCallScreen(
      callId: callId,
      title: title,
      initialParticipants: participants,
    );
  }
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

class _Ctl extends StatelessWidget {
  const _Ctl(this.icon, this.label, this.onTap, {this.active = true});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
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
            backgroundColor: active
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
