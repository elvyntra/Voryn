import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/notifications/lock_screen_service.dart';
import '../../core/notifications/voryn_firebase_messaging.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../connect/mock_voryn_state.dart';
import '../connect/user_interaction_screens.dart';
import 'voryn_call_history_service.dart';
import 'voryn_call_latency_tracker.dart';
import 'voryn_call_runtime_coordinator.dart';
import 'voryn_call_service.dart';
import 'widgets/call_avatar_rings.dart';
import 'widgets/call_top_bar.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callId,
    this.initialCall,
    this.initialUser,
  });

  final String callId;
  final VorynCallHistoryItem? initialCall;
  final VorynMockUser? initialUser;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  VorynCallHistoryItem? _call;
  late VorynMockUser _user;
  bool _resolved = false;
  RealtimeChannel? _callSubscription;

  @override
  void initState() {
    super.initState();
    _call = widget.initialCall;
    _user =
        widget.initialUser ??
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

    _subscribeToCallEvents();
    _verifyAndLoad();
  }

  void _subscribeToCallEvents() {
    _callSubscription = const VorynCallService().subscribeToCallState(
      widget.callId,
      (status) {
        if (!_resolved && mounted) {
          debugPrint(
            '[CALL ${widget.callId}] incoming call ended remotely ($status)',
          );
          _resolved = true;
          VorynFirebaseMessaging.clearPendingIncomingCall(widget.callId);
          LockScreenService.cancelNativeIncomingCall(
            widget.callId,
            reason: 'remote_terminal',
          );
          _exitSafely();
        }
      },
    );
  }

  Future<void> _verifyAndLoad() async {
    try {
      if (VorynCallRuntimeCoordinator.isAcceptInFlight(widget.callId)) {
        debugPrint(
          '[CALL ${widget.callId}] accept in flight during incoming verify, ignoring incoming UI',
        );
        _exitSafely();
        return;
      }

      final active = await const VorynCallHistoryService()
          .loadIncomingActiveCall(callId: widget.callId);

      if (!mounted) return;

      if (active == null) {
        // The call is stale, already ended, or unavailable
        LockScreenService.cancelNativeIncomingCall(
          widget.callId,
          reason: 'stale',
        );
        _exitSafely();
        return;
      }

      _call = active;
      final parts = active.displayName
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .take(2)
          .toList();
      final initials = parts.map((p) => p[0].toUpperCase()).join();

      setState(() {
        _user = VorynMockUser(
          backendUid: active.otherUid,
          customName: null,
          name: active.displayName,
          id: active.vorynId.startsWith('@')
              ? active.vorynId
              : '@${active.vorynId}',
          phone: '',
          email: '',
          presence: VorynPresenceStatus.online,
          initials: initials.isEmpty ? '?' : initials,
        );
      });
    } catch (_) {}
  }

  Future<void> _accept() async {
    if (_resolved) return;
    _resolved = true;
    _callSubscription?.unsubscribe();
    try {
      await VorynCallRuntimeCoordinator.runAcceptOnce(widget.callId, () async {
        final acceptMs = await LockScreenService.getElapsedRealtimeMs();
        final tracker = VorynCallLatencyTracker.start(
          callId: widget.callId,
          baseTimestampMs: acceptMs,
        );
        await tracker.stage('flutter_accept_received');
        final isVideo = _call?.callType == 'video';
        final callType = isVideo ? 'video' : 'audio';

        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          debugPrint(
            '[CALL ${widget.callId}] handing off foreground accept to VorynCallActivity',
          );
          await LockScreenService.acceptIncomingCall(
            callId: widget.callId,
            callType: callType,
            callerName: _user.name,
          );
          if (mounted) {
            _exitSafely();
          }
          return;
        }

        await LockScreenService.cancelNativeIncomingCall(
          widget.callId,
          reason: 'accept',
        );

        if (!mounted) return;

        if (isVideo) {
          context.pushReplacement(
            '/active-video-call/${widget.callId}',
            extra: {'user': _user},
          );
        } else {
          context.pushReplacement(
            '/active-audio-call/${widget.callId}',
            extra: {'user': _user},
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _decline() async {
    if (_resolved) return;
    _resolved = true;
    _callSubscription?.unsubscribe();
    VorynFirebaseMessaging.clearPendingIncomingCall(widget.callId);
    await LockScreenService.cancelNativeIncomingCall(
      widget.callId,
      reason: 'decline',
    );

    try {
      await const VorynCallService().decline(widget.callId);
    } catch (_) {}

    await _exitSafely();
  }

  @override
  void dispose() {
    _callSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _exitSafely() async {
    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) {
      await LockScreenService.moveCallTaskBehindKeyguard();
      return;
    }

    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/connect');
      }
    }
  }

  void _openQuickMessage() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF16191E),
      builder: (_) => QuickMessageSheet(user: _user),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[BOOT] IncomingCallScreen build');
    final colors = context.vorynColors;
    final isVideo = _call?.callType == 'video';

    final primaryName = _user.customName ?? _user.name;
    final secondaryText =
        _user.customName != null && _user.customName != _user.name
        ? '${_user.name} · ${_user.id}'
        : _user.id;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // Top Security Badge
              const Center(
                child: SecurityBadge(label: 'SECURE CALL · DIRECT TRANSPORT'),
              ),

              const Spacer(flex: 2),

              // Caller Identity: Concentric Acoustic Rings & Avatar
              CallAvatarRings(
                initials: _user.initials,
                size: 140,
                ringColor: colors.accent,
                badge: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222A),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0D0F12),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 16,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Primary Name
              Text(
                primaryName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 6),

              // Canonical Name / Voryn ID
              Text(
                secondaryText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  color: Colors.white60,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Incoming Call Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceRaised.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
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
                    const SizedBox(width: 8),
                    Text(
                      isVideo ? 'Incoming Video Call' : 'Incoming Audio Call',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'HD Opus',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Secondary Actions: Message & Remind
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PillAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Message',
                    onTap: _openQuickMessage,
                  ),
                  const SizedBox(width: 14),
                  _PillAction(
                    icon: Icons.alarm_rounded,
                    label: 'Remind',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reminder set for 15 minutes'),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const Spacer(flex: 2),

              // Big Accept & Decline Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Decline Button
                    _BigCallButton(
                      icon: Icons.call_end_rounded,
                      label: 'Decline',
                      color: const Color(0xFFDC2626),
                      glowColor: const Color(
                        0xFFDC2626,
                      ).withValues(alpha: 0.35),
                      onTap: _decline,
                    ),

                    // Swipe up indicator
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white38,
                          size: 20,
                        ),
                        Text(
                          'SWIPE UP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),

                    // Accept Button
                    _BigCallButton(
                      icon: isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      label: 'Accept',
                      color: const Color(0xFF16A34A),
                      glowColor: const Color(0xFF16A34A).withValues(alpha: 0.4),
                      onTap: _accept,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Home Gesture Pill
              Container(
                width: 130,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16191E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigCallButton extends StatelessWidget {
  const _BigCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.glowColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color glowColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: glowColor, blurRadius: 28, spreadRadius: 4),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(child: Icon(icon, size: 36, color: Colors.white)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
