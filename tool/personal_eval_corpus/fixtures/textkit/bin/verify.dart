import 'dart:io';

import '../src/csv_row.dart';
import '../src/normalizer.dart';

/// Verifier for the `textkit` fixture.
///
/// Hand-rolled rather than `package:test` on purpose: an eval replay runs this
/// many times against two models, so it must not depend on pub resolution or
/// network access. Exit code 0 means every check passed; 1 means at least one
/// failed, and every failure is printed so the agent can see what broke.
void main(List<String> args) {
  final failures = <String>[];
  const normalizer = TextNormalizer();
  const csv = CsvRowParser();

  void check(String name, Object? actual, Object? expected) {
    final actualText = _describe(actual);
    final expectedText = _describe(expected);
    if (actualText != expectedText) {
      failures.add('$name\n  expected: $expectedText\n  actual:   $actualText');
    }
  }

  // collapse_whitespace
  check(
    'collapseWhitespace collapses runs',
    normalizer.collapseWhitespace('a   b\t\tc'),
    'a b c',
  );
  check(
    'collapseWhitespace trims the ends',
    normalizer.collapseWhitespace('  padded  '),
    'padded',
  );
  check(
    'collapseWhitespace handles newlines',
    normalizer.collapseWhitespace('line\n\nnext'),
    'line next',
  );

  // strip_trailing_punctuation
  check(
    'stripTrailingPunctuation removes a trailing period',
    normalizer.stripTrailingPunctuation('done.'),
    'done',
  );
  check(
    'stripTrailingPunctuation removes a run of punctuation',
    normalizer.stripTrailingPunctuation('really?!'),
    'really',
  );
  check(
    'stripTrailingPunctuation keeps inner punctuation',
    normalizer.stripTrailingPunctuation('a,b,c.'),
    'a,b,c',
  );
  check(
    'stripTrailingPunctuation keeps a decimal point',
    normalizer.stripTrailingPunctuation('3.5'),
    '3.5',
  );
  check(
    'stripTrailingPunctuation leaves clean input alone',
    normalizer.stripTrailingPunctuation('clean'),
    'clean',
  );

  // title_case
  check(
    'titleCase upper-cases each word',
    normalizer.titleCase('hello brave world'),
    'Hello Brave World',
  );
  check(
    'titleCase preserves inner capitals',
    normalizer.titleCase('open gPS reader'),
    'Open GPS Reader',
  );
  check(
    'titleCase normalizes spacing first',
    normalizer.titleCase('  spaced   out  '),
    'Spaced Out',
  );

  // csv_row
  check('csv splits plain fields', csv.parse('a,b,c'), ['a', 'b', 'c']);
  check('csv keeps empty fields', csv.parse('a,,c'), ['a', '', 'c']);
  check('csv unquotes a quoted field', csv.parse('"a",b'), ['a', 'b']);
  check('csv keeps a comma inside quotes', csv.parse('"a,b",c'), ['a,b', 'c']);
  check('csv unescapes a doubled quote', csv.parse('"say ""hi""",z'), [
    'say "hi"',
    'z',
  ]);
  check('csv keeps a trailing empty field', csv.parse('a,'), ['a', '']);

  // truncate
  check(
    'truncate leaves short input alone',
    normalizer.truncate('short', 10),
    'short',
  );
  check(
    'truncate leaves exact-length input alone',
    normalizer.truncate('exactly10!', 10),
    'exactly10!',
  );
  check(
    'truncate fits the ellipsis inside the budget',
    normalizer.truncate('abcdefghij', 5),
    'abcd\u2026',
  );
  check('truncate to zero is empty', normalizer.truncate('abc', 0), '');

  // slugify
  check(
    'slugify lowercases and hyphenates',
    normalizer.slugify('Hello World'),
    'hello-world',
  );
  check(
    'slugify collapses punctuation runs',
    normalizer.slugify('a --  b!!c'),
    'a-b-c',
  );
  check(
    'slugify trims edge hyphens',
    normalizer.slugify('  !leading and trailing!  '),
    'leading-and-trailing',
  );
  check(
    'slugify keeps digits',
    normalizer.slugify('Release 2026'),
    'release-2026',
  );

  if (failures.isEmpty) {
    stdout.writeln('textkit verify: all checks passed');
    exit(0);
  }
  stderr.writeln('textkit verify: ${failures.length} check(s) failed\n');
  for (final failure in failures) {
    stderr.writeln(failure);
    stderr.writeln('');
  }
  exit(1);
}

String _describe(Object? value) {
  if (value is List) {
    return '[${value.map(_describe).join(', ')}]';
  }
  return value is String ? '"$value"' : '$value';
}
