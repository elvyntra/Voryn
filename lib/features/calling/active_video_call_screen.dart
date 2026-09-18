import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../connect/mock_voryn_state.dart';
import 'voryn_call_history_service.dart';
import 'voryn_call_latency_tracker.dart';
import 'voryn_call_runtime_coordinator.dart';
import 'voryn_call_service.dart';
import 'voryn_livekit_service.dart';
import 'widgets/add_participant_sheet.dart';
import 'widgets/call_avatar_rings.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_top_bar.dart';
import 'widgets/screen_share_banner.dart';
import 'widgets/video_pip.dart';

class ActiveVideoCallScreen extends StatefulWidget {
  const ActiveVideoCallScreen({
    super.key,
    required this.callId,
    this.user,
    this.existingSession,
  });

  final String callId;
  final VorynMockUser? user;
  final VorynLiveKitSession? existingSession;

  @override
  State<ActiveVideoCallScreen> createState() => _ActiveVideoCallScreenState();
}

class _ActiveVideoCallScreenState extends State<ActiveVideoCallScreen> {
  late VorynMockUser _user;
  late final VorynCallRuntimeCoordinator _coordinator;
  VorynCallLatencyTracker? _latencyTracker;
  VorynLiveKitSession? _session;
  Timer? _timer;
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(
    Duration.zero,
  );
  final ValueNotifier<bool> _cameraEnabledNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _mutedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _screenSharingNotifier = ValueNotifier(false);

  livekit.VideoTrack? _remoteTrack;
  livekit.VideoTrack? _localTrack;

  bool _loading = true;
  bool _isConnected = false;
  String _callStatusText = 'Calling…';
  bool _ending = false;
  bool _ended = false;
  bool _listenerAttached = false;

  @override
  void initState() {
    super.initState();
    LockScreenService.cancelNativeIncomingCall(widget.callId, reason: 'accept');
    _coordinator = VorynCallRuntimeCoordinator.forCall(widget.callId);
    _latencyTracker =
        VorynCallLatencyTracker.get(widget.callId) ??
        VorynCallLatencyTracker.start(callId: widget.callId);
    unawaited(_latencyTracker?.stage('active_route_mounted'));

    _coordinator.attachScreen(
      onStatusChanged: _handleRealtimeStatus,
      onRouteExit: _handleRouteExit,
    );

    _user =
        widget.user ??
        findMockUser('@rahul') ??
        const VorynMockUser(
          backendUid: null,
          customName: 'Contact',
          name: 'Voryn User',
          id: '@voryn',
          phone: '',
          email: '',
          presence: VorynPresenceStatus.online,
          initials: 'VU',
        );

    _start();
  }

  Future<void> _start() async {
    if (widget.user == null) {
      try {
        final item = await const VorynCallHistoryService()
            .loadIncomingActiveCall(callId: widget.callId);
        if (item != null && mounted) {
          final parts = item.displayName
              .split(RegExp(r'\s+'))
              .where((p) => p.isNotEmpty)
              .take(2)
              .toList();
          final initials = parts.map((p) => p[0].toUpperCase()).join();
          setState(() {
            _user = VorynMockUser(
              backendUid: item.otherUid,
              customName: null,
              name: item.displayName,
              id: item.vorynId.startsWith('@')
                  ? item.vorynId
                  : '@${item.vorynId}',
              phone: '',
              email: '',
              presence: VorynPresenceStatus.online,
              initials: initials.isEmpty ? '?' : initials,
            );
          });
        }
      } catch (_) {}
    }

    if (widget.existingSession != null) {
      _session = widget.existingSession;
      _coordinator.session = _session;
      _isConnected = true;
      await _session?.setCameraEnabled(true);
      _attachRoomListener();
      _startTimer();
      unawaited(_latencyTracker?.stage('call_connected_ui'));
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      _session = await _coordinator.connect(
        video: true,
        latencyTracker: _latencyTracker,
      );
      _attachRoomListener();
      if (_session!.room.remoteParticipants.isNotEmpty) {
        _isConnected = true;
        _startTimer();
        await _latencyTracker?.stage('backend_accept_start');
        await const VorynCallService().setConnected(widget.callId);
        await _latencyTracker?.stage('backend_accept_done');
        await _latencyTracker?.stage('call_connected_ui');
      } else {
        _callStatusText = 'Ringing…';
      }
    } catch (e) {
      debugPrint('[CALL ${widget.callId}] connect fallback / mock mode: $e');
      _isConnected = true;
      _callStatusText = 'Connected';
      _startTimer();
      await _latencyTracker?.stage('call_connected_ui');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _handleRealtimeStatus(String status) {
    if (status == 'connected' && !_isConnected) {
      _isConnected = true;
      _callStatusText = '';
      _startTimer();
      unawaited(_latencyTracker?.stage('call_connected_ui'));
      if (mounted) setState(() {});
    } else if (status == 'ringing' && !_isConnected) {
      _callStatusText = 'Ringing…';
      if (mounted) setState(() {});
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ending && !_ended) {
        _durationNotifier.value += const Duration(seconds: 1);
      }
    });
  }

  void _attachRoomListener() {
    if (_listenerAttached || _session == null) return;
    _listenerAttached = true;
    _session!.room.addListener(_onRoomChanged);
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
    final room = _session?.room;
    if (room == null) return;

    if (room.remoteParticipants.isNotEmpty && !_isConnected) {
      _isConnected = true;
      _callStatusText = '';
      _startTimer();
      unawaited(const VorynCallService().setConnected(widget.callId));
      if (mounted) setState(() {});
    }

    if (room.remoteParticipants.length > 1) {
      _checkAndEscalateToGroup();
      return;
    }

    if (room.connectionState == livekit.ConnectionState.disconnected) {
      debugPrint('[CALL ${widget.callId}] LiveKit room disconnected');
      _handleRoomDisconnected();
      return;
    }

    final nextRemote = _session?.remoteVideoTrack;
    final nextLocal = _session?.localVideoTrack;
    if (nextRemote != _remoteTrack || nextLocal != _localTrack) {
      setState(() {
        _remoteTrack = nextRemote;
        _localTrack = nextLocal;
      });
    }
  }

  Future<void> _handleRoomDisconnected() async {
    if (_ending || _ended) return;
    try {
      final call = await const VorynCallService().getCall(widget.callId);
      final status = call?['status'] as String?;
      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'declined' ||
          status == 'failed') {
        debugPrint(
          '[CALL ${widget.callId}] backend confirms terminal status=$status',
        );
        _performTeardown(isLocalInitiator: false);
      } else {
        debugPrint(
          '[CALL ${widget.callId}] video media disconnected but call still active (status=$status)',
        );
      }
    } catch (_) {
      _performTeardown(isLocalInitiator: false);
    }
  }

  Future<void> _checkAndEscalateToGroup() async {
    if (_ending || _ended || !mounted) return;
    try {
      final count = await const VorynCallService().getParticipantCount(
        widget.callId,
      );
      final room = _session?.room;
      if (count > 2 && room != null && room.remoteParticipants.length > 1) {
        _escalateToGroup();
      }
    } catch (_) {
      if ((_session?.room.remoteParticipants.length ?? 0) > 1) {
        _escalateToGroup();
      }
    }
  }

  void _escalateToGroup() {
    if (_ending || _ended || !mounted) return;
    debugPrint(
      '[CALL ${widget.callId}] participant joined room, escalating to group',
    );
    _coordinator.isTransitioning = true;
    _detachRoomListener();
    _coordinator.detachScreen();
    final shortId = widget.callId.length > 8
        ? widget.callId.substring(0, 8)
        : widget.callId;
    context.pushReplacement(
      '/group-call/${widget.callId}',
      extra: {'title': 'Call $shortId', 'session': _session},
    );
  }

  Future<void> _toggleMute() async {
    if (_ending || _ended) return;
    final next = !_mutedNotifier.value;
    _mutedNotifier.value = next;
    await _session?.setMicrophoneEnabled(!next);
  }

  Future<void> _toggleCamera() async {
    if (_ending || _ended) return;
    final next = !_cameraEnabledNotifier.value;
    _cameraEnabledNotifier.value = next;
    await _session?.setCameraEnabled(next);
  }

  Future<void> _flipCamera() async {
    if (_ending || _ended || !_cameraEnabledNotifier.value) return;
    try {
      final publication =
          _session?.room.localParticipant?.videoTrackPublications.firstOrNull;
      if (publication?.track is livekit.LocalVideoTrack) {
        final localTrack = publication!.track as livekit.LocalVideoTrack;
        final current = localTrack.currentOptions;
        final pos = current is livekit.CameraCaptureOptions
            ? current.cameraPosition
            : livekit.CameraPosition.front;
        await localTrack.restartTrack(
          livekit.CameraCaptureOptions(cameraPosition: pos.switched()),
        );
      }
    } catch (_) {}
  }

  Future<void> _toggleShare() async {
    if (_ending || _ended) return;
    final next = !_screenSharingNotifier.value;
    _screenSharingNotifier.value = next;
    await _session?.setScreenShareEnabled(next);
  }

  void _openAudioRoutes() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16191E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volume_up_rounded, color: Colors.white),
              title: const Text(
                'Speaker',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                await _session?.setSpeakerEnabled(true);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.phone_in_talk_rounded,
                color: Colors.white,
              ),
              title: const Text(
                'Earpiece / Phone',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                await _session?.setSpeakerEnabled(false);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _endCall() {
    if (_ending || _ended) return Future<void>.value();
    if (mounted) {
      setState(() => _ending = true);
    } else {
      _ending = true;
    }
    debugPrint('[CALL ${widget.callId}] local end pressed');
    return _performTeardown(isLocalInitiator: true);
  }

  Future<void> _performTeardown({bool isLocalInitiator = false}) {
    _ending = true;
    _timer?.cancel();
    _detachRoomListener();
    return _coordinator.performTeardown(
      isLocalInitiator: isLocalInitiator,
      onRouteExit: _handleRouteExit,
    );
  }

  Future<void> _handleRouteExit() async {
    _ending = true;
    _ended = true;
    _timer?.cancel();
    _detachRoomListener();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      final client = VorynBackend.client;
      if (client?.auth.currentUser != null) {
        context.go('/connect');
      } else {
        context.go('/welcome');
      }
    }
  }

  void _minimize() async {
    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) {
      return;
    }
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        final client = VorynBackend.client;
        if (client?.auth.currentUser != null) {
          context.go('/connect');
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
    _durationNotifier.dispose();
    _cameraEnabledNotifier.dispose();
    _mutedNotifier.dispose();
    _screenSharingNotifier.dispose();
    if (!_coordinator.isTransitioning && !_coordinator.isEnded) {
      _coordinator.performTeardown(isLocalInitiator: true);
    }
    _coordinator.detachScreen();
    super.dispose();
  }

  String _formatTimer(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_ended) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    debugPrint('[BOOT] ActiveVideoCallScreen build');
    final colors = context.vorynColors;
    final primaryName = _user.customName ?? _user.name;

    final remoteTrack = _remoteTrack ?? _session?.remoteVideoTrack;
    final localTrack = _localTrack ?? _session?.localVideoTrack;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dominant Remote Video Stage
          if (remoteTrack != null)
            livekit.VideoTrackRenderer(
              remoteTrack,
              key: ValueKey(remoteTrack.sid ?? remoteTrack.hashCode),
              fit: livekit.VideoViewFit.cover,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1D24), Color(0xFF0C0E12)],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CallAvatarRings(initials: _user.initials, size: 110),
                    const SizedBox(height: 20),
                    Text(
                      primaryName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _loading ? 'Connecting video…' : 'Camera off',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top Gradient Scrim for Overlay Visibility
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 140,
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

          // Bottom Gradient Scrim for Controls Visibility
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
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

          // Top Overlay: CallTopBar + Identity & Timer
          SafeArea(
            child: Column(
              children: [
                CallTopBar(
                  onMinimize: _minimize,
                  centerWidget: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            primaryName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'HD',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
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
                          ValueListenableBuilder<Duration>(
                            valueListenable: _durationNotifier,
                            builder: (context, duration, _) {
                              return Text(
                                _loading
                                    ? 'Connecting…'
                                    : (!_isConnected
                                          ? _callStatusText
                                          : _formatTimer(duration)),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                ),
                              );
                            },
                          ),
                        ],
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
                ),

                // Screen Share Banner (if screen sharing active)
                ValueListenableBuilder<bool>(
                  valueListenable: _screenSharingNotifier,
                  builder: (context, sharing, _) {
                    if (!sharing) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ScreenShareBanner(onStopSharing: _toggleShare),
                    );
                  },
                ),
              ],
            ),
          ),

          // Floating Picture-in-Picture Local Video Preview
          ListenableBuilder(
            listenable: Listenable.merge([
              _cameraEnabledNotifier,
              _mutedNotifier,
            ]),
            builder: (context, _) {
              return VideoPip(
                localTrack: localTrack,
                isMuted: _mutedNotifier.value,
                isCameraEnabled: _cameraEnabledNotifier.value,
                userInitials: 'YOU',
              );
            },
          ),

          // Bottom Controls Overlay
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Floating 2x3 Control Tray
                    CallControlTray(
                      row1: [
                        ValueListenableBuilder<bool>(
                          valueListenable: _mutedNotifier,
                          builder: (context, muted, _) => CallControlButton(
                            icon: muted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            label: muted ? 'Muted' : 'Mute',
                            isDestructive: muted,
                            onTap: _toggleMute,
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: _cameraEnabledNotifier,
                          builder: (context, enabled, _) => CallControlButton(
                            icon: enabled
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            label: enabled ? 'Camera' : 'Camera off',
                            isActive: enabled,
                            activeColor: colors.surfaceRaised,
                            onTap: _toggleCamera,
                          ),
                        ),
                        CallControlButton(
                          icon: Icons.flip_camera_android_rounded,
                          label: 'Flip',
                          onTap: _flipCamera,
                        ),
                      ],
                      row2: [
                        CallControlButton(
                          icon: Icons.volume_up_rounded,
                          label: 'Speaker',
                          onTap: _openAudioRoutes,
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: _screenSharingNotifier,
                          builder: (context, sharing, _) => CallControlButton(
                            icon: Icons.screen_share_outlined,
                            label: sharing ? 'Sharing' : 'Share',
                            isActive: sharing,
                            activeColor: colors.accent,
                            onTap: _toggleShare,
                          ),
                        ),
                        CallControlButton(
                          icon: Icons.call_end_rounded,
                          label: 'End',
                          isDestructive: true,
                          onTap: _endCall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
