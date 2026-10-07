import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_response_scoring.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The diagnostic probes' pure scoring, extracted from the service (F5) so
/// each rule is pinned directly rather than through a whole probe run.
void main() {
  group('integer sequence', () {
    test('counts the in-order run and ignores noise between entries', () {
      expect(
        LiveLlmResponseScoring.matchedIntegerSequence(
          '1\n2\n\nnote\n3\n5\n4',
          length: 40,
        ),
        4,
      );
    });

    test('stops at the requested length', () {
      final content = List.generate(50, (i) => '${i + 1}').join('\n');
      expect(
        LiveLlmResponseScoring.matchedIntegerSequence(content, length: 40),
        40,
      );
    });
  });

  test('a single code fence is stripped, anything else is kept', () {
    expect(
      LiveLlmResponseScoring.stripSingleCodeFence('```dart\nfinal a = 1;\n```'),
      'final a = 1;',
    );
    expect(
      LiveLlmResponseScoring.stripSingleCodeFence('plain\r\ntext'),
      'plain\ntext',
    );
  });

  test('unified diff headers lose their a/ and b/ prefixes only', () {
    expect(
      LiveLlmResponseScoring.normalizeUnifiedDiffFileHeaders(
        '--- a/lib/x.dart\n+++ b/lib/x.dart\n@@ -1 +1 @@\n-a/old\n+b/new',
      ),
      '--- lib/x.dart\n+++ lib/x.dart\n@@ -1 +1 @@\n-a/old\n+b/new',
    );
  });

  group('first edit-format mismatch', () {
    String? mismatch(String expected, String actual) =>
        LiveLlmResponseScoring.firstEditFormatMismatch(
          expected: expected,
          actual: actual,
        );

    test('names the first differing line', () {
      expect(mismatch('a\nb', 'a\nc'), 'line 2: expected `b`, received `c`');
    });

    test('reports a short or long output at its end', () {
      expect(
        mismatch('a\nb', 'a'),
        'line 2: expected `b`, received end of output',
      );
      expect(
        mismatch('a', 'a\nb'),
        'line 2: expected end of output, received `b`',
      );
      expect(mismatch('same', 'same'), isNull);
    });
  });

  test('the service forwards chart scoring to the extracted rule', () {
    expect(
      LiveLlmDiagnosticService.matchedChartAnswers('78, 41, Dune, Cobalt'),
      LiveLlmResponseScoring.matchedChartAnswers('78, 41, Dune, Cobalt'),
    );
    expect(
      LiveLlmDiagnosticService.chartValueTolerance,
      LiveLlmResponseScoring.chartValueTolerance,
    );
  });

  test('quadrant colours are matched in order on the visible answer', () {
    const expected = ['yellow', 'blue', 'red', 'green'];
    expect(
      LiveLlmResponseScoring.matchedQuadrantColors(
        'Yellow, blue, red, green.',
        expected,
      ),
      4,
    );
    expect(
      LiveLlmResponseScoring.matchedQuadrantColors('blue, yellow', expected),
      1,
    );
    expect(
      LiveLlmResponseScoring.matchedQuadrantColors(
        '<think>yellow blue red green</think>no idea',
        expected,
      ),
      0,
      reason: 'the reasoning is not the answer',
    );
  });

  group('JSON object decoding', () {
    test('decodes the visible answer, not braces inside the reasoning', () {
      expect(
        LiveLlmResponseScoring.tryDecodeJsonObject(
          '<think>maybe {a}</think>Here: {"ok": true}',
        ),
        {'ok': true},
      );
    });

    test('returns null for anything that is not one object', () {
      expect(LiveLlmResponseScoring.tryDecodeJsonObject('[1, 2]'), isNull);
      expect(LiveLlmResponseScoring.tryDecodeJsonObject('no json'), isNull);
    });
  });

  test('string lists compare by value and order', () {
    expect(
      LiveLlmResponseScoring.stringListEquals(['a', 'b'], ['a', 'b']),
      isTrue,
    );
    expect(
      LiveLlmResponseScoring.stringListEquals(['b', 'a'], ['a', 'b']),
      isFalse,
    );
    expect(LiveLlmResponseScoring.stringListEquals('a', ['a']), isFalse);
  });
}
