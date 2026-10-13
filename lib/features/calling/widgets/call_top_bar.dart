import 'package:flutter/material.dart';
import '../../../core/theme/voryn_theme.dart';

class CallTopBar extends StatelessWidget {
  const CallTopBar({
    super.key,
    required this.onMinimize,
    this.centerWidget,
    this.onAddParticipant,
    this.showAddParticipant = true,
    this.onToggleLayout,
    this.isSplitScreen = false,
  });

  final VoidCallback onMinimize;
  final Widget? centerWidget;
  final VoidCallback? onAddParticipant;
  final bool showAddParticipant;
  final VoidCallback? onToggleLayout;
  final bool isSplitScreen;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onMinimize,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            style: IconButton.styleFrom(
              backgroundColor: colors.surfaceRaised.withValues(alpha: 0.6),
              foregroundColor: colors.textPrimary,
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(44, 44),
            ),
            tooltip: 'Minimize call',
          ),
          if (onToggleLayout != null) ...[
            const SizedBox(width: 8),
            IconButton(
              key: const Key('layout_toggle_button'),
              onPressed: onToggleLayout,
              icon: Icon(
                isSplitScreen
                    ? Icons.picture_in_picture_alt_rounded
                    : Icons.splitscreen_rounded,
                size: 20,
              ),
              style: IconButton.styleFrom(
                backgroundColor: isSplitScreen
                    ? colors.accent.withValues(alpha: 0.8)
                    : colors.surfaceRaised.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(44, 44),
              ),
              tooltip: isSplitScreen
                  ? 'Switch to PiP View'
                  : 'Switch to 50/50 Split View',
            ),
          ],
          Expanded(
            child: centerWidget != null
                ? Center(child: centerWidget)
                : const SizedBox.shrink(),
          ),
          if (showAddParticipant)
            IconButton(
              onPressed: onAddParticipant,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
              style: IconButton.styleFrom(
                backgroundColor: colors.surfaceRaised.withValues(alpha: 0.6),
                foregroundColor: colors.textPrimary,
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(44, 44),
              ),
              tooltip: 'Add participant',
            )
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class SecurityBadge extends StatelessWidget {
  const SecurityBadge({super.key, this.label = 'SECURE CALL'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF10281E).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: Color(0xFF22C55E),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF22C55E),
            ),
          ),
        ],
      ),
    );
  }
}
