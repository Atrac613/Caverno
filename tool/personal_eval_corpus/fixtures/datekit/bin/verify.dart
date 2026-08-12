import 'dart:io';

import '../src/calendar.dart';
import '../src/duration_text.dart';

/// Verifier for the `datekit` fixture. Exit 0 means every check passed.
void main(List<String> args) {
  final failures = <String>[];
  const calendar = Calendar();
  const durations = DurationText();

  void check(String name, Object? actual, Object? expected) {
    final a = _describe(actual);
    final e = _describe(expected);
    if (a != e) {
      failures.add('$name\n  expected: $e\n  actual:   $a');
    }
  }

  // leap_year
  check('2024 is a leap year', calendar.isLeapYear(2024), true);
  check('2026 is not a leap year', calendar.isLeapYear(2026), false);
  check('1900 is not a leap year', calendar.isLeapYear(1900), false);
  check('2000 is a leap year', calendar.isLeapYear(2000), true);
  check('February 2024 has 29 days', calendar.daysInMonth(2024, 2), 29);
  check('February 2026 has 28 days', calendar.daysInMonth(2026, 2), 28);

  // add_months
  check(
    'addMonths clamps to the shorter month',
    calendar.addMonths(DateTime(2026, 1, 31), 1),
    DateTime(2026, 2, 28),
  );
  check(
    'addMonths clamps into a leap February',
    calendar.addMonths(DateTime(2024, 1, 31), 1),
    DateTime(2024, 2, 29),
  );
  check(
    'addMonths crosses a year boundary',
    calendar.addMonths(DateTime(2026, 11, 15), 3),
    DateTime(2027, 2, 15),
  );
  check(
    'addMonths goes backwards',
    calendar.addMonths(DateTime(2026, 3, 31), -1),
    DateTime(2026, 2, 28),
  );

  // days_between
  check(
    'daysBetween counts whole days',
    calendar.daysBetween(DateTime(2026, 3, 1), DateTime(2026, 3, 15)),
    14,
  );
  check(
    'daysBetween ignores the time of day',
    calendar.daysBetween(
      DateTime(2026, 3, 1, 23, 59),
      DateTime(2026, 3, 2, 0, 1),
    ),
    1,
  );
  check(
    'daysBetween is negative going backwards',
    calendar.daysBetween(DateTime(2026, 3, 15), DateTime(2026, 3, 1)),
    -14,
  );

  // iso_week
  check(
    '2026-01-01 is ISO week 1',
    calendar.isoWeekNumber(DateTime(2026, 1, 1)),
    1,
  );
  check(
    '2026-12-31 is ISO week 53',
    calendar.isoWeekNumber(DateTime(2026, 12, 31)),
    53,
  );
  check(
    '2027-01-03 is ISO week 53',
    calendar.isoWeekNumber(DateTime(2027, 1, 3)),
    53,
  );

  // duration_format
  check(
    'format renders two units',
    durations.format(const Duration(hours: 1, minutes: 5)),
    '1h 5m',
  );
  check(
    'format drops units past the second',
    durations.format(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)),
    '2d 3h',
  );
  check('format renders zero', durations.format(Duration.zero), '0s');
  check(
    'format signs a negative once',
    durations.format(const Duration(minutes: -90)),
    '-1h 30m',
  );
  check(
    'format skips empty leading units',
    durations.format(const Duration(seconds: 45)),
    '45s',
  );

  // duration_parse
  check(
    'parse reads a compound duration',
    durations.parse('1h 5m'),
    const Duration(hours: 1, minutes: 5),
  );
  check(
    'parse reads a single unit',
    durations.parse('90s'),
    const Duration(seconds: 90),
  );
  check(
    'parse reads a negative duration',
    durations.parse('-2h'),
    const Duration(hours: -2),
  );
  check('parse rejects a typo', durations.parse('1x'), null);
  check('parse rejects a partial typo', durations.parse('1h 5x'), null);
  check('parse rejects empty input', durations.parse('   '), null);
  check(
    'parse round-trips format',
    durations.parse(durations.format(const Duration(days: 1, hours: 2))),
    const Duration(days: 1, hours: 2),
  );

  if (failures.isEmpty) {
    stdout.writeln('datekit verify: all checks passed');
    exit(0);
  }
  stderr.writeln('datekit verify: ${failures.length} check(s) failed\n');
  for (final failure in failures) {
    stderr.writeln(failure);
    stderr.writeln('');
  }
  exit(1);
}

String _describe(Object? value) {
  if (value is DateTime) {
    return '${value.year}-${_two(value.month)}-${_two(value.day)}';
  }
  if (value is Duration) {
    return '${value.inMilliseconds}ms';
  }
  return value is String ? '"$value"' : '$value';
}

String _two(int value) => value.toString().padLeft(2, '0');
