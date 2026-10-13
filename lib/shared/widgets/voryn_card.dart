import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';

class VorynSurface extends StatelessWidget {
  const VorynSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final radii = context.vorynRadii;
    final spacing = context.vorynSpacing;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(spacing.md),
        child: child,
      ),
    );
  }
}

class VorynCard extends StatefulWidget {
  const VorynCard({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.padding,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final bool enabled;

  @override
  State<VorynCard> createState() => _VorynCardState();
}

class _VorynCardState extends State<VorynCard> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onPressed != null || widget.onLongPress != null);

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final radii = context.vorynRadii;
    final spacing = context.vorynSpacing;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _interactive ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: _interactive ? () => setState(() => _pressed = false) : null,
      onTapUp: _interactive ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onPressed : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: widget.padding ?? EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: _pressed ? colors.surfacePressed : colors.surface,
          borderRadius: BorderRadius.circular(radii.lg),
          border: Border.all(color: colors.border),
        ),
        child: Opacity(opacity: widget.enabled ? 1 : 0.48, child: widget.child),
      ),
    );
  }
}
