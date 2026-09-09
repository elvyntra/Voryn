import 'package:flutter/material.dart';

@immutable
class VorynColors extends ThemeExtension<VorynColors> {
  const VorynColors({
    required this.background,
    required this.backgroundSoft,
    required this.surface,
    required this.surfaceRaised,
    required this.surfacePressed,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.iconMuted,
    required this.accent,
    required this.accentViolet,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.disabled,
  });

  final Color background;
  final Color backgroundSoft;
  final Color surface;
  final Color surfaceRaised;
  final Color surfacePressed;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color iconMuted;
  final Color accent;
  final Color accentViolet;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color disabled;

  static const dark = VorynColors(
    background: Color(0xFF050507),
    backgroundSoft: Color(0xFF0A0B10),
    surface: Color(0xFF12131A),
    surfaceRaised: Color(0xFF1A1B24),
    surfacePressed: Color(0xFF232431),
    border: Color(0x1FFFFFFF),
    textPrimary: Color(0xFFF8F8FB),
    textSecondary: Color(0xFFB9BBC6),
    textMuted: Color(0xFF7C7F8D),
    iconMuted: Color(0xFF8D90A0),
    accent: Color(0xFF6C7CFF),
    accentViolet: Color(0xFF8B5CF6),
    accentSoft: Color(0x336C7CFF),
    success: Color(0xFF32D583),
    warning: Color(0xFFFFB84D),
    danger: Color(0xFFFF4D5E),
    disabled: Color(0xFF343541),
  );

  static const light = VorynColors(
    background: Color(0xFFF7F7FB),
    backgroundSoft: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF1F2F7),
    surfacePressed: Color(0xFFE7E9F3),
    border: Color(0x1A111827),
    textPrimary: Color(0xFF11131A),
    textSecondary: Color(0xFF4C5263),
    textMuted: Color(0xFF7A8194),
    iconMuted: Color(0xFF697083),
    accent: Color(0xFF5D6BFF),
    accentViolet: Color(0xFF7C3AED),
    accentSoft: Color(0x245D6BFF),
    success: Color(0xFF12B76A),
    warning: Color(0xFFF79009),
    danger: Color(0xFFF04438),
    disabled: Color(0xFFD9DCE8),
  );

  LinearGradient get accentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentViolet],
  );

  @override
  VorynColors copyWith({
    Color? background,
    Color? backgroundSoft,
    Color? surface,
    Color? surfaceRaised,
    Color? surfacePressed,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? iconMuted,
    Color? accent,
    Color? accentViolet,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? disabled,
  }) {
    return VorynColors(
      background: background ?? this.background,
      backgroundSoft: backgroundSoft ?? this.backgroundSoft,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      iconMuted: iconMuted ?? this.iconMuted,
      accent: accent ?? this.accent,
      accentViolet: accentViolet ?? this.accentViolet,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      disabled: disabled ?? this.disabled,
    );
  }

  @override
  VorynColors lerp(ThemeExtension<VorynColors>? other, double t) {
    if (other is! VorynColors) return this;

    return VorynColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundSoft: Color.lerp(backgroundSoft, other.backgroundSoft, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfacePressed: Color.lerp(surfacePressed, other.surfacePressed, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentViolet: Color.lerp(accentViolet, other.accentViolet, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
    );
  }
}
