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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final buttonSize = screenWidth < 380 ? 48.0 : (screenWidth < 420 ? 54.0 : 60.0);
    final iconSize = screenWidth < 380 ? 20.0 : (screenWidth < 420 ? 23.0 : 26.0);

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

    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: buttonSize,
              child: Material(
                color: bg,
                shape: const CircleBorder(),
                elevation: isDestructive ? 4 : 0,
                shadowColor: isDestructive
                    ? const Color(0xFFF87171).withValues(alpha: 0.4)
                    : Colors.transparent,
                child: Center(child: Icon(icon, size: iconSize, color: fg)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: screenWidth < 380 ? 11 : 12,
                fontWeight: FontWeight.w500,
                color: isDestructive
                    ? const Color(0xFFFCA5A5)
                    : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxItems = row1.length > row2.length ? row1.length : row2.length;
    final isCompact = screenWidth < 380 || maxItems >= 5;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 20),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 16,
        vertical: isCompact ? 12 : 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF17171a).withValues(alpha: 0.92),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final btn in row1)
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: btn)),
            ],
          ),
          SizedBox(height: isCompact ? 14 : 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final btn in row2)
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: btn)),
            ],
          ),
        ],
      ),
    );
  }
}
