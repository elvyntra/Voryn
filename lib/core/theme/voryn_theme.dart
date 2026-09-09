import 'package:flutter/material.dart';

import 'voryn_colors.dart';
import 'voryn_radii.dart';
import 'voryn_spacing.dart';

export 'voryn_colors.dart';
export 'voryn_icons.dart';
export 'voryn_radii.dart';
export 'voryn_spacing.dart';

extension VorynThemeContext on BuildContext {
  VorynColors get vorynColors => Theme.of(this).extension<VorynColors>()!;
  VorynSpacing get vorynSpacing => Theme.of(this).extension<VorynSpacing>()!;
  VorynRadii get vorynRadii => Theme.of(this).extension<VorynRadii>()!;
}

class VorynTheme {
  const VorynTheme._();

  static ThemeData get dark =>
      _buildTheme(brightness: Brightness.dark, colors: VorynColors.dark);

  static ThemeData get light =>
      _buildTheme(brightness: Brightness.light, colors: VorynColors.light);

  static ThemeData _buildTheme({
    required Brightness brightness,
    required VorynColors colors,
  }) {
    final textTheme = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: Colors.white,
        secondary: colors.accentViolet,
        onSecondary: Colors.white,
        error: colors.danger,
        onError: Colors.white,
        surface: colors.surface,
        onSurface: colors.textPrimary,
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
        VorynSpacing.regular,
        VorynRadii.regular,
      ],
      textTheme: textTheme,
      iconTheme: IconThemeData(color: colors.textSecondary, size: 22),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        hintStyle: textTheme.bodyLarge?.copyWith(color: colors.textMuted),
        labelStyle: textTheme.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VorynRadii.regular.md),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VorynRadii.regular.md),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VorynRadii.regular.md),
          borderSide: BorderSide(color: colors.accent, width: 1.4),
        ),
      ),
    );
  }

  static TextTheme _textTheme(VorynColors colors) {
    const family = 'Roboto';

    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: family,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.05,
        color: colors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: family,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.14,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: family,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: family,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: colors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.42,
        color: colors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontFamily: family,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: family,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.15,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: family,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: colors.textMuted,
      ),
    );
  }
}
