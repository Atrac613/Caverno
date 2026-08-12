import 'dart:io';

import '../src/money.dart';
import '../src/stats.dart';

/// Verifier for the `numkit` fixture. Exit 0 means every check passed.
void main(List<String> args) {
  final failures = <String>[];
  const stats = Stats();

  void check(String name, Object? actual, Object? expected) {
    final a = _describe(actual);
    final e = _describe(expected);
    if (a != e) {
      failures.add('$name\n  expected: $e\n  actual:   $a');
    }
  }

  // money_scale
  check(
    'scale rounds half away from zero',
    const Money(101).scale(0.5),
    const Money(51),
  );
  check(
    'scale rounds a negative half away from zero',
    const Money(-101).scale(0.5),
    const Money(-51),
  );
  check(
    'scale keeps an exact product',
    const Money(200).scale(0.5),
    const Money(100),
  );
  check(
    'scale rounds down below a half',
    const Money(100).scale(0.104),
    const Money(10),
  );

  // money_split
  check('split spreads the remainder', const Money(100).split(3), [
    const Money(34),
    const Money(33),
    const Money(33),
  ]);
  check('split of an exact amount is even', const Money(90).split(3), [
    const Money(30),
    const Money(30),
    const Money(30),
  ]);
  check(
    'split preserves the total',
    _sum(const Money(101).split(4)),
    const Money(101),
  );
  check(
    'split of a negative preserves the total',
    _sum(const Money(-100).split(3)),
    const Money(-100),
  );
  check('split by zero yields nothing', const Money(100).split(0), <Money>[]);

  // median
  check('median of an odd list', stats.median([3, 1, 2]), 2.0);
  check(
    'median of an even list averages the middle',
    stats.median([4, 1, 3, 2]),
    2.5,
  );
  check('median of empty input is null', stats.median(const []), null);
  check(
    'median does not reorder the caller list',
    _medianKeepsInput(stats),
    true,
  );

  // clamp
  check('clamp holds a value inside the range', stats.clamp(5, 1, 10), 5);
  check('clamp raises a low value', stats.clamp(-2, 1, 10), 1);
  check('clamp lowers a high value', stats.clamp(42, 1, 10), 10);
  check('clamp tolerates a reversed range', stats.clamp(5, 10, 1), 5);

  // percent
  check('percentOf computes a share', stats.percentOf(25, 200), 12.5);
  check('percentOf a zero whole is null', stats.percentOf(5, 0), null);
  check('percentOf handles a zero part', stats.percentOf(0, 200), 0.0);

  // rank
  check(
    'rank orders by descending score',
    stats.rank({'a': 1, 'b': 9, 'c': 5}),
    ['b', 'c', 'a'],
  );
  check('rank breaks ties by label', stats.rank({'b': 5, 'a': 5, 'c': 9}), [
    'c',
    'a',
    'b',
  ]);
  check('rank of an empty map is empty', stats.rank(const {}), <String>[]);

  if (failures.isEmpty) {
    stdout.writeln('numkit verify: all checks passed');
    exit(0);
  }
  stderr.writeln('numkit verify: ${failures.length} check(s) failed\n');
  for (final failure in failures) {
    stderr.writeln(failure);
    stderr.writeln('');
  }
  exit(1);
}

Money _sum(List<Money> parts) =>
    parts.fold(const Money(0), (total, part) => total + part);

bool _medianKeepsInput(Stats stats) {
  final input = <num>[3, 1, 2];
  stats.median(input);
  return input[0] == 3 && input[1] == 1 && input[2] == 2;
}

String _describe(Object? value) {
  if (value is List) {
    return '[${value.map(_describe).join(', ')}]';
  }
  return value is String ? '"$value"' : '$value';
}
