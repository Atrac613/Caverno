import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Caverno's theme. Dark is the designed-for default; light is kept
/// mode-complete. Component themes own padding, radius, and color so call sites
/// pass intent, not overrides. See `DESIGN.md` for the rationale and tokens.
///
/// Typography uses the platform default font for now; swapping in a bundled
/// face (Inter / JetBrains Mono) is a deliberate follow-up because Caverno is
/// offline-first and should not fetch fonts at runtime.
class AppTheme {
  AppTheme._();

  static final ThemeData dark = _build(Brightness.dark, AppSemanticColors.dark);
  static final ThemeData light =
      _build(Brightness.light, AppSemanticColors.light);

  static ThemeData _build(Brightness brightness, AppSemanticColors colors) {
    final isDark = brightness == Brightness.dark;

    const accent = Color(0xFF6D6AF0);
    const onAccent = Color(0xFFFFFFFF);
    const danger = Color(0xFFF85149);
    final bg = isDark ? const Color(0xFF0E0E11) : const Color(0xFFFAFAFB);
    final surface1 = isDark ? const Color(0xFF161619) : const Color(0xFFFFFFFF);
    final textPrimary =
        isDark ? const Color(0xFFECECEE) : const Color(0xFF1A1A1E);

    const radii = AppRadii.standard;
    const space = AppSpacing.standard;

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: onAccent,
      surface: surface1,
      onSurface: textPrimary,
      onSurfaceVariant: colors.textSecondary,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface1,
      surfaceContainer: colors.surface2,
      surfaceContainerHigh: colors.surface2,
      surfaceContainerHighest: colors.surface3,
      outline: colors.hairline,
      outlineVariant: colors.hairline,
      error: danger,
      onError: onAccent,
    );

    final textTheme = _textTheme(brightness, textPrimary, colors.textSecondary);

    final controlPadding =
        EdgeInsets.symmetric(horizontal: space.lg, vertical: space.md);
    const buttonTextStyle =
        TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.4);
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radii.sm));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      visualDensity: VisualDensity.compact,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: surface1,
      dividerColor: colors.hairline,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: surface1,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          padding: controlPadding,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.textSecondary,
          padding: controlPadding,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: colors.hairlineStrong),
          padding: controlPadding,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surface2,
        contentPadding:
            EdgeInsets.symmetric(horizontal: space.lg, vertical: space.lg),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: colors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: BorderSide(color: colors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.md),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface1,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.md),
          side: BorderSide(color: colors.hairline, width: 0.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface3,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface3,
        modalBackgroundColor: colors.surface3,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radii.lg)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface3,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.sm),
          side: BorderSide(color: colors.hairline, width: 0.5),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: space.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.sm),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: 0.5,
        space: 0.5,
      ),
      extensions: <ThemeExtension<dynamic>>[
        AppRadii.standard,
        AppSpacing.standard,
        colors,
      ],
    );
  }

  static TextTheme _textTheme(
    Brightness brightness,
    Color primary,
    Color secondary,
  ) {
    final base = (brightness == Brightness.dark
            ? Typography.material2021().white
            : Typography.material2021().black)
        .apply(bodyColor: primary, displayColor: primary);
    return base.copyWith(
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: primary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: primary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: primary,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: secondary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: primary,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: secondary,
      ),
    );
  }
}
