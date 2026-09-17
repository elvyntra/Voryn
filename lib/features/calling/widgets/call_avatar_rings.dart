import 'package:flutter/material.dart';
import '../../../core/theme/voryn_theme.dart';

class CallAvatarRings extends StatelessWidget {
  const CallAvatarRings({
    super.key,
    required this.initials,
    this.size = 140.0,
    this.badge,
    this.ringColor,
    this.isPulsing = true,
  });

  final String initials;
  final double size;
  final Widget? badge;
  final Color? ringColor;
  final bool isPulsing;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final primaryRing = ringColor ?? colors.accent;

    return SizedBox(
      width: size + 80,
      height: size + 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outermost subtle acoustic ring
          Container(
            width: size + 76,
            height: size + 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: primaryRing.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
          ),
          // Intermediate ring
          Container(
            width: size + 44,
            height: size + 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: primaryRing.withValues(alpha: 0.16),
                width: 1.5,
              ),
            ),
          ),
          // Inner acoustic glowing ring
          Container(
            width: size + 16,
            height: size + 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primaryRing.withValues(alpha: 0.22),
                  primaryRing.withValues(alpha: 0.0),
                ],
              ),
              border: Border.all(
                color: primaryRing.withValues(alpha: 0.35),
                width: 2.0,
              ),
            ),
          ),
          // Main avatar
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E222B),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (badge != null) Positioned(right: 4, bottom: 4, child: badge!),
            ],
          ),
        ],
      ),
    );
  }
}
