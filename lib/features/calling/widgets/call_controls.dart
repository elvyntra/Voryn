import 'package:flutter/material.dart';
import '../../../core/theme/voryn_theme.dart';

class CallControlButton extends StatelessWidget {
  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.isActive = false,
    this.activeColor,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isActive;
  final Color? activeColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    Color bg;
    Color fg;

    if (isDestructive) {
      bg = const Color(0xFFF87171).withValues(alpha: 0.9);
      fg = const Color(0xFF1A0808);
    } else if (isActive) {
      bg = activeColor ?? colors.accent;
      fg = Colors.white;
    } else {
      bg = colors.surfaceRaised.withValues(alpha: 0.85);
      fg = foregroundColor ?? colors.textPrimary;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 60,
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            elevation: isDestructive ? 4 : 0,
            shadowColor: isDestructive
                ? const Color(0xFFF87171).withValues(alpha: 0.4)
                : Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Center(child: Icon(icon, size: 26, color: fg)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDestructive
                ? const Color(0xFFFCA5A5)
                : colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class CallControlTray extends StatelessWidget {
  const CallControlTray({super.key, required this.row1, required this.row2});

  final List<Widget> row1;
  final List<Widget> row2;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF14171D).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.border.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: row1),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: row2),
        ],
      ),
    );
  }
}
