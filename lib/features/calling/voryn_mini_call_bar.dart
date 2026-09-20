import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import 'voryn_active_call_presentation_service.dart';

/// Global compact mini-call bar displayed in VorynShell when an active call is minimized.
///
/// Tapping anywhere on the bar restores the call to fullscreen without reconnecting.
class VorynMiniCallBar extends StatefulWidget {
  const VorynMiniCallBar({super.key, this.presentationService});

  final VorynActiveCallPresentationService? presentationService;

  @override
  State<VorynMiniCallBar> createState() => _VorynMiniCallBarState();
}

class _VorynMiniCallBarState extends State<VorynMiniCallBar>
    with SingleTickerProviderStateMixin {
  VorynActiveCallPresentationService get _service =>
      widget.presentationService ?? VorynActiveCallPresentationService.instance;

  Timer? _timer;
  String _formattedDuration = '00:00';
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _service.snapshotNotifier.addListener(_onSnapshotChanged);
    _onSnapshotChanged();
  }

  @override
  void dispose() {
    _service.snapshotNotifier.removeListener(_onSnapshotChanged);
    _stopTimer();
    _pulseController.dispose();
    super.dispose();
  }

  void _onSnapshotChanged() {
    final snapshot = _service.currentSnapshot;
    if (snapshot != null && snapshot.shouldShowMiniBar) {
      _startTimer(snapshot.startedAt);
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _stopTimer();
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _startTimer(int startedAt) {
    _updateTimer(startedAt);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateTimer(startedAt);
    });
  }

  void _updateTimer(int startedAt) {
    if (startedAt <= 0) {
      if (_formattedDuration != '00:00') {
        setState(() => _formattedDuration = '00:00');
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = (now - startedAt).clamp(0, 86400000);
    final duration = Duration(milliseconds: elapsedMs);

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    final formatted = hours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
    if (formatted != _formattedDuration && mounted) {
      setState(() => _formattedDuration = formatted);
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'V';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(1, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveCallSnapshot?>(
      valueListenable: _service.snapshotNotifier,
      builder: (context, snapshot, _) {
        if (snapshot == null || !snapshot.shouldShowMiniBar) {
          return const SizedBox.shrink();
        }

        final colors =
            Theme.of(context).extension<VorynColors>() ??
            (Theme.of(context).brightness == Brightness.light
                ? VorynColors.light
                : VorynColors.dark);
        final screenWidth = MediaQuery.of(context).size.width;
        final isWideScreen = screenWidth > 600;

        final isVideo = snapshot.callType == 'video';
        final initials = _getInitials(snapshot.displayName);

        final barContent = Material(
          color: colors.surfaceRaised,
          elevation: 4,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _service.returnToActiveCall(snapshot.callId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  // Call Avatar with Initials
                  VorynAvatar(initials: initials, size: VorynAvatarSize.small),
                  const SizedBox(width: 12),

                  // Call info: Display Name + Duration & Type
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // Subtle Pulsing Green Dot
                            FadeTransition(
                              opacity: _pulseController.drive(
                                Tween<double>(begin: 0.35, end: 1.0),
                              ),
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.success,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.call_rounded,
                              size: 13,
                              color: colors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formattedDuration,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Return / Maximize Icon Button
                  Semantics(
                    button: true,
                    label: 'Return to call',
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.border, width: 1),
                      ),
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: 16,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return Semantics(
          container: true,
          label:
              'Active call with ${snapshot.displayName}, duration $_formattedDuration. Tap to return.',
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
            child: isWideScreen
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: barContent,
                    ),
                  )
                : barContent,
          ),
        );
      },
    );
  }
}
