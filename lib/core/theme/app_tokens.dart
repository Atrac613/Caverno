import 'package:flutter/material.dart';

/// Bundled monospace family (assets/fonts/JetBrainsMono-*.ttf). Use this for all
/// code, diff, SHA, path, and log rendering instead of the generic 'monospace'
/// alias, which resolves to an inconsistent per-OS face.
const String kMonoFontFamily = 'JetBrainsMono';

/// Design tokens for Caverno, exposed as [ThemeExtension]s so a single source
/// of truth travels with [ThemeData] and interpolates on theme changes.
///
/// Values mirror the machine-readable frontmatter in `DESIGN.md`. Read them via
/// the [AppThemeContext] getters (`context.radii`, `context.space`,
/// `context.appColors`) or `Theme.of(context).extension<T>()`.

/// Corner-radius scale. Modest by design — Material's default dialog radius (28)
/// reads too soft for a dense developer tool.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
  });

  /// Chips, code blocks, diff tiles, badges.
  final double xs;

  /// Buttons, list rows, small controls.
  final double sm;

  /// Cards, text fields, inputs.
  final double md;

  /// Dialogs, bottom sheets.
  final double lg;

  /// The single radius scale; identical across light/dark.
  static const AppRadii standard = AppRadii(xs: 4, sm: 6, md: 10, lg: 14);

  @override
  AppRadii copyWith({double? xs, double? sm, double? md, double? lg}) {
    return AppRadii(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
    );
  }

  @override
  AppRadii lerp(AppRadii? other, double t) {
    if (other is! AppRadii) return this;
    return AppRadii(
      xs: lerpDouble(xs, other.xs, t),
      sm: lerpDouble(sm, other.sm, t),
      md: lerpDouble(md, other.md, t),
      lg: lerpDouble(lg, other.lg, t),
    );
  }
}

/// Spacing scale on a 4px base, tuned for compact density. Replaces ad-hoc
/// `EdgeInsets` literals.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.xxxl,
  });

  final double xxs; // 2
  final double xs; // 4
  final double sm; // 6
  final double md; // 8
  final double lg; // 12
  final double xl; // 16
  final double xxl; // 24
  final double xxxl; // 32

  /// The single spacing scale; identical across light/dark.
  static const AppSpacing standard = AppSpacing(
    xxs: 2,
    xs: 4,
    sm: 6,
    md: 8,
    lg: 12,
    xl: 16,
    xxl: 24,
    xxxl: 32,
  );

  @override
  AppSpacing copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? xxxl,
  }) {
    return AppSpacing(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      xxxl: xxxl ?? this.xxxl,
    );
  }

  @override
  AppSpacing lerp(AppSpacing? other, double t) {
    if (other is! AppSpacing) return this;
    return AppSpacing(
      xxs: lerpDouble(xxs, other.xxs, t),
      xs: lerpDouble(xs, other.xs, t),
      sm: lerpDouble(sm, other.sm, t),
      md: lerpDouble(md, other.md, t),
      lg: lerpDouble(lg, other.lg, t),
      xl: lerpDouble(xl, other.xl, t),
      xxl: lerpDouble(xxl, other.xxl, t),
      xxxl: lerpDouble(xxxl, other.xxxl, t),
    );
  }
}

/// Semantic colors Material's [ColorScheme] cannot express: stepped surfaces,
/// hairlines, the muted text ramp, state colors, diff washes, and the accent
/// interaction states. Mode-specific — see [dark] / [light].
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.surface2,
    required this.surface3,
    required this.hairline,
    required this.hairlineStrong,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.diffAddedBg,
    required this.diffRemovedBg,
    required this.accentHover,
    required this.accentPressed,
  });

  /// Raised cards, inputs, panels (one step above [ColorScheme.surface]).
  final Color surface2;

  /// Popovers, menus, dialogs (the highest in-app surface).
  final Color surface3;

  /// Default 0.5px divider / edge.
  final Color hairline;

  /// Hover / emphasized divider.
  final Color hairlineStrong;

  /// Supporting text, timestamps.
  final Color textSecondary;

  /// Placeholders, captions, metadata.
  final Color textMuted;

  /// Genuine success state only (never decoration).
  final Color success;

  /// Genuine warning state only.
  final Color warning;

  /// Wash behind added-line / success text in diff surfaces.
  final Color diffAddedBg;

  /// Wash behind removed-line / danger text in diff surfaces.
  final Color diffRemovedBg;

  /// Accent hover state (pairs with [ColorScheme.primary]).
  final Color accentHover;

  /// Accent pressed state.
  final Color accentPressed;

  static const AppSemanticColors dark = AppSemanticColors(
    surface2: Color(0xFF1D1D21),
    surface3: Color(0xFF26262B),
    hairline: Color(0xFF2A2A30),
    hairlineStrong: Color(0xFF36363D),
    textSecondary: Color(0xFFA2A2AC),
    textMuted: Color(0xFF6E6E78),
    success: Color(0xFF3FB950),
    warning: Color(0xFFD29922),
    diffAddedBg: Color(0x262EA043),
    diffRemovedBg: Color(0x26F85149),
    accentHover: Color(0xFF5B57E8),
    accentPressed: Color(0xFF4A46D6),
  );

  /// Mode-complete light counterpart; dark is the designed-for default.
  static const AppSemanticColors light = AppSemanticColors(
    surface2: Color(0xFFF4F4F6),
    surface3: Color(0xFFFFFFFF),
    hairline: Color(0xFFE4E4E8),
    hairlineStrong: Color(0xFFD4D4DA),
    textSecondary: Color(0xFF5C5C66),
    textMuted: Color(0xFF9A9AA4),
    success: Color(0xFF1A7F37),
    warning: Color(0xFF9A6700),
    diffAddedBg: Color(0x1A1A7F37),
    diffRemovedBg: Color(0x1ACF222E),
    accentHover: Color(0xFF5B57E8),
    accentPressed: Color(0xFF4A46D6),
  );

  @override
  AppSemanticColors copyWith({
    Color? surface2,
    Color? surface3,
    Color? hairline,
    Color? hairlineStrong,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? diffAddedBg,
    Color? diffRemovedBg,
    Color? accentHover,
    Color? accentPressed,
  }) {
    return AppSemanticColors(
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      diffAddedBg: diffAddedBg ?? this.diffAddedBg,
      diffRemovedBg: diffRemovedBg ?? this.diffRemovedBg,
      accentHover: accentHover ?? this.accentHover,
      accentPressed: accentPressed ?? this.accentPressed,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      diffAddedBg: Color.lerp(diffAddedBg, other.diffAddedBg, t)!,
      diffRemovedBg: Color.lerp(diffRemovedBg, other.diffRemovedBg, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
    );
  }
}

/// Linear interpolation for token doubles, defaulting to a non-null result.
double lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// Ergonomic token access from a [BuildContext].
extension AppThemeContext on BuildContext {
  AppRadii get radii => Theme.of(this).extension<AppRadii>() ?? AppRadii.standard;
  AppSpacing get space =>
      Theme.of(this).extension<AppSpacing>() ?? AppSpacing.standard;
  AppSemanticColors get appColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.dark;
}
