import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import '../../core/theme/voryn_theme.dart';
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
  final Color statusColor;

  const GroupCallParticipant({
    required this.id,
    required this.name,
    required this.initials,
    this.isYou = false,
    this.isMuted = false,
    this.statusColor = const Color(0xFF22C55E),
  });
}

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({
    super.key,
    required this.callId,
    this.title = 'Group Meeting',
    this.initialParticipants = 2,
    this.activeSpeakerName,
    this.participants,
    this.existingSession,
  });

  final String callId;
  final String title;
  final int initialParticipants;
  final String? activeSpeakerName;
  final List<GroupCallParticipant>? participants;
  final VorynLiveKitSession? existingSession;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  Timer? _timer;
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(
    Duration.zero,
  );

  VorynLiveKitSession? _session;
  RealtimeChannel? _callSubscription;
  bool _listenerAttached = false;

  bool _muted = false;
  bool _cameraEnabled = true;
  bool _screenSharing = false;

  bool _ending = false;
  bool _ended = false;
  Future<void>? _teardownFuture;

  late String _currentUserName;
  late String _currentUserInitials;

  @override
  void initState() {
    super.initState();
    _session = widget.existingSession;
    _attachRoomListener();
    _subscribeToCallEvents();

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
  }

  void _subscribeToCallEvents() {
    _callSubscription?.unsubscribe();
    _callSubscription = const VorynCallService().subscribeToCallState(
      widget.callId,
      (status) {
        debugPrint(
          '[CALL ${widget.callId}] realtime remote terminal event received in group call ($status)',
        );
        _teardownFuture ??= _performTeardown(isLocalInitiator: false);
      },
    );
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

  List<GroupCallParticipant> _getParticipants() {
    if (widget.participants != null && widget.participants!.isNotEmpty) {
      return widget.participants!;
    }
    final list = <GroupCallParticipant>[];
    if (_session != null && _session!.room.remoteParticipants.isNotEmpty) {
      for (final p in _session!.room.remoteParticipants.values) {
        final name = p.name.isNotEmpty
            ? p.name
            : (p.identity.isNotEmpty ? p.identity : 'Participant');
        list.add(
          GroupCallParticipant(
            id: p.sid,
            name: name,
            initials: _getInitials(name),
            statusColor: const Color(0xFF22C55E),
            isMuted: p.isMuted,
          ),
        );
      }
    } else {
      final speaker =
          widget.activeSpeakerName ??
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
        ),
      );
    }

    list.add(
      GroupCallParticipant(
        id: 'me',
        name: '$_currentUserName (You)',
        initials: _currentUserInitials,
        statusColor: const Color(0xFF22C55E),
        isMuted: _muted,
        isYou: true,
      ),
    );
    return list;
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

  @override
  Widget build(BuildContext context) {
    debugPrint('[BOOT] GroupCallScreen build');
    final colors = context.vorynColors;
    final speakerName =
        widget.activeSpeakerName ??
        (widget.title.isNotEmpty && widget.title != 'Group Meeting'
            ? widget.title
            : 'Active Speaker');
    final speakerInitials = _getInitials(speakerName);
    final participants = _getParticipants();

    return Scaffold(
      backgroundColor: const Color(0xFF090B0E),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            ValueListenableBuilder<Duration>(
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E222B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.groups_outlined,
                              size: 13,
                              color: Color(0xFFA78BFA),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${participants.length} in call  ›',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFA78BFA),
                              ),
                            ),
                          ],
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

            const SizedBox(height: 6),

            // Active Speaker Stage
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF171A21),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Active Speaker representation
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 46,
                              backgroundColor: const Color(0xFF262A34),
                              child: Text(
                                speakerInitials,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              speakerName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Top Badges: Active Speaker (left) & HD (right)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: 14,
                                color: Color(0xFF22C55E),
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Active Speaker',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 12,
                                color: Colors.white70,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'HD',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom Name & Status
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            speakerName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mic_none_rounded,
                            size: 14,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Participant Strip (Small Cards)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: participants.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final p = participants[index];
                    return SizedBox(
                      width: 100,
                      child: _ParticipantTile(
                        initials: p.initials,
                        name: p.name,
                        statusColor: p.statusColor,
                        isMuted: p.isYou ? _muted : p.isMuted,
                        isYou: p.isYou,
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Floating 2x3 Control Tray
            CallControlTray(
              row1: [
                CallControlButton(
                  icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: _muted ? 'Muted' : 'Mute',
                  isActive: _muted,
                  activeColor: const Color(0xFFDC2626),
                  onTap: () => setState(() => _muted = !_muted),
                ),
                CallControlButton(
                  icon: _cameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: 'Camera',
                  isActive: _cameraEnabled,
                  activeColor: colors.surfaceRaised,
                  onTap: () => setState(() => _cameraEnabled = !_cameraEnabled),
                ),
                CallControlButton(
                  icon: Icons.flip_camera_android_rounded,
                  label: 'Flip',
                  onTap: () {},
                ),
              ],
              row2: [
                CallControlButton(
                  icon: Icons.volume_up_rounded,
                  label: 'Audio',
                  onTap: () {},
                ),
                CallControlButton(
                  icon: Icons.screen_share_outlined,
                  label: _screenSharing ? 'Stop sharing' : 'Share',
                  isActive: _screenSharing,
                  activeColor: colors.accent,
                  onTap: () => setState(() => _screenSharing = !_screenSharing),
                ),
                CallControlButton(
                  icon: Icons.call_end_rounded,
                  label: 'End',
                  isDestructive: true,
                  onTap: _endCall,
                ),
              ],
            ),

            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.initials,
    required this.name,
    required this.statusColor,
    required this.isMuted,
    this.isYou = false,
  });

  final String initials;
  final String name;
  final Color statusColor;
  final bool isMuted;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14171E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isYou
              ? const Color(0xFFA78BFA).withValues(alpha: 0.4)
              : Colors.white10,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const Spacer(),
              if (isYou)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4C1D95),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'YOU',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDDD6FE),
                    ),
                  ),
                ),
              const Spacer(),
              Icon(
                isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 13,
                color: isMuted
                    ? const Color(0xFFF87171)
                    : const Color(0xFF22C55E),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF242933),
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
