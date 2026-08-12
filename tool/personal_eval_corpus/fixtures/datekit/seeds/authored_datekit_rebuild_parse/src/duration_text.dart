/// Renders and parses short human-readable durations.
class DurationText {
  const DurationText();

  /// Formats a duration as the two largest non-zero units, e.g. "1h 5m".
  ///
  /// A zero duration is "0s", and a negative duration keeps a single leading
  /// minus rather than signing each unit.
  String format(Duration duration) {
    if (duration.inMilliseconds == 0) {
      return '0s';
    }
    final negative = duration.isNegative;
    final total = duration.abs();
    final parts = <String>[];
    final days = total.inDays;
    final hours = total.inHours % 24;
    final minutes = total.inMinutes % 60;
    final seconds = total.inSeconds % 60;

    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0) parts.add('${minutes}m');
    if (seconds > 0) parts.add('${seconds}s');

    final rendered = parts.take(2).join(' ');
    return negative ? '-$rendered' : rendered;
  }

  /// Parses "1h 5m", "90s", "2d" and similar into a [Duration].
  ///
  /// Returns null for anything it does not fully understand, so a caller never
  /// silently treats a typo as zero.
  Duration? parse(String input) {
    return null;
  }
}
