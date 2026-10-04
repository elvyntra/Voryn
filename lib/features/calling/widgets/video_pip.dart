import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import '../../../core/theme/voryn_theme.dart';

class VideoPip extends StatefulWidget {
  const VideoPip({
    super.key,
    required this.videoTrack,
    this.isMirror = true,
    this.isMuted = false,
    this.isVideoEnabled = true,
    this.label = 'You',
    this.userInitials = 'YOU',
    this.onTap,
    this.controlsVisible = true,
  });

  final livekit.VideoTrack? videoTrack;
  final bool isMirror;
  final bool isMuted;
  final bool isVideoEnabled;
  final String label;
  final String userInitials;
  final VoidCallback? onTap;
  final bool controlsVisible;

  @override
  State<VideoPip> createState() => _VideoPipState();
}

class _VideoPipState extends State<VideoPip> {
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final isTabletOrWeb = MediaQuery.of(context).size.width > 600;
    final width = isTabletOrWeb ? 136.0 : 108.0;
    final height = isTabletOrWeb ? 190.0 : 152.0;

    final defaultBottom = widget.controlsVisible ? 190.0 : 36.0;

    final pipWidget = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF16191F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.isVideoEnabled && widget.videoTrack != null)
            livekit.VideoTrackRenderer(
              widget.videoTrack!,
              key: ValueKey(
                'pip_${widget.videoTrack!.sid ?? widget.videoTrack!.hashCode}',
              ),
              mirrorMode: widget.isMirror
                  ? livekit.VideoViewMirrorMode.mirror
                  : livekit.VideoViewMirrorMode.off,
              fit: livekit.VideoViewFit.cover,
            )
          else
            Container(
              color: const Color(0xFF1E222B),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: isTabletOrWeb ? 22 : 18,
                      backgroundColor: colors.surfaceRaised,
                      child: Text(
                        widget.userInitials,
                        style: TextStyle(
                          fontSize: isTabletOrWeb ? 14 : 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.isVideoEnabled ? 'Connecting…' : 'Camera off',
                      style: const TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),

          // Top right subtle swap icon
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                size: 14,
                color: Colors.white70,
              ),
            ),
          ),

          // Gradient bottom scrim
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 38,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Bottom info row (Label + Mute indicator)
          Positioned(
            left: 8,
            right: 8,
            bottom: 6,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ),
                if (widget.isMuted) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.mic_off_rounded,
                    size: 13,
                    color: Color(0xFFF87171),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      right: _offset?.dx ?? 18,
      bottom: _offset?.dy ?? defaultBottom,
      child: Tooltip(
        message: 'Tap to swap view',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onPanUpdate: (details) {
            setState(() {
              final current = _offset ?? Offset(18, defaultBottom);
              _offset = Offset(
                (current.dx - details.delta.dx).clamp(12.0, 240.0),
                (current.dy - details.delta.dy).clamp(24.0, 560.0),
              );
            });
          },
          child: pipWidget,
        ),
      ),
    );
  }
}
