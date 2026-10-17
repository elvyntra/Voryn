import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import '../calling/group_call_screen.dart';
import '../calling/voryn_livekit_service.dart';
import '../calling/widgets/call_controls.dart';
import '../calling/widgets/call_top_bar.dart';
import '../calling/widgets/screen_share_banner.dart';
import '../calling/widgets/video_pip.dart';
import 'models/meeting_models.dart';
import 'services/voryn_meeting_service.dart';
import 'widgets/meeting_invite_sheet.dart';

enum MeetingConnectionState {
  connecting,
  connected,
  reconnecting,
  failed,
  ended,
}

class MeetingRoomScreen extends StatefulWidget {
  const MeetingRoomScreen({
    super.key,
    required this.joinedMeeting,
    this.existingSession,
    this.liveKitService = const VorynLiveKitService(),
    this.meetingService,
    this.customParticipants,
    this.onMeetingEnded,
  });

  final VorynJoinedMeeting joinedMeeting;
  final VorynLiveKitSession? existingSession;
  final VorynLiveKitService liveKitService;
  final VorynMeetingService? meetingService;
  final List<GroupCallParticipant>? customParticipants;
  final VoidCallback? onMeetingEnded;

  @override
  State<MeetingRoomScreen> createState() => MeetingRoomScreenState();
}

class MeetingRoomScreenState extends State<MeetingRoomScreen>
    with WidgetsBindingObserver {
  late MeetingConnectionState _state;
  String? _errorMessage;

  VorynLiveKitSession? _session;
  RealtimeChannel? _meetingChannel;
  bool _listenerAttached = false;

  Timer? _timer;
  late final ValueNotifier<Duration> _durationNotifier;

  bool _controlsVisible = true;
  late bool _muted;
  late bool _cameraEnabled;
  bool _speakerOn = true;
  bool _screenSharing = false;
  bool _is2ParticipantPipMode = false;
  bool _isLocalDominant = false;
  Offset? _pipOffset;
  String? _fullscreenParticipantId;

  bool _isLeaving = false;
  bool _isEnded = false;
  Future<void>? _teardownFuture;

  late String _currentUserName;
  late String _currentUserInitials;
  List<GroupCallParticipant>? _customParticipants;

  VorynMeetingService get _meetingService =>
      widget.meetingService ?? VorynMeetingService.instance;

  bool get isHost => widget.joinedMeeting.isHost;

  bool get isReconnecting =>
      _state == MeetingConnectionState.reconnecting ||
      (_session != null &&
          !_session!.isConnected &&
          _state == MeetingConnectionState.connected &&
          !_isLeaving &&
          !_isEnded);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _durationNotifier = ValueNotifier(Duration.zero);

    // Media preferences from pre-join
    _muted = !widget.joinedMeeting.initialMic;
    _cameraEnabled = widget.joinedMeeting.initialCamera;

    // User identity
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

    if (widget.customParticipants != null) {
      _customParticipants = List.of(widget.customParticipants!);
    }

    // Connect or reuse session
    if (widget.existingSession != null) {
      _session = widget.existingSession;
      _attachRoomListener();
      _state = _session!.isConnected
          ? MeetingConnectionState.connected
          : MeetingConnectionState.connecting;
      if (_state == MeetingConnectionState.connected) {
        _startTimer();
      }
    } else {
      _state = MeetingConnectionState.connecting;
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }

    _subscribeToMeetingEvents();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isLeaving && !_isEnded && _state == MeetingConnectionState.connected) {
        _durationNotifier.value += const Duration(seconds: 1);
      }
    });
  }

  Future<void> _connect() async {
    if (!mounted || _isLeaving || _isEnded) return;

    final url = widget.joinedMeeting.livekitUrl;
    final token = widget.joinedMeeting.livekitToken;

    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      setState(() {
        _state = MeetingConnectionState.failed;
        _errorMessage = 'Meeting token or room URL is unavailable.';
      });
      return;
    }

    if (token.startsWith('mock.') || url.contains('.internal')) {
      setState(() {
        _state = MeetingConnectionState.connected;
      });
      _startTimer();
      return;
    }

    setState(() {
      _state = MeetingConnectionState.connecting;
      _errorMessage = null;
    });

    try {
      final session = await widget.liveKitService.connectMeeting(
        url: url,
        token: token,
        initialMic: widget.joinedMeeting.initialMic,
        initialCamera: widget.joinedMeeting.initialCamera,
      );

      if (!mounted) {
        await session.disconnect();
        return;
      }

      _session = session;
      _attachRoomListener();
      setState(() {
        _state = MeetingConnectionState.connected;
      });
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = MeetingConnectionState.failed;
        _errorMessage = 'Could not connect to meeting room';
      });
    }
  }

  void _subscribeToMeetingEvents() {
    final client = VorynBackend.client;
    if (client == null) return;

    _meetingChannel?.unsubscribe();
    _meetingChannel = client
        .channel('meeting:${widget.joinedMeeting.meetingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'meetings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.joinedMeeting.meetingId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus == 'ended' || newStatus == 'cancelled') {
              _onMeetingEndedRemotely();
            }
          },
        )
        .subscribe();
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
    if (!mounted || _isLeaving || _isEnded) return;
    final room = _session?.room;
    if (room != null &&
        room.connectionState == livekit.ConnectionState.reconnecting) {
      if (_state != MeetingConnectionState.reconnecting) {
        setState(() => _state = MeetingConnectionState.reconnecting);
      }
    } else if (room != null &&
        room.connectionState == livekit.ConnectionState.connected &&
        _state == MeetingConnectionState.reconnecting) {
      setState(() => _state = MeetingConnectionState.connected);
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_isLeaving && !_isEnded) {
      _reconcileOnResume();
    }
  }

  Future<void> _reconcileOnResume() async {
    try {
      final code = widget.joinedMeeting.joinCode;
      if (code != null && code.isNotEmpty) {
        final prejoin = await _meetingService.resolveMeetingForPrejoin(code);
        if (prejoin != null && (prejoin.status == 'ended' || prejoin.status == 'cancelled')) {
          _onMeetingEndedRemotely();
          return;
        }
      }
      final myMeetings = await _meetingService.listMyMeetings();
      final me = myMeetings.where((m) => m.id == widget.joinedMeeting.meetingId).firstOrNull;
      if (me != null && me.isEnded) {
        _onMeetingEndedRemotely();
      }
    } catch (_) {}
  }

  void _onMeetingEndedRemotely() {
    if (_isEnded || _isLeaving) return;
    _isEnded = true;
    _state = MeetingConnectionState.ended;
    widget.onMeetingEnded?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meeting has been ended by the host.')),
      );
    }
    _disconnectAndExit();
  }

  @visibleForTesting
  void triggerRemoteMeetingEnd() => _onMeetingEndedRemotely();

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

  @visibleForTesting
  void setTestState(MeetingConnectionState newState) {
    setState(() => _state = newState);
  }

  String _getInitials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    return parts.isNotEmpty ? parts.map((p) => p[0].toUpperCase()).join() : 'M';
  }

  List<GroupCallParticipant> _getParticipants() {
    if (_customParticipants != null && _customParticipants!.isNotEmpty) {
      return _customParticipants!;
    }

    final list = <GroupCallParticipant>[];
    if (_session != null) {
      try {
        final remotes = _session!.room.remoteParticipants;
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
      } catch (_) {}
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

  void _toggle2ParticipantLayout() {
    if (!mounted) return;
    setState(() => _is2ParticipantPipMode = !_is2ParticipantPipMode);
  }

  Future<void> _toggleShare() async {
    if (_isLeaving || _isEnded) return;
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

  void _copyMeetingCode() {
    final code = widget.joinedMeeting.joinCode ?? widget.joinedMeeting.meetingId;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meeting code copied to clipboard')),
    );
  }

  Future<void> _leaveMeeting() async {
    if (_isLeaving || _isEnded) return;
    _isLeaving = true;
    setState(() {});

    try {
      await _meetingService.leaveMeeting(widget.joinedMeeting.meetingId);
    } catch (e) {
      debugPrint('[MEETING] leaveMeeting RPC failed: $e');
    } finally {
      await _disconnectAndExit();
    }
  }

  Future<void> _confirmEndForEveryone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17171a),
        title: const Text('End meeting for everyone?'),
        content: const Text(
          'This will end the meeting for all participants.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFF87171)),
            child: const Text('End Meeting'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _endMeetingForEveryone();
    }
  }

  Future<void> _endMeetingForEveryone() async {
    if (_isLeaving || _isEnded) return;
    _isLeaving = true;
    setState(() {});

    final result = await _meetingService.endMeetingForEveryone(widget.joinedMeeting.meetingId);

    if (result.status == MeetingEndStatus.failedBeforeDb) {
      // Termination failed BEFORE DB update. Meeting remains active.
      _isLeaving = false;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage != null && result.errorMessage!.isNotEmpty
                  ? 'Failed to end meeting: ${result.errorMessage}. Meeting remains active.'
                  : 'Failed to end meeting before database update. Meeting remains active.',
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    // Meeting is authoritatively ended in database.
    _isEnded = true;

    if (result.status == MeetingEndStatus.endedCleanupPending) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting ended. Media room cleanup is pending.'),
            backgroundColor: Color(0xFFF59E0B),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting ended for everyone.'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    }

    await _disconnectAndExit();
  }

  Future<void> _disconnectAndExit() {
    return _teardownFuture ??= _performTeardown();
  }

  Future<void> _performTeardown() async {
    _timer?.cancel();
    _detachRoomListener();
    _meetingChannel?.unsubscribe();

    if (_screenSharing) {
      try {
        await LockScreenService.setScreenShareActive(false);
      } catch (_) {}
    }

    try {
      await _session?.disconnect();
    } catch (_) {}

    if (mounted) {
      final rootNav = Navigator.of(context, rootNavigator: true);
      final nav = Navigator.of(context);
      if (rootNav.canPop()) {
        rootNav.pop();
      } else if (nav.canPop()) {
        nav.pop();
      } else {
        try {
          context.go('/meetings');
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _detachRoomListener();
    _meetingChannel?.unsubscribe();
    _durationNotifier.dispose();
    super.dispose();
  }

  String _formatTimer(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _openInvitePicker() {
    MeetingInviteSheet.show(
      context,
      meetingId: widget.joinedMeeting.meetingId,
      meetingTitle: widget.joinedMeeting.title,
      meetingService: _meetingService,
    );
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
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _openInvitePicker();
                        },
                        icon: const Icon(Icons.person_add_rounded, size: 16, color: Color(0xFF008F66)),
                        label: const Text('Invite', style: TextStyle(color: Color(0xFF008F66), fontSize: 13)),
                      ),
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
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Meeting Code'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _copyMeetingCode();
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

  Widget _buildTopHeader(BuildContext context, List<GroupCallParticipant> participants) {
    return CallTopBar(
      onMinimize: () {
        final rootNav = Navigator.of(context, rootNavigator: true);
        final nav = Navigator.of(context);
        if (rootNav.canPop()) {
          rootNav.pop();
        } else if (nav.canPop()) {
          nav.pop();
        }
      },
      onAddParticipant: _openInvitePicker,
      showAddParticipant: true,
      onToggleLayout: participants.length == 2 ? _toggle2ParticipantLayout : null,
      isSplitScreen: !_is2ParticipantPipMode,
      centerWidget: ValueListenableBuilder<Duration>(
        valueListenable: _durationNotifier,
        builder: (context, duration, _) {
          final timeStr = _formatTimer(duration);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.joinedMeeting.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 1),
              const Text(
                'Meeting Room',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isReconnecting) ...[
                    const SizedBox(
                      width: 8,
                      height: 8,
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
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${participants.length} in meeting · $timeStr',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPersistentStatusPill(List<GroupCallParticipant> participants) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _durationNotifier,
      builder: (context, duration, _) {
        final timeStr = _formatTimer(duration);
        return Container(
          key: const Key('persistent_status_pill'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${participants.length} in meeting · $timeStr',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStage(BuildContext context, List<GroupCallParticipant> participants) {
    final activeScreenShareTrack =
        _session?.remoteScreenShareTrack ?? _session?.localScreenShareTrack;
    if (activeScreenShareTrack != null) {
      return _buildScreenShareStage(context, activeScreenShareTrack, participants);
    }

    if (participants.length >= 3 &&
        _fullscreenParticipantId != null &&
        participants.any((p) => p.id == _fullscreenParticipantId)) {
      return _buildFullscreenParticipantStage(context, participants);
    }

    final hasAnyVideo = participants.any((p) => p.videoTrack != null && !p.isCameraOff);

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
          bottom: _controlsVisible ? 180 : 24,
          height: 100,
          child: ListView.separated(
            key: const Key('meeting_pip_deck'),
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

  Widget _buildScreenShareStage(
    BuildContext context,
    livekit.VideoTrack screenTrack,
    List<GroupCallParticipant> participants,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Colors.black,
          child: IgnorePointer(
            child: livekit.VideoTrackRenderer(
              screenTrack,
              key: ValueKey(
                'meet_screen_${screenTrack.sid ?? screenTrack.hashCode}',
              ),
              fit: livekit.VideoViewFit.contain,
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: _controlsVisible ? 120 : 20,
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: participants.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = participants[i];
              return Container(
                width: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: p.isSpeaking ? const Color(0xFF22C55E) : Colors.white24,
                    width: p.isSpeaking ? 2 : 1,
                  ),
                  color: const Color(0xFF17171a),
                ),
                clipBehavior: Clip.antiAlias,
                child: p.videoTrack != null && !p.isCameraOff
                    ? ConferenceVideoTrackSurface(
                        track: p.videoTrack!,
                        mirrorMode: p.isYou
                            ? livekit.VideoViewMirrorMode.mirror
                            : livekit.VideoViewMirrorMode.off,
                        fit: livekit.VideoViewFit.cover,
                      )
                    : Center(
                        child: Text(
                          p.initials,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoGrid(BuildContext context, List<GroupCallParticipant> participants) {
    final count = participants.length;
    if (count <= 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _buildVideoTile(context, participants.first),
      );
    } else if (count == 2) {
      if (_is2ParticipantPipMode) {
        final dominant = _isLocalDominant ? participants[1] : participants[0];
        return _buildVideoTile(context, dominant);
      }
      final isLandscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: isLandscape
            ? Row(
                children: [
                  Expanded(child: _buildVideoTile(context, participants[0])),
                  const SizedBox(width: 8),
                  Expanded(child: _buildVideoTile(context, participants[1])),
                ],
              )
            : Column(
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

  Widget _buildAudioGrid(BuildContext context, List<GroupCallParticipant> participants) {
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
          icon: Icons.copy_rounded,
          label: 'Copy Code',
          onTap: _copyMeetingCode,
        ),
        CallControlButton(
          icon: Icons.call_end_rounded,
          label: 'Leave',
          isDestructive: true,
          onTap: _leaveMeeting,
        ),
        if (isHost)
          CallControlButton(
            icon: Icons.cancel_presentation_rounded,
            label: 'End All',
            isDestructive: true,
            onTap: _confirmEndForEveryone,
          ),
      ],
    );
  }

  Widget _buildConnectingView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b0b0d),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF008F66)),
              const SizedBox(height: 20),
              Text(
                widget.joinedMeeting.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connecting to meeting room...',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedView(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b0b0d),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 56,
                  color: Color(0xFFF87171),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Connection Failed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'Could not connect to meeting room',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _leaveMeeting,
                      child: const Text('Return'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF008F66),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _connect,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_state == MeetingConnectionState.connecting) {
      return _buildConnectingView(context);
    }

    if (_state == MeetingConnectionState.failed) {
      return _buildFailedView(context);
    }

    final participants = _getParticipants();
    final activeScreenShareTrack =
        _session?.remoteScreenShareTrack ?? _session?.localScreenShareTrack;
    final is2ParticipantPip =
        participants.length == 2 && _is2ParticipantPipMode && activeScreenShareTrack == null;
    final pipParticipant = is2ParticipantPip
        ? (_isLocalDominant ? participants[0] : participants[1])
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0b0b0d),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Interactive Stage (fills screen, tap toggles controls)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: SafeArea(
              top: _controlsVisible,
              bottom: _controlsVisible,
              child: _buildStage(context, participants),
            ),
          ),

          // Floating Picture-in-Picture when in 2-participant PiP mode (and no screen sharing)
          if (is2ParticipantPip && pipParticipant != null)
            VideoPip(
              key: const Key('meeting_room_pip'),
              videoTrack: pipParticipant.videoTrack,
              isMirror: pipParticipant.isYou,
              isMuted: pipParticipant.isMuted,
              isVideoEnabled: !pipParticipant.isCameraOff,
              label: pipParticipant.name,
              userInitials: pipParticipant.initials,
              controlsVisible: _controlsVisible,
              offset: _pipOffset,
              onOffsetChanged: (newOffset) => _pipOffset = newOffset,
              onTap: () => setState(() => _isLocalDominant = !_isLocalDominant),
            ),

          // Top Gradient Scrim
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 130,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Gradient Scrim
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 220,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top Header Bar (Animated hide/show)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
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
                    child: _buildTopHeader(context, participants),
                  ),
                ),
              ),
            ),
          ),

          // Persistent Status Pill when controls are hidden
          if (!_controlsVisible)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildPersistentStatusPill(participants),
                ),
              ),
            ),

          // Screen Share Banner (when local user is presenting)
          if (_screenSharing)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: _controlsVisible ? 68 : 40),
                  child: ScreenShareBanner(onStopSharing: _toggleShare),
                ),
              ),
            ),

          // Remote Screen Share Banner (when remote participant is presenting)
          if (activeScreenShareTrack != null && !_screenSharing)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: _controlsVisible ? 68 : 40),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.screen_share_rounded,
                          size: 16,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${_session?.screenSharePresenterName ?? 'Participant'} is sharing screen',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Bottom Controls Overlay (animated hide/show)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
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
          ),
        ],
      ),
    );
  }
}

