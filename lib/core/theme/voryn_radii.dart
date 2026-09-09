import 'package:flutter/material.dart';

@immutable
class VorynRadii extends ThemeExtension<VorynRadii> {
  const VorynRadii({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.full,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double full;

  static const regular = VorynRadii(
    xs: 8,
    sm: 12,
    md: 16,
    lg: 20,
    xl: 28,
    full: 999,
  );

  @override
  VorynRadii copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? full,
  }) {
    return VorynRadii(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      full: full ?? this.full,
    );
  }

  @override
  VorynRadii lerp(ThemeExtension<VorynRadii>? other, double t) {
    if (other is! VorynRadii) return this;

    return VorynRadii(
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
      full: _lerp(full, other.full, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
