import 'package:caverno/features/project_farm/domain/roadmap_next_task_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourceText = '''
# Roadmap

### Recommended Next Slice

**Recommended next slice: RC1 signed-device evidence.** The latest main-side
work remains concentrated on Remote Coding.

| Remote Coding | RC1 | current | Add authenticated transport. |
''';
  final source = NormalizedSource(sourceText.split('\n'));

  ExtractedItem item(String quote, {String id = 'RC1', int line = 5}) =>
      ExtractedItem(id: id, title: 'Title', quote: quote, line: line);

  group('verifyItem', () {
    test('keeps a verbatim quote and records the source line', () {
      final verification = verifyItem(
        item('**Recommended next slice: RC1 signed-device evidence.**'),
        source,
      );

      expect(verification.verdict, QuoteVerdict.verified);
      expect(verification.sourceLine, 5);
      expect(verification.lineError, 0);
    });

    test('matches through dropped emphasis and a copied gutter', () {
      final verification = verifyItem(
        item('    5| Recommended next slice: RC1 signed-device evidence.'),
        source,
      );

      expect(verification.verdict, QuoteVerdict.verified);
      expect(verification.sourceLine, 5);
    });

    test('matches a quote that spans a line break', () {
      final verification = verifyItem(
        item(
          'RC1 signed-device evidence.** The latest main-side\n'
          'work remains concentrated',
        ),
        source,
      );

      expect(verification.verdict, QuoteVerdict.verified);
      expect(verification.sourceLine, 5);
    });

    test('rejects a fabricated quote', () {
      final verification = verifyItem(
        item('Recommended next slice: RC2 signed-device evidence.'),
        source,
      );

      expect(verification.verdict, QuoteVerdict.quoteNotFound);
      expect(verification.kept, isFalse);
    });

    test('rejects a real quote that does not carry the item id', () {
      final verification = verifyItem(
        item('The latest main-side', id: 'ANA4'),
        source,
      );

      expect(verification.verdict, QuoteVerdict.idNotInQuote);
    });

    test('records the occurrence nearest the reported line', () {
      expect(verifyItem(item('RC1', line: 8), source).sourceLine, 8);
      expect(verifyItem(item('RC1', line: 4), source).sourceLine, 5);
    });

    test('rejects an empty quote', () {
      expect(verifyItem(item('  '), source).verdict, QuoteVerdict.emptyQuote);
    });
  });

  group('outline', () {
    const lines = [
      '# Title',
      '',
      '```markdown',
      '# not a heading',
      '```',
      '## Active Focus',
      '### Recommended Next Slice',
      'body',
      '### In Progress',
      'table',
      '## Plan Mode Track',
      'text',
    ];
    final outline = outlineOf(lines);

    test('skips headings inside fenced code', () {
      expect(outline.map((heading) => heading.line), [1, 6, 7, 9, 11]);
    });

    test('bounds a section at the next heading of its level or higher', () {
      OutlineHeading at(int line) =>
          outline.firstWhere((heading) => heading.line == line);

      expect(sectionRange(outline, at(7), lines.length), (start: 7, end: 9));
      expect(sectionRange(outline, at(6), lines.length), (start: 6, end: 11));
      expect(sectionRange(outline, at(11), lines.length), (start: 11, end: 13));
    });

    test('resolves a named heading by text, nearest the reported line', () {
      expect(resolveHeading(outline, 'Recommended Next Slice', 30)?.line, 7);
      expect(resolveHeading(outline, '### Recommended Next Slice', 7)?.line, 7);
      expect(resolveHeading(outline, 'Next Slice', 7), isNull);
    });
  });

  test('decodeJsonObject tolerates a reasoning block and a fence', () {
    expect(decodeJsonObject('<think>x</think>\n```json\n{"a": 1}\n```'), {
      'a': 1,
    });
    expect(decodeJsonObject('not json'), isNull);
  });
}
