import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import '../../../core/theme/voryn_theme.dart';

class VideoPip extends StatefulWidget {
  const VideoPip({
    super.key,
    required this.localTrack,
    this.isMuted = false,
    this.isCameraEnabled = true,
    this.userInitials = 'ME',
  });

  final livekit.VideoTrack? localTrack;
  final bool isMuted;
  final bool isCameraEnabled;
  final String userInitials;

  @override
  State<VideoPip> createState() => _VideoPipState();
}

class _VideoPipState extends State<VideoPip> {
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    const width = 106.0;
    const height = 148.0;

    final pipWidget = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF16191F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.isCameraEnabled && widget.localTrack != null)
            livekit.VideoTrackRenderer(
              widget.localTrack!,
              key: ValueKey(
                widget.localTrack!.sid ?? widget.localTrack!.hashCode,
              ),
              mirrorMode: livekit.VideoViewMirrorMode.mirror,
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
                      radius: 18,
                      backgroundColor: colors.surfaceRaised,
                      child: Text(
                        widget.userInitials,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Camera off',
                      style: TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          // Gradient bottom scrim
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Bottom info row (You + Mute indicator)
          Positioned(
            left: 8,
            right: 8,
            bottom: 6,
            child: Row(
              children: [
                const Text(
                  'You',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const Spacer(),
                if (widget.isMuted)
                  const Icon(
                    Icons.mic_off_rounded,
                    size: 13,
                    color: Color(0xFFF87171),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Positioned(
      right: _offset?.dx ?? 18,
      bottom: _offset?.dy ?? 190,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final current = _offset ?? const Offset(18, 190);
            _offset = Offset(
              (current.dx - details.delta.dx).clamp(12.0, 240.0),
              (current.dy - details.delta.dy).clamp(140.0, 520.0),
            );
          });
        },
        child: pipWidget,
      ),
    );
  }
}
