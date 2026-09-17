import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';

enum VorynButtonVariant { primary, secondary }

class VorynButton extends StatefulWidget {
  const VorynButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
    this.isLoading = false,
  }) : variant = VorynButtonVariant.primary;

  const VorynButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
    this.isLoading = false,
  }) : variant = VorynButtonVariant.secondary;

  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;
  final bool isLoading;
  final VorynButtonVariant variant;

  bool get isDisabled => onPressed == null || isLoading;

  @override
  State<VorynButton> createState() => _VorynButtonState();
}

class _VorynButtonState extends State<VorynButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final radii = context.vorynRadii;
    final isPrimary = widget.variant == VorynButtonVariant.primary;
    final background = switch ((
      isPrimary,
      widget.isDisabled,
      _pressed,
      _hovered,
    )) {
      (true, true, _, _) => colors.disabled,
      (true, false, true, _) => colors.accentViolet,
      (true, false, false, true) => colors.accentViolet,
      (true, false, false, false) => colors.accent,
      (false, true, _, _) => colors.surface,
      (false, false, true, _) => colors.surfacePressed,
      (false, false, false, true) => colors.surfacePressed,
      (false, false, false, false) => colors.surfaceRaised,
    };
    final foreground = widget.isDisabled
        ? colors.textMuted
        : colors.textPrimary;

    return Semantics(
      button: true,
      enabled: !widget.isDisabled,
      child: MouseRegion(
        cursor: widget.isDisabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: widget.isDisabled
            ? null
            : (_) => setState(() => _hovered = true),
        onExit: widget.isDisabled
            ? null
            : (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: widget.isDisabled
              ? null
              : (_) => setState(() => _pressed = true),
          onTapCancel: widget.isDisabled
              ? null
              : () => setState(() => _pressed = false),
          onTapUp: widget.isDisabled
              ? null
              : (_) => setState(() => _pressed = false),
          onTap: widget.isDisabled ? null : widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 56,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radii.md),
              border: Border.all(
                color: isPrimary ? Colors.transparent : colors.border,
              ),
              boxShadow: isPrimary && !widget.isDisabled
                  ? [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              child: widget.isLoading
                  ? SizedBox.square(
                      key: const ValueKey('loader'),
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(foreground),
                      ),
                    )
                  : Row(
                      key: const ValueKey('content'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.leadingIcon != null) ...[
                          Icon(widget.leadingIcon, color: foreground, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.labelLarge?.copyWith(color: foreground),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
