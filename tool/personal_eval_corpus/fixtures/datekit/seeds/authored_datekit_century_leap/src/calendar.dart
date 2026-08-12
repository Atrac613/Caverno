/// Calendar arithmetic that avoids the usual month-length traps.
class Calendar {
  const Calendar();

  /// Proleptic Gregorian leap year rule.
  bool isLeapYear(int year) {
    if (year % 4 != 0) return false;
    return true;
  }

  int daysInMonth(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && isLeapYear(year)) {
      return 29;
    }
    return lengths[month - 1];
  }

  /// Adds [months], clamping the day to the target month's length so
  /// 2026-01-31 + 1 month lands on 2026-02-28 rather than rolling into March.
  DateTime addMonths(DateTime from, int months) {
    final totalMonths = from.year * 12 + (from.month - 1) + months;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final day = from.day <= daysInMonth(year, month)
        ? from.day
        : daysInMonth(year, month);
    return DateTime(year, month, day);
  }

  /// Whole days between two dates, ignoring the time of day.
  int daysBetween(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return end.difference(start).inDays;
  }

  /// ISO-8601 week number. Week 1 is the week containing the first Thursday.
  int isoWeekNumber(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    // Shift to the Thursday of this ISO week, which always sits in the year
    // the week belongs to.
    final thursday = day.add(Duration(days: 4 - _isoWeekday(day)));
    final firstOfYear = DateTime(thursday.year, 1, 1);
    final dayOfYear = thursday.difference(firstOfYear).inDays + 1;
    return ((dayOfYear - 1) ~/ 7) + 1;
  }

  int _isoWeekday(DateTime date) => date.weekday;
}
