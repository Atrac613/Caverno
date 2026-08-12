/// Integer-minor-unit money arithmetic.
///
/// Amounts are held in minor units (yen, cents) so no total ever accumulates
/// binary floating point error.
class Money {
  const Money(this.minorUnits);

  final int minorUnits;

  Money operator +(Money other) => Money(minorUnits + other.minorUnits);

  /// Applies a rate and rounds to the nearest minor unit, so a half lands away
  /// from zero rather than being discarded.
  Money scale(double rate) {
    return Money((minorUnits * rate).toInt());
  }

  /// Splits into [parts] shares that always sum back to the original.
  ///
  /// The remainder is spread one minor unit at a time over the leading shares,
  /// so 100 into 3 becomes [34, 33, 33] rather than losing a unit.
  List<Money> split(int parts) {
    if (parts <= 0) {
      return const <Money>[];
    }
    final base = minorUnits ~/ parts;
    var remainder = minorUnits - base * parts;
    final step = remainder.isNegative ? -1 : 1;
    return List<Money>.generate(parts, (index) {
      if (remainder != 0) {
        remainder -= step;
        return Money(base + step);
      }
      return Money(base);
    });
  }

  @override
  String toString() => '$minorUnits';

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;
}
