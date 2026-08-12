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
    final parts = <String>[];
    if (duration.inDays > 0) parts.add('${duration.inDays}d');
    if (duration.inHours > 0) parts.add('${duration.inHours}h');
    if (duration.inMinutes > 0) parts.add('${duration.inMinutes}m');
    if (duration.inSeconds > 0) parts.add('${duration.inSeconds}s');
    return parts.join(' ');
  }

  /// Parses "1h 5m", "90s", "2d" and similar into a [Duration].
  ///
  /// Returns null for anything it does not fully understand, so a caller never
  /// silently treats a typo as zero.
  Duration? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final negative = trimmed.startsWith('-');
    final body = negative ? trimmed.substring(1) : trimmed;
    final pattern = RegExp(r'^(\d+)([dhms])$');

    var total = Duration.zero;
    var matched = 0;
    for (final token in body.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final match = pattern.firstMatch(token);
      if (match == null) {
        return null;
      }
      final value = int.parse(match.group(1)!);
      total += switch (match.group(2)!) {
        'd' => Duration(days: value),
        'h' => Duration(hours: value),
        'm' => Duration(minutes: value),
        _ => Duration(seconds: value),
      };
      matched += 1;
    }
    if (matched == 0) {
      return null;
    }
    return negative ? -total : total;
  }
}
