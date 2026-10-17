import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import 'multi_call_coordinator.dart';
import 'voryn_call_runtime_coordinator.dart';
import 'voryn_call_service.dart';
import 'voryn_livekit_service.dart';
import 'widgets/add_participant_sheet.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_top_bar.dart';

class GroupCallParticipant {
  final String id;
  final String name;
  final String initials;
  final bool isYou;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeaking;
  final livekit.VideoTrack? videoTrack;
  final Color statusColor;

  const GroupCallParticipant({
    required this.id,
    required this.name,
    required this.initials,
    this.isYou = false,
    this.isMuted = false,
    this.isCameraOff = true,
    this.isSpeaking = false,
    this.videoTrack,
    this.statusColor = const Color(0xFF22C55E),
  });

  GroupCallParticipant copyWith({
    String? id,
    String? name,
    String? initials,
    bool? isYou,
    bool? isMuted,
    bool? isCameraOff,
    bool? isSpeaking,
    livekit.VideoTrack? videoTrack,
    Color? statusColor,
  }) {
    return GroupCallParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      isYou: isYou ?? this.isYou,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      videoTrack: videoTrack ?? this.videoTrack,
      statusColor: statusColor ?? this.statusColor,
    );
  }
}

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({
    super.key,
    required this.callId,
    this.title = 'Conference',
    this.initialParticipants = 2,
    this.activeSpeakerName,
    this.participants,
    this.existingSession,
    this.initialDuration,
    this.isInitiator,
  });

  final String callId;
  final String title;
  final int initialParticipants;
  final String? activeSpeakerName;
  final List<GroupCallParticipant>? participants;
  final VorynLiveKitSession? existingSession;
  final Duration? initialDuration;
  final bool? isInitiator;

  @override
  State<GroupCallScreen> createState() => GroupCallScreenState();
}

class GroupCallScreenState extends State<GroupCallScreen> {
  Timer? _timer;
  late final ValueNotifier<Duration> _durationNotifier;

  VorynLiveKitSession? _session;
  RealtimeChannel? _callSubscription;
  bool _listenerAttached = false;

  bool _controlsVisible = true;
  bool _muted = false;
  bool _cameraEnabled = true;
  bool _speakerOn = true;
  bool _screenSharing = false;
  String? _fullscreenParticipantId;

  bool _ending = false;
  bool _ended = false;
  Future<void>? _teardownFuture;

  late String _currentUserName;
  late String _currentUserInitials;

  List<GroupCallParticipant>? _customParticipants;

  bool get isInitiator =>
      widget.isInitiator ??
      MultiCallCoordinator.instance.isCallInitiator(widget.callId);

  bool get isConference =>
      MultiCallCoordinator.instance.isConference(widget.callId) ||
      widget.participants != null ||
      widget.callId.startsWith('conf');

  bool get isReconnecting =>
      _session != null &&
      !_session!.isConnected &&
      !_ended &&
      !_ending;

  @override
  void initState() {
    super.initState();
    _session = widget.existingSession ??
        MultiCallCoordinator.instance.sessionsByCallId[widget.callId];
    _attachRoomListener();
    _subscribeToCallEvents();

    final startDuration = widget.initialDuration ??
        (VorynCallRuntimeCoordinator.isCallActive(widget.callId)
            ? VorynCallRuntimeCoordinator.forCall(widget.callId).currentDuration
            : Duration.zero);
    _durationNotifier = ValueNotifier(startDuration);

    final user = VorynBackend.client?.auth.currentUser;
    final metaName = user?.userMetadata?['full_name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      _currentUserName = metaName.trim();
    } else if (user?.email != null && user!.email!.isNotEmpty) {
      _currentUserName = user.email!.split('@').first;
    } else {
      _currentUserName = 'You';
    }

    final parts = _currentUserName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    _currentUserInitials = parts.isNotEmpty
        ? parts.map((p) => p[0].toUpperCase()).join()
        : 'Y';

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ending && !_ended) {
        _durationNotifier.value += const Duration(seconds: 1);
      }
    });

    if (widget.participants != null) {
      _customParticipants = List.of(widget.participants!);
    }
  }

  void _subscribeToCallEvents() {
    _callSubscription?.unsubscribe();
    _callSubscription = const VorynCallService().subscribeToCallState(
      widget.callId,
      (status) {
        debugPrint(
          '[CALL ${widget.callId}] realtime remote terminal event in group call ($status)',
        );
        _teardownFuture ??= _performTeardown(isLocalInitiator: false);
      },
    );
  }

  void _attachRoomListener() {
    if (_listenerAttached || _session == null) return;
    try {
      _listenerAttached = true;
      _session!.room.addListener(_onRoomChanged);
    } catch (_) {}
  }

  void _detachRoomListener() {
    if (!_listenerAttached) return;
    _listenerAttached = false;
    try {
      _session?.room.removeListener(_onRoomChanged);
    } catch (_) {}
  }

  void _onRoomChanged() {
    if (!mounted || _ending || _ended) return;
    setState(() {});
  }

  String _getInitials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    return parts.isNotEmpty ? parts.map((p) => p[0].toUpperCase()).join() : 'M';
  }

  @visibleForTesting
  void addTestParticipant(GroupCallParticipant p) {
    setState(() {
      _customParticipants = List.of(_getParticipants())..add(p);
    });
  }

  @visibleForTesting
  void removeTestParticipant(String id) {
    setState(() {
      _customParticipants = List.of(_getParticipants())
        ..removeWhere((p) => p.id == id);
    });
  }

  List<GroupCallParticipant> _getParticipants() {
    if (_customParticipants != null && _customParticipants!.isNotEmpty) {
      return _customParticipants!;
    }

    final list = <GroupCallParticipant>[];
    if (_session != null) {
      try {
        final remotes = _session!.room.remoteParticipants;
        if (remotes.isNotEmpty) {
          for (final p in remotes.values) {
            final name = p.name.isNotEmpty
                ? p.name
                : (p.identity.isNotEmpty ? p.identity : 'Participant');

            livekit.VideoTrack? remoteTrack;
            for (final pub in p.videoTrackPublications) {
              if (pub.track is livekit.VideoTrack && pub.subscribed && !pub.muted) {
                remoteTrack = pub.track as livekit.VideoTrack;
                break;
              }
            }

            final isSpeaking = p.isSpeaking ||
                (_session!.room.activeSpeakers.contains(p));

            list.add(
              GroupCallParticipant(
                id: p.sid,
                name: name,
                initials: _getInitials(name),
                statusColor: const Color(0xFF22C55E),
                isMuted: p.isMuted,
                isCameraOff: remoteTrack == null,
                isSpeaking: isSpeaking,
                videoTrack: remoteTrack,
              ),
            );
          }
        }
      } catch (_) {}
    }

    if (list.isEmpty) {
      final speaker = widget.activeSpeakerName ??
          (widget.title.isNotEmpty && widget.title != 'Group Meeting'
              ? widget.title
              : 'Host');
      list.add(
        GroupCallParticipant(
          id: 'speaker',
          name: speaker,
          initials: _getInitials(speaker),
          statusColor: const Color(0xFF22C55E),
          isMuted: false,
          isCameraOff: true,
        ),
      );
    }

    // Local participant
    livekit.VideoTrack? localTrack;
    if (_cameraEnabled && _session != null) {
      try {
        localTrack = _session!.localVideoTrack;
      } catch (_) {}
    }

    list.add(
      GroupCallParticipant(
        id: 'me',
        name: '$_currentUserName (You)',
        initials: _currentUserInitials,
        statusColor: const Color(0xFF22C55E),
        isMuted: _muted,
        isCameraOff: !_cameraEnabled,
        isYou: true,
        videoTrack: localTrack,
      ),
    );

    return list;
  }

  void _toggleControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = !_controlsVisible);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    try {
      await _session?.setMicrophoneEnabled(!next);
    } catch (_) {}
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraEnabled;
    setState(() => _cameraEnabled = next);
    try {
      await _session?.setCameraEnabled(next);
    } catch (_) {}
  }

  Future<void> _flipCamera() async {
    try {
      await _session?.room.localParticipant?.setCameraEnabled(true);
    } catch (_) {}
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    setState(() => _speakerOn = next);
    try {
      await _session?.setSpeakerEnabled(next);
    } catch (_) {}
  }

  Future<void> _toggleShare() async {
    if (_ending || _ended) return;
    if (_session == null) return;
    if (_screenSharing) {
      await _session!.setScreenShareEnabled(false);
      setState(() => _screenSharing = false);
    } else {
      if (_session!.hasRemoteScreenShare) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Someone else is already sharing screen'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final success = await _session!.setScreenShareEnabled(true);
      if (mounted) {
        if (success) {
          setState(() => _screenSharing = true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Screen share cancelled or unavailable.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _leaveCall() async {
    debugPrint('[CALL ${widget.callId}] Leave Call pressed');
    await _endCall(endForEveryone: false);
  }

  Future<void> _confirmEndForEveryone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17171a),
        title: const Text(
          'End Call for Everyone?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'This will disconnect all participants from the conference.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End for Everyone'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _endCall(endForEveryone: true);
    }
  }

  Future<void> _endCall({bool endForEveryone = false}) {
    if (_ending || _ended) return Future<void>.value();
    if (mounted) {
      setState(() => _ending = true);
    } else {
      _ending = true;
    }
    debugPrint(
      '[CALL ${widget.callId}] local End pressed in group call (endForEveryone=$endForEveryone)',
    );
    return _teardownFuture ??= _performTeardown(
      isLocalInitiator: true,
      endForEveryone: endForEveryone,
    );
  }

  Future<void> _performTeardown({
    bool isLocalInitiator = false,
    bool endForEveryone = false,
  }) async {
    if (_ended) return;
    _ending = true;
    debugPrint('[CALL ${widget.callId}] group teardown begin');
    _timer?.cancel();
    _detachRoomListener();
    _callSubscription?.unsubscribe();

    if (isLocalInitiator && endForEveryone) {
      try {
        await const VorynCallService().end(widget.callId);
        debugPrint('[CALL ${widget.callId}] group call ended for everyone');
      } catch (_) {}
    }

    try {
      await _session?.disconnect();
      debugPrint('[CALL ${widget.callId}] group room disconnect complete');
    } catch (_) {}

    _ended = true;
    _session = null;

    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) {
      debugPrint('[CALL ${widget.callId}] group route exit (locked)');
      await LockScreenService.moveCallTaskBehindKeyguard();
      return;
    }

    debugPrint('[CALL ${widget.callId}] group route exit');
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        final client = VorynBackend.client;
        if (client?.auth.currentUser != null) {
          context.go('/meetings');
        } else {
          context.go('/welcome');
        }
      }
    }
  }

  void _minimize() async {
    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) return;

    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        final client = VorynBackend.client;
        if (client?.auth.currentUser != null) {
          context.go('/meetings');
        } else {
          context.go('/welcome');
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _detachRoomListener();
    _callSubscription?.unsubscribe();
    _durationNotifier.dispose();
    super.dispose();
  }

  String _formatTimer(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showParticipantListSheet(BuildContext context) {
    final participants = _getParticipants();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17171a),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
              maxWidth: 480,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Participants (${participants.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: participants.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (ctx, i) {
                        final p = participants[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF202024),
                            child: Text(
                              p.initials,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (p.isYou) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF064E3B),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'YOU',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFD1FAE5),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p.isSpeaking) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Speaking',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF22C55E),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Icon(
                                p.isMuted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                size: 16,
                                color: p.isMuted
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFF22C55E),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                p.isCameraOff
                                    ? Icons.videocam_off_rounded
                                    : Icons.videocam_rounded,
                                size: 16,
                                color: p.isCameraOff
                                    ? Colors.white38
                                    : Colors.white70,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_rounded, size: 16),
                      label: const Text('Add Participant'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        AddParticipantSheet.show(context, callId: widget.callId);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPersistentStatusPill(
    BuildContext context,
    List<GroupCallParticipant> participants,
    String timeString,
  ) {
    return GestureDetector(
      onTap: _toggleControls,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReconnecting) ...[
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Reconnecting…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber,
                ),
              ),
            ] else ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${participants.length} in call · $timeString',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantStage(
    BuildContext context,
    List<GroupCallParticipant> participants,
    bool hasAnyVideo,
  ) {
    if (participants.length >= 3 &&
        _fullscreenParticipantId != null &&
        participants.any((p) => p.id == _fullscreenParticipantId)) {
      return _buildFullscreenParticipantStage(context, participants);
    }

    if (hasAnyVideo) {
      return _buildVideoGrid(context, participants);
    } else {
      return _buildAudioGrid(context, participants);
    }
  }

  Widget _buildFullscreenParticipantStage(
    BuildContext context,
    List<GroupCallParticipant> participants,
  ) {
    final dominant = participants.firstWhere(
      (p) => p.id == _fullscreenParticipantId,
      orElse: () => participants.first,
    );
    final otherParticipants =
        participants.where((p) => p.id != dominant.id).toList();

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _buildVideoTile(
            context,
            dominant,
            isFullscreen: true,
          ),
        ),

        // "All Screens Equal" toggle button
        Positioned(
          top: _controlsVisible ? 72 : 24,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('equal_screen_btn'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _fullscreenParticipantId = null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF008F66).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      size: 16,
                      color: Color(0xFF22C55E),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'All Screens Equal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Dynamic PiP strip for other participants
        Positioned(
          left: 12,
          right: 12,
          bottom: _controlsVisible ? 120 : 24,
          height: 100,
          child: ListView.separated(
            key: const Key('group_pip_deck'),
            scrollDirection: Axis.horizontal,
            itemCount: otherParticipants.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = otherParticipants[i];
              return GestureDetector(
                key: ValueKey('pip_switch_${p.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _fullscreenParticipantId = p.id;
                  });
                },
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF17171a),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.isSpeaking
                          ? const Color(0xFF22C55E)
                          : Colors.white24,
                      width: p.isSpeaking ? 2.0 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (p.videoTrack != null && !p.isCameraOff)
                        ConferenceVideoTrackSurface(
                          track: p.videoTrack!,
                          mirrorMode: p.isYou
                              ? livekit.VideoViewMirrorMode.mirror
                              : livekit.VideoViewMirrorMode.off,
                          fit: livekit.VideoViewFit.cover,
                        )
                      else
                        _buildAvatarPlaceholder(context, p),

                      Positioned(
                        left: 4,
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Icon(
                                p.isMuted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                size: 10,
                                color: p.isMuted
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFF22C55E),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicEqualGrid(
    BuildContext context,
    List<GroupCallParticipant> participants, {
    bool isAudioOnly = false,
  }) {
    final count = participants.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final totalW = constraints.maxWidth;
        final totalH = constraints.maxHeight;
        const gap = 8.0;

        if (count == 3) {
          if (isLandscape) {
            final colW = (totalW - (2 * gap)) / 3;
            return Row(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: colW,
                    height: totalH,
                    child: isAudioOnly
                        ? _buildAudioTile(context, participants[i], canFullscreen: true)
                        : _buildVideoTile(context, participants[i], canFullscreen: true),
                  ),
                ],
              ],
            );
          } else {
            final rowH = (totalH - (2 * gap)) / 3;
            return Column(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(height: gap),
                  SizedBox(
                    width: totalW,
                    height: rowH,
                    child: isAudioOnly
                        ? _buildAudioTile(context, participants[i], canFullscreen: true)
                        : _buildVideoTile(context, participants[i], canFullscreen: true),
                  ),
                ],
              ],
            );
          }
        }

        if (count == 4) {
          final rowH = (totalH - gap) / 2;
          final colW = (totalW - gap) / 2;
          return Column(
            children: [
              SizedBox(
                height: rowH,
                child: Row(
                  children: [
                    SizedBox(
                      width: colW,
                      height: rowH,
                      child: isAudioOnly
                          ? _buildAudioTile(context, participants[0], canFullscreen: true)
                          : _buildVideoTile(context, participants[0], canFullscreen: true),
                    ),
                    const SizedBox(width: gap),
                    SizedBox(
                      width: colW,
                      height: rowH,
                      child: isAudioOnly
                          ? _buildAudioTile(context, participants[1], canFullscreen: true)
                          : _buildVideoTile(context, participants[1], canFullscreen: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              SizedBox(
                height: rowH,
                child: Row(
                  children: [
                    SizedBox(
                      width: colW,
                      height: rowH,
                      child: isAudioOnly
                          ? _buildAudioTile(context, participants[2], canFullscreen: true)
                          : _buildVideoTile(context, participants[2], canFullscreen: true),
                    ),
                    const SizedBox(width: gap),
                    SizedBox(
                      width: colW,
                      height: rowH,
                      child: isAudioOnly
                          ? _buildAudioTile(context, participants[3], canFullscreen: true)
                          : _buildVideoTile(context, participants[3], canFullscreen: true),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final cols = isLandscape ? 3 : 2;
        final rows = (count + cols - 1) ~/ cols;
        final rowH = (totalH - (rows - 1) * gap) / rows;
        final effectiveRowH = rowH < 100 ? 120.0 : rowH;
        final useScroll = rowH < 100;

        Widget content = Column(
          children: [
            for (int r = 0; r < rows; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              SizedBox(
                height: effectiveRowH,
                child: Row(
                  children: [
                    for (int c = 0; c < cols; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      Expanded(
                        child: (r * cols + c < count)
                            ? (isAudioOnly
                                ? _buildAudioTile(
                                    context,
                                    participants[r * cols + c],
                                    canFullscreen: true,
                                  )
                                : _buildVideoTile(
                                    context,
                                    participants[r * cols + c],
                                    canFullscreen: true,
                                  ))
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );

        if (useScroll) {
          return SingleChildScrollView(child: content);
        }
        return content;
      },
    );
  }

  Widget _buildVideoGrid(
    BuildContext context,
    List<GroupCallParticipant> participants,
  ) {
    final count = participants.length;
    if (count == 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Expanded(child: _buildVideoTile(context, participants[0])),
            const SizedBox(height: 8),
            Expanded(child: _buildVideoTile(context, participants[1])),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _buildDynamicEqualGrid(context, participants, isAudioOnly: false),
      );
    }
  }

  Widget _buildAudioGrid(
    BuildContext context,
    List<GroupCallParticipant> participants,
  ) {
    final count = participants.length;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = (count <= 2) ? 1 : (screenWidth > 700 ? 3 : 2);
    final isSingleCol = crossAxisCount == 1;

    if (count <= 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: isSingleCol ? 2.2 : 1.1,
          ),
          itemBuilder: (context, i) => _buildAudioTile(context, participants[i]),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _buildDynamicEqualGrid(context, participants, isAudioOnly: true),
      );
    }
  }

  Widget _buildVideoTile(
    BuildContext context,
    GroupCallParticipant p, {
    bool canFullscreen = false,
    bool isFullscreen = false,
  }) {
    final hasTrack = p.videoTrack != null && !p.isCameraOff;

    final tile = Container(
      key: ValueKey('tile_${p.id}'),
      decoration: BoxDecoration(
        color: const Color(0xFF17171a),
        borderRadius: BorderRadius.circular(isFullscreen ? 0 : 16),
        border: isFullscreen
            ? null
            : Border.all(
                color: p.isSpeaking
                    ? const Color(0xFF22C55E)
                    : (p.isYou
                        ? const Color(0xFF008F66).withValues(alpha: 0.35)
                        : Colors.white10),
                width: p.isSpeaking ? 2.0 : 1.0,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasTrack)
            ConferenceVideoTrackSurface(
              track: p.videoTrack!,
              key: ValueKey('video_${p.id}'),
              mirrorMode: p.isYou
                  ? livekit.VideoViewMirrorMode.mirror
                  : livekit.VideoViewMirrorMode.off,
              fit: livekit.VideoViewFit.cover,
            )
          else
            _buildAvatarPlaceholder(context, p),

          if (p.isSpeaking)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq_rounded, size: 12, color: Color(0xFF22C55E)),
                    SizedBox(width: 4),
                    Text(
                      'Speaking',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (canFullscreen)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                key: ValueKey('fullscreen_btn_${p.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _fullscreenParticipantId = p.id;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    p.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 13,
                    color: p.isMuted
                        ? const Color(0xFFF87171)
                        : const Color(0xFF22C55E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return tile;
  }

  Widget _buildAudioTile(
    BuildContext context,
    GroupCallParticipant p, {
    bool canFullscreen = false,
  }) {
    final tile = Container(
      key: ValueKey('audio_tile_${p.id}'),
      decoration: BoxDecoration(
        color: const Color(0xFF17171a),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.isSpeaking
              ? const Color(0xFF22C55E)
              : (p.isYou
                  ? const Color(0xFF008F66).withValues(alpha: 0.35)
                  : Colors.white10),
          width: p.isSpeaking ? 2.0 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          if (canFullscreen)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                key: ValueKey('fullscreen_btn_${p.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _fullscreenParticipantId = p.id;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  if (p.isSpeaking)
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF22C55E), width: 2),
                      ),
                    ),
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF202024),
                    child: Text(
                      p.initials,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    p.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 14,
                    color: p.isMuted
                        ? const Color(0xFFF87171)
                        : const Color(0xFF22C55E),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return tile;
  }

  Widget _buildAvatarPlaceholder(BuildContext context, GroupCallParticipant p) {
    return Container(
      color: const Color(0xFF17171a),
      alignment: Alignment.center,
      child: CircleAvatar(
        radius: 36,
        backgroundColor: const Color(0xFF202024),
        child: Text(
          p.initials,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildControlsTray(BuildContext context) {
    return CallControlTray(
      row1: [
        CallControlButton(
          icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _muted ? 'Muted' : 'Mute',
          isActive: _muted,
          activeColor: const Color(0xFFDC2626),
          onTap: _toggleMute,
        ),
        CallControlButton(
          icon: _cameraEnabled
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          label: _cameraEnabled ? 'Camera' : 'Camera Off',
          isActive: _cameraEnabled,
          activeColor: const Color(0xFF22C55E),
          onTap: _toggleCamera,
        ),
        CallControlButton(
          icon: Icons.flip_camera_android_rounded,
          label: 'Flip',
          onTap: _flipCamera,
        ),
        CallControlButton(
          icon: _speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
          label: _speakerOn ? 'Speaker' : 'Earpiece',
          isActive: _speakerOn,
          onTap: _toggleSpeaker,
        ),
      ],
      row2: [
        CallControlButton(
          icon: Icons.screen_share_outlined,
          label: _screenSharing ? 'Stop' : 'Share',
          isActive: _screenSharing,
          onTap: _toggleShare,
        ),
        CallControlButton(
          icon: Icons.people_outline_rounded,
          label: 'People',
          onTap: () => _showParticipantListSheet(context),
        ),
        CallControlButton(
          icon: Icons.call_end_rounded,
          label: isConference ? 'Leave' : 'End',
          isDestructive: true,
          onTap: _leaveCall,
        ),
        if (isInitiator)
          CallControlButton(
            icon: Icons.cancel_presentation_rounded,
            label: 'End All',
            isDestructive: true,
            onTap: _confirmEndForEveryone,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[BOOT] GroupCallScreen build');
    final participants = _getParticipants();
    final hasAnyVideo = participants.any(
      (p) => p.videoTrack != null && !p.isCameraOff,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0b0b0d),
      body: SafeArea(
        child: Stack(
          children: [
            // Interactive Participant Stage (tap toggles controls)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Column(
                  children: [
                    const SizedBox(height: 70), // Spacing for top header
                    Expanded(
                      child: _buildParticipantStage(
                        context,
                        participants,
                        hasAnyVideo,
                      ),
                    ),
                    const SizedBox(height: 180), // Spacing for bottom controls
                  ],
                ),
              ),
            ),

            // Persistent Status Pill (Visible when controls hidden)
            ValueListenableBuilder<Duration>(
              valueListenable: _durationNotifier,
              builder: (context, duration, _) {
                final timeString = _formatTimer(duration);
                return Align(
                  alignment: Alignment.topCenter,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: _controlsVisible,
                      child: _buildPersistentStatusPill(
                        context,
                        participants,
                        timeString,
                      ),
                    ),
                  ),
                );
              },
            ),

            // Top Header Overlay (animated hide/show)
            Align(
              alignment: Alignment.topCenter,
              child: AnimatedSlide(
                offset: _controlsVisible ? Offset.zero : const Offset(0, -1.2),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: _durationNotifier,
                      builder: (context, duration, _) {
                        final timeString = _formatTimer(duration);
                        return CallTopBar(
                          onMinimize: _minimize,
                          centerWidget: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${widget.title}  $timeString',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              GestureDetector(
                                onTap: () => _showParticipantListSheet(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF202024),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isReconnecting) ...[
                                        const SizedBox(
                                          width: 9,
                                          height: 9,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: Colors.amber,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Reconnecting…',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.amber,
                                          ),
                                        ),
                                      ] else ...[
                                        const Icon(
                                          Icons.groups_outlined,
                                          size: 13,
                                          color: Color(0xFF10B981),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${participants.length} in call  ›',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onAddParticipant: () {
                            AddParticipantSheet.show(
                              context,
                              callId: widget.callId,
                              onParticipantInvited: (vorynId) {
                                debugPrint(
                                  '[CALL ${widget.callId}] participant invited: $vorynId',
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Controls Overlay (animated hide/show)
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                offset: _controlsVisible ? Offset.zero : const Offset(0, 1.2),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildControlsTray(context),
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

class ConferenceVideoTrackSurface extends StatelessWidget {
  const ConferenceVideoTrackSurface({
    super.key,
    required this.track,
    required this.mirrorMode,
    this.fit = livekit.VideoViewFit.cover,
  });

  final livekit.VideoTrack track;
  final livekit.VideoViewMirrorMode mirrorMode;
  final livekit.VideoViewFit fit;

  @override
  Widget build(BuildContext context) {
    if (track is! livekit.LocalVideoTrack && track is! livekit.RemoteVideoTrack) {
      return Container(
        color: const Color(0xFF17171a),
        child: Center(
          child: Icon(
            mirrorMode == livekit.VideoViewMirrorMode.mirror
                ? Icons.flip_camera_android_rounded
                : Icons.videocam_rounded,
            color: Colors.white54,
          ),
        ),
      );
    }
    return IgnorePointer(
      child: livekit.VideoTrackRenderer(
        track,
        mirrorMode: mirrorMode,
        fit: fit,
      ),
    );
  }
}
