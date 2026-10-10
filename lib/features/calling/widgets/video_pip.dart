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
    this.offset,
    this.onOffsetChanged,
  });

  final livekit.VideoTrack? videoTrack;
  final bool isMirror;
  final bool isMuted;
  final bool isVideoEnabled;
  final String label;
  final String userInitials;
  final VoidCallback? onTap;
  final bool controlsVisible;
  final Offset? offset;
  final ValueChanged<Offset>? onOffsetChanged;

  @override
  State<VideoPip> createState() => _VideoPipState();
}

class _VideoPipState extends State<VideoPip> {
  Offset? _currentOffset;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentOffset = widget.offset;
  }

  @override
  void didUpdateWidget(covariant VideoPip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.offset != null && widget.offset != _currentOffset && !_isDragging) {
      _currentOffset = widget.offset;
    }
  }

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
        color: const Color(0xFF17171a),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
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
              color: const Color(0xFF17171a),
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
    ),
  );

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final padding = mediaQuery.padding;

    final minRight = padding.right + 12.0;
    final maxRight = (screenSize.width - width - padding.left - 12.0)
        .clamp(minRight, double.infinity);

    final minBottom = padding.bottom + (widget.controlsVisible ? 180.0 : 24.0);
    final maxBottom = (screenSize.height - height - padding.top - 24.0)
        .clamp(minBottom, double.infinity);

    final cur = _currentOffset;
    final resolvedRight = cur != null
        ? cur.dx.clamp(minRight, maxRight)
        : minRight;
    final resolvedBottom = cur != null
        ? cur.dy.clamp(minBottom, maxBottom)
        : defaultBottom.clamp(minBottom, maxBottom);

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      right: resolvedRight,
      bottom: resolvedBottom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: (_) {
          _isDragging = true;
          _currentOffset = Offset(resolvedRight, resolvedBottom);
          setState(() {});
        },
        onPanUpdate: (details) {
          final curDx = _currentOffset?.dx ?? resolvedRight;
          final curDy = _currentOffset?.dy ?? resolvedBottom;
          final nextDx = (curDx - details.delta.dx).clamp(minRight, maxRight);
          final nextDy = (curDy - details.delta.dy).clamp(minBottom, maxBottom);
          final nextOffset = Offset(nextDx, nextDy);
          _currentOffset = nextOffset;
          setState(() {});
          widget.onOffsetChanged?.call(nextOffset);
        },
        onPanEnd: (_) {
          setState(() => _isDragging = false);
        },
        onPanCancel: () {
          setState(() => _isDragging = false);
        },
        child: pipWidget,
      ),
    );
  }
}
