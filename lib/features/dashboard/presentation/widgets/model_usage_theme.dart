import 'package:flutter/material.dart';

/// Colors and number formats shared by the model-usage charts and list.
///
/// Series colors are assigned by rank (largest first) rather than by hashing
/// the model name, so the legend, the share bar, and the daily columns always
/// agree and the biggest consumer is always the most prominent hue.
class ModelUsageTheme {
  ModelUsageTheme._();

  /// Hue offsets from the theme's primary, so the palette follows the app's
  /// accent in both light and dark instead of being hardcoded.
  static const List<double> _hueOffsets = [0, 42, -38, 84, -76, 126, 160, -118];

  static Color seriesColor(BuildContext context, int rank) {
    final primary = HSLColor.fromColor(Theme.of(context).colorScheme.primary);
    final offset = _hueOffsets[rank % _hueOffsets.length];
    // Later ranks also step down in saturation so a long legend stays legible.
    final fade = (rank ~/ _hueOffsets.length) * 0.18;
    return primary
        .withHue((primary.hue + offset) % 360)
        .withSaturation((primary.saturation - fade).clamp(0.25, 1.0))
        .withLightness(primary.lightness.clamp(0.35, 0.72))
        .toColor();
  }

  /// Compact token counts: 1.27B, 142M, 16.2K, 940.
  static String compactTokens(int value) {
    if (value < 0) return '0';
    if (value >= 1000000000) return '${_round(value / 1000000000)}B';
    if (value >= 1000000) return '${_round(value / 1000000)}M';
    if (value >= 1000) return '${_round(value / 1000)}K';
    return '$value';
  }

  /// Percentages as shown in the breakdown: 60.7%, 0.0%.
  static String percent(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

  /// Request latency: 820ms, 12.4s.
  static String duration(int milliseconds) {
    if (milliseconds < 1000) return '${milliseconds}ms';
    return '${(milliseconds / 1000).toStringAsFixed(1)}s';
  }

  static String _round(double value) {
    // Keep three significant figures, matching how token totals read best.
    if (value >= 100) return value.toStringAsFixed(0);
    if (value >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }
}
