import 'package:flutter_test/flutter_test.dart';

import '../../tool/kc1_cutoff_exposure_census.dart';
import '../../tool/kc1_cutoff_oracle.dart';
import '../../tool/kc1_post_generation_check.dart';

/// KC1 slice 3 — the offline replay, before its numbers are read.
///
/// The claim this instrument exists to test is an asymmetry, not a rate: a
/// prompt block must choose which APIs to mention within a token budget, and a
/// post-generation check has no budget and no need to choose. So the assertion
/// that matters is that the index reaches a symbol the KC2 digest provably does
/// not, and the rest is making sure a mention is not counted as a use.

CutoffOracle _oracle() => CutoffOracle.resolve();

StaleSymbolIndex _index() =>
    StaleSymbolIndex.fromOracle(_oracle(), packages: const ['riverpod']);

ReplayedResponse _response(
  String content, {
  String caseId = 'flutter-pop-scope',
  String arm = 'bare',
  int repeat = 1,
}) => ReplayedResponse(
  caseId: caseId,
  arm: arm,
  repeat: repeat,
  content: content,
);

void main() {
  group('the index reaches further than a prompt block can', () {
    test('it holds a symbol the KC2 digest leaves out', () {
      final oracle = _oracle();

      expect(
        digestCovers(
          cutoffCases.firstWhere((c) => c.id == 'flutter-pop-scope'),
          oracle,
        ),
        isFalse,
        reason:
            'Precondition. WillPopScope was deprecated at v3.12, outside the '
            'digest window, and the census measured that case unmoved by the '
            'delta arm: 5/5 stale to 4/5.',
      );
      expect(
        _index().reasonFor('WillPopScope'),
        contains('PopScope'),
        reason:
            'The asymmetry being measured. A block chooses within a token '
            'budget; a check that reads the answer has neither budget nor '
            'anything to choose.',
      );
    });

    test('it is uncapped where the digest is capped', () {
      final oracle = _oracle();
      final digest = oracle.recentFlutterDeprecations().length;

      expect(digest, lessThanOrEqualTo(40));
      expect(
        _index().length,
        greaterThan(digest * 2),
        reason:
            'If these were the same size the comparison would be measuring the '
            'cap, not the approach.',
      );
    });

    test('package legacy symbols are in it too', () {
      expect(
        _index().reasonFor('StateNotifierProvider'),
        contains('legacy'),
      );
      expect(
        _index().reasonFor('NotifierProvider'),
        isNull,
        reason: 'The current idiom must never be flagged.',
      );
    });
  });

  group('a mention is not a use', () {
    test('comment lines, trailing comments and fences are stripped', () {
      const content = '''
```dart
// Do not use WillPopScope here.
return PopScope(canPop: false); // WillPopScope was the old way
```
''';

      expect(stripComments(content), isNot(contains('WillPopScope')));
      expect(stripComments(content), contains('PopScope'));
    });

    test('a symbol only in a comment is flagged but not counted as code', () {
      final report = replayPostGenerationCheck(
        responses: [
          _response('// WillPopScope is gone\nreturn PopScope(canPop: false);'),
        ],
        verdicts: const {'flutter-pop-scope|bare|1': 'correct'},
        index: _index(),
      );

      final row = report.rows.single;
      expect(row.flags.map((f) => f.symbol), contains('WillPopScope'));
      expect(row.codeFlags, isEmpty);
      expect(row.commentOnlyFlags, hasLength(1));
      expect(
        report.flaggedCorrect,
        0,
        reason:
            'Firing on prose that names the API it avoided would be the '
            'clearest way for this check to lose precision.',
      );
    });
  });

  group('against the labelled set', () {
    test('a stale usage is caught', () {
      final report = replayPostGenerationCheck(
        responses: [_response('return WillPopScope(onWillPop: () async => true);')],
        verdicts: const {'flutter-pop-scope|bare|1': 'stale'},
        index: _index(),
      );

      expect(report.caught, 1);
      expect(report.missed, 0);
      // Two flags, not one: the widget and its deprecated `onWillPop`
      // parameter. A prompt block has to spend a line on each; a check that
      // reads the answer gets both for the same nothing.
      expect(
        report.rows.single.codeFlags.map((flag) => flag.symbol),
        containsAll(<String>['WillPopScope', 'onWillPop']),
      );
    });

    test('a stale idiom that is not a symbol is counted as a miss', () {
      // Freezed's missing `abstract` is a codegen contract, not a deprecated
      // name, so no symbol index can see it. Counted rather than excluded: a
      // recall figure that quietly drops the cases it cannot reach is not one.
      final report = replayPostGenerationCheck(
        responses: [
          _response(
            '@freezed\nclass Point with _\$Point {}',
            caseId: 'freezed-abstract',
          ),
        ],
        verdicts: const {'freezed-abstract|bare|1': 'stale'},
        index: _index(),
      );

      expect(report.caught, 0);
      expect(report.missed, 1);
    });

    test('a common word collides, so this nominates and never decides', () {
      // `.withValues(alpha: 0.5)` is the *current* idiom, and `alpha` is a
      // deprecated field name somewhere in the SDK. A bare name has no receiver
      // type, so it collides. Measured: 14 of 30 correct answers flagged, almost
      // all on words like alpha, value, builder, of, blue.
      final report = replayPostGenerationCheck(
        responses: [
          _response(
            'base.withValues(alpha: 0.5)',
            caseId: 'color-with-values',
          ),
        ],
        verdicts: const {'color-with-values|bare|1': 'correct'},
        index: _index(),
      );

      expect(
        report.rows.single.codeFlags.map((flag) => flag.symbol),
        contains('alpha'),
        reason:
            'Pinned deliberately. If this ever stops firing, someone has made '
            'the index decide instead of nominate, and KC4 has to verify with '
            'LL11 deprecated_member_use -- which knows the receiver type -- '
            'rather than trust the name that triggered it.',
      );
    });

    test('an unlabelled response is carried, not silently dropped', () {
      final report = replayPostGenerationCheck(
        responses: [_response('return PopScope(canPop: false);')],
        verdicts: const {},
        index: _index(),
      );

      expect(report.rows.single.verdict, 'unlabelled');
      expect(report.labelledStale, isEmpty);
      expect(report.labelledCorrect, isEmpty);
    });
  });
}
