import 'package:flutter/material.dart';

@immutable
class VorynSpacing extends ThemeExtension<VorynSpacing> {
  const VorynSpacing({
    required this.zero,
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.screen,
  });

  final double zero;
  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double screen;

  static const regular = VorynSpacing(
    zero: 0,
    xxs: 4,
    xs: 8,
    sm: 12,
    md: 16,
    lg: 20,
    xl: 28,
    xxl: 36,
    screen: 24,
  );

  @override
  VorynSpacing copyWith({
    double? zero,
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? screen,
  }) {
    return VorynSpacing(
      zero: zero ?? this.zero,
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      screen: screen ?? this.screen,
    );
  }

  @override
  VorynSpacing lerp(ThemeExtension<VorynSpacing>? other, double t) {
    if (other is! VorynSpacing) return this;

    return VorynSpacing(
      zero: _lerp(zero, other.zero, t),
      xxs: _lerp(xxs, other.xxs, t),
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
      xxl: _lerp(xxl, other.xxl, t),
      screen: _lerp(screen, other.screen, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
