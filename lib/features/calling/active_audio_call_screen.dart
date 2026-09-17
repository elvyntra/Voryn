import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import 'voryn_call_history_service.dart';
import 'voryn_call_service.dart';
import 'voryn_livekit_service.dart';
import 'widgets/add_participant_sheet.dart';
import 'widgets/call_avatar_rings.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_top_bar.dart';
import 'widgets/call_waveform.dart';

class ActiveAudioCallScreen extends StatefulWidget {
  const ActiveAudioCallScreen({
    super.key,
    required this.callId,
    this.user,
    this.existingSession,
  });

  final String callId;
  final VorynMockUser? user;
  final VorynLiveKitSession? existingSession;

  @override
  State<ActiveAudioCallScreen> createState() => _ActiveAudioCallScreenState();
}

class _ActiveAudioCallScreenState extends State<ActiveAudioCallScreen> {
  late VorynMockUser _user;
  VorynLiveKitSession? _session;
  Timer? _timer;
  RealtimeChannel? _callSubscription;
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(
    Duration.zero,
  );

  bool _loading = true;
  bool _muted = false;
  bool _held = false;
  bool _screenSharing = false;
  bool _isConnected = false;
  String _callStatusText = 'Calling…';

  bool _ending = false;
  bool _ended = false;
  bool _listenerAttached = false;
  Future<void>? _teardownFuture;

  @override
  void initState() {
    super.initState();
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
    // If user info was not supplied, attempt to resolve it from the call history
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
      _isConnected = true;
      _attachRoomListener();
      _subscribeToCallEvents();
      _startTimer();
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      _session = await const VorynLiveKitService().connect(
        callId: widget.callId,
        video: false,
      );
      _attachRoomListener();
      _subscribeToCallEvents();
      if (_session!.room.remoteParticipants.isNotEmpty) {
        _isConnected = true;
        _startTimer();
        await const VorynCallService().setConnected(widget.callId);
      } else {
        _callStatusText = 'Ringing…';
      }
    } catch (e) {
      debugPrint('[CALL ${widget.callId}] connect fallback / mock mode: $e');
      _isConnected = true;
      _callStatusText = 'Connected';
      _startTimer();
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _subscribeToCallEvents() {
    _callSubscription?.unsubscribe();
    _callSubscription = const VorynCallService().subscribeToCallState(
      widget.callId,
      (status) {
        debugPrint('[CALL ${widget.callId}] realtime state update: $status');
        if ([
          'completed',
          'cancelled',
          'declined',
          'missed',
          'failed',
        ].contains(status)) {
          debugPrint('[CALL ${widget.callId}] remote end received');
          _teardownFuture ??= _performTeardown(isLocalInitiator: false);
        } else if (status == 'connected' && !_isConnected) {
          _isConnected = true;
          _callStatusText = '';
          _startTimer();
          if (mounted) setState(() {});
        } else if (status == 'ringing' && !_isConnected) {
          _callStatusText = 'Ringing…';
          if (mounted) setState(() {});
        }
      },
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_held && !_ending && !_ended) {
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

    // If more than 1 remote participant is in the room, verify and escalate to group call UI
    if (room.remoteParticipants.length > 1) {
      _checkAndEscalateToGroup();
      return;
    }

    // On room disconnection, check whether the call is truly terminal on backend
    if (room.connectionState == livekit.ConnectionState.disconnected) {
      debugPrint('[CALL ${widget.callId}] LiveKit room disconnected');
      _handleRoomDisconnected();
      return;
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
        _teardownFuture ??= _performTeardown(isLocalInitiator: false);
      } else {
        debugPrint(
          '[CALL ${widget.callId}] media disconnected but call still active (status=$status), awaiting reconnection or terminal signal',
        );
      }
    } catch (_) {
      _teardownFuture ??= _performTeardown(isLocalInitiator: false);
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
    _detachRoomListener();
    _callSubscription?.unsubscribe();
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
    final next = !_muted;
    await _session?.setMicrophoneEnabled(!next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleHold() async {
    if (_ending || _ended) return;
    final next = !_held;
    if (mounted) setState(() => _held = next);
  }

  Future<void> _toggleShare() async {
    if (_ending || _ended) return;
    final next = !_screenSharing;
    await _session?.setScreenShareEnabled(next);
    if (mounted) setState(() => _screenSharing = next);
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

  void _switchToVideo() {
    _callSubscription?.unsubscribe();
    _detachRoomListener();
    context.pushReplacement(
      '/active-video-call/${widget.callId}',
      extra: {'user': _user, 'session': _session},
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
    return _teardownFuture ??= _performTeardown(isLocalInitiator: true);
  }

  Future<void> _performTeardown({bool isLocalInitiator = false}) async {
    if (_ended) return;
    _ending = true;
    debugPrint('[CALL ${widget.callId}] teardown begin');
    _timer?.cancel();
    _detachRoomListener();
    _callSubscription?.unsubscribe();

    if (isLocalInitiator) {
      try {
        await const VorynCallService().end(widget.callId);
        debugPrint('[CALL ${widget.callId}] backend terminal update success');
      } catch (e) {
        debugPrint('[CALL ${widget.callId}] backend terminal update error: $e');
      }
    }

    try {
      await _session?.disconnect();
      debugPrint('[CALL ${widget.callId}] room disconnect complete');
    } catch (_) {}

    _ended = true;
    await const VorynCallService().clearActiveCall(widget.callId);
    _session = null;
    debugPrint('[CALL ${widget.callId}] teardown complete');

    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) {
      debugPrint('[CALL ${widget.callId}] route exit (locked)');
      await LockScreenService.moveCallTaskBehindKeyguard();
      return;
    }

    debugPrint('[CALL ${widget.callId}] route exit');
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

  void _minimize() async {
    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) {
      // Do not expose the normal app shell over lock screen
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

  void _openMessageSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF16191E),
      builder: (_) => QuickMessageSheet(user: _user),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _detachRoomListener();
    _callSubscription?.unsubscribe();
    _durationNotifier.dispose();
    if (!_ending && !_ended) {
      _performTeardown(isLocalInitiator: true);
    }
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
      return const Scaffold(backgroundColor: Color(0xFF0D0F12));
    }
    debugPrint('[BOOT] ActiveAudioCallScreen build');
    final colors = context.vorynColors;

    // Contact identity resolution
    final primaryName = _user.customName ?? _user.name;
    final secondaryText =
        _user.customName != null && _user.customName != _user.name
        ? '${_user.name} · ${_user.id}'
        : _user.id;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            CallTopBar(
              onMinimize: _minimize,
              centerWidget: const SecurityBadge(label: 'SECURE CALL'),
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

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            const Spacer(flex: 2),

                            // Caller Identity: Concentric Acoustic Rings & Avatar
                            CallAvatarRings(
                              initials: _user.initials,
                              size: 130,
                              badge: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF0D0F12),
                                    width: 2.5,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Primary Contact Name
                            Text(
                              primaryName,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 6),

                            // Canonical Name / Voryn ID
                            Text(
                              secondaryText,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 15,
                                    color: Colors.white60,
                                  ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 18),

                            // Call Duration & HD Status
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF22C55E),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ValueListenableBuilder<Duration>(
                                  valueListenable: _durationNotifier,
                                  builder: (context, duration, _) {
                                    return Text(
                                      _loading
                                          ? 'Connecting…'
                                          : (_held
                                                ? 'Call on hold'
                                                : (!_isConnected
                                                      ? _callStatusText
                                                      : _formatTimer(
                                                          duration,
                                                        ))),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'HD VOICE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white38,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Restrained Acoustic Waveform
                            CallWaveform(
                              isActive: !_held && !_muted && !_loading,
                              color: const Color(0xFFA78BFA),
                            ),

                            const Spacer(flex: 3),

                            // Secondary Message trigger button
                            TextButton.icon(
                              onPressed: _openMessageSheet,
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                                color: Colors.white70,
                              ),
                              label: const Text(
                                'Send message',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Floating 2x3 Control Tray
                            CallControlTray(
                              row1: [
                                CallControlButton(
                                  icon: Icons.volume_up_rounded,
                                  label: 'Audio',
                                  onTap: _openAudioRoutes,
                                ),
                                CallControlButton(
                                  icon: Icons.videocam_outlined,
                                  label: 'Video',
                                  onTap: _switchToVideo,
                                ),
                                CallControlButton(
                                  icon: _muted
                                      ? Icons.mic_off_rounded
                                      : Icons.mic_rounded,
                                  label: _muted ? 'Muted' : 'Mute',
                                  isActive: _muted,
                                  activeColor: const Color(0xFFDC2626),
                                  onTap: _toggleMute,
                                ),
                              ],
                              row2: [
                                CallControlButton(
                                  icon: _held
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  label: _held ? 'Resume' : 'Hold',
                                  isActive: _held,
                                  activeColor: colors.accent,
                                  onTap: _toggleHold,
                                ),
                                CallControlButton(
                                  icon: Icons.screen_share_outlined,
                                  label: 'Share',
                                  isActive: _screenSharing,
                                  activeColor: colors.accent,
                                  onTap: _toggleShare,
                                ),
                                CallControlButton(
                                  icon: Icons.call_end_rounded,
                                  label: 'End',
                                  isDestructive: true,
                                  onTap: _endCall,
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Network Quality Status Line
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              child: Row(
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
                                  const Text(
                                    'Good connection',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.shield_outlined,
                                    size: 14,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Secure',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
