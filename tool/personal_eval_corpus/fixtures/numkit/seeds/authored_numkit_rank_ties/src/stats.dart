/// Small aggregate helpers that have to behave on empty and tied input.
class Stats {
  const Stats();

  /// Median of [values]. Returns null for empty input rather than 0, so a
  /// caller cannot mistake "no data" for "measured zero".
  double? median(List<num> values) {
    if (values.isEmpty) {
      return null;
    }
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle].toDouble();
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  /// Clamps [value] into [lower]..[upper], tolerating a reversed range.
  num clamp(num value, num lower, num upper) {
    final low = lower <= upper ? lower : upper;
    final high = lower <= upper ? upper : lower;
    if (value < low) return low;
    if (value > high) return high;
    return value;
  }

  /// Share of [part] in [whole] as a percentage, null when [whole] is zero.
  double? percentOf(num part, num whole) {
    if (whole == 0) {
      return null;
    }
    return part / whole * 100;
  }

  /// Ranks descending by score, breaking ties by ascending label so the order
  /// is stable across runs.
  List<String> rank(Map<String, int> scores) {
    final entries = scores.entries.toList()
      ..sort((left, right) {
        return right.value.compareTo(left.value);
      });
    return entries.map((entry) => entry.key).toList(growable: false);
  }
}
