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
    this.card = const Color(0xFF1C1C20),
    this.primaryEmerald = const Color(0xFF008F66),
    this.deepEmerald = const Color(0xFF064E3B),
    this.forestGreen = const Color(0xFF065F46),
    this.softMint = const Color(0xFFD1FAE5),
  });

  final Color background;
  final Color backgroundSoft;
  final Color surface;
  final Color surfaceRaised;
  final Color surfacePressed;
  final Color card;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color iconMuted;
  final Color accent;
  /// Retained for backwards compatibility with existing UI components; maps to forestGreen.
  final Color accentViolet;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color disabled;

  // Canonical VoRyn Emerald Design System Tokens
  final Color primaryEmerald;
  final Color deepEmerald;
  final Color forestGreen;
  final Color softMint;

  static const dark = VorynColors(
    background: Color(0xFF0B0B0D),
    backgroundSoft: Color(0xFF111114),
    surface: Color(0xFF17171A),
    surfaceRaised: Color(0xFF202024),
    surfacePressed: Color(0xFF28282D),
    card: Color(0xFF1C1C20),
    border: Color(0xFF303036),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA8A8B3),
    textMuted: Color(0xFF71717A),
    iconMuted: Color(0xFF8E8E99),
    accent: Color(0xFF008F66),
    accentViolet: Color(0xFF065F46), // Mapped to forestGreen
    accentSoft: Color(0x33008F66),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFDC2626),
    disabled: Color(0xFF27272A),
    primaryEmerald: Color(0xFF008F66),
    deepEmerald: Color(0xFF064E3B),
    forestGreen: Color(0xFF065F46),
    softMint: Color(0xFFD1FAE5),
  );

  static const light = VorynColors(
    background: Color(0xFFFFFFFF),
    backgroundSoft: Color(0xFFF8FAF9),
    surface: Color(0xFFF8FAF9),
    surfaceRaised: Color(0xFFEEF3F0),
    surfacePressed: Color(0xFFE2EBE6),
    card: Color(0xFFF8FAF9),
    border: Color(0x1A102A23),
    textPrimary: Color(0xFF102A23),
    textSecondary: Color(0xFF325349),
    textMuted: Color(0xFF5E7E74),
    iconMuted: Color(0xFF5E7E74),
    accent: Color(0xFF008F66),
    accentViolet: Color(0xFF065F46), // Mapped to forestGreen
    accentSoft: Color(0x1F008F66),
    success: Color(0xFF008F66),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    disabled: Color(0xFFD1DCD6),
    primaryEmerald: Color(0xFF008F66),
    deepEmerald: Color(0xFF064E3B),
    forestGreen: Color(0xFF065F46),
    softMint: Color(0xFFD1FAE5),
  );

  LinearGradient get accentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryEmerald, forestGreen],
  );

  @override
  VorynColors copyWith({
    Color? background,
    Color? backgroundSoft,
    Color? surface,
    Color? surfaceRaised,
    Color? surfacePressed,
    Color? card,
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
    Color? primaryEmerald,
    Color? deepEmerald,
    Color? forestGreen,
    Color? softMint,
  }) {
    return VorynColors(
      background: background ?? this.background,
      backgroundSoft: backgroundSoft ?? this.backgroundSoft,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      card: card ?? this.card,
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
      primaryEmerald: primaryEmerald ?? this.primaryEmerald,
      deepEmerald: deepEmerald ?? this.deepEmerald,
      forestGreen: forestGreen ?? this.forestGreen,
      softMint: softMint ?? this.softMint,
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
      card: Color.lerp(card, other.card, t)!,
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
      primaryEmerald: Color.lerp(primaryEmerald, other.primaryEmerald, t)!,
      deepEmerald: Color.lerp(deepEmerald, other.deepEmerald, t)!,
      forestGreen: Color.lerp(forestGreen, other.forestGreen, t)!,
      softMint: Color.lerp(softMint, other.softMint, t)!,
    );
  }
}
