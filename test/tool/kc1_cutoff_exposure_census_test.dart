import 'package:flutter_test/flutter_test.dart';

import '../../tool/kc1_cutoff_exposure_census.dart';
import '../../tool/kc1_cutoff_oracle.dart';

/// KC1 first slice — the instrument, before the number it produces.
///
/// Two things are being defended here, and they are not the same thing.
///
/// The scoring has to separate truth from grounding, because a correct claim
/// made with nothing to ground it and a stale one made with nothing to ground
/// it are different findings that a single "did it get it right" number
/// destroys. That is an acceptance criterion, asserted directly.
///
/// And the *fixtures* have to be backed by the installed toolchain rather than
/// by the author's beliefs. This is a cutoff instrument: if the fixture set is
/// allowed to declare which idiom is expired, the run compares one person's
/// 2026 beliefs with a model's and reports the difference as staleness. The
/// oracle is what stops that, so the oracle is tested against real disk.

CutoffOracle _oracle() => CutoffOracle.resolve();

CutoffCase _caseNamed(String id) =>
    cutoffCases.firstWhere((testCase) => testCase.id == id);

ClaimRecord _score(
  String id,
  String response, {
  CensusArm arm = CensusArm.bare,
}) => scoreCutoffResponse(
  testCase: _caseNamed(id),
  arm: arm,
  repeat: 1,
  response: response,
  truthSource: 'test',
);

void main() {
  group('the fixtures are backed by what is installed', () {
    test('every case is confirmed by the oracle', () {
      expect(
        verifyFixtures(cutoffCases, _oracle()),
        isEmpty,
        reason:
            'A fixture the installed SDK and pub cache do not back is not a '
            'measurement of the model. If this fails after a dependency bump, '
            'the fixture expired -- which is the whole point of reading the '
            'oracle off disk instead of hard-coding the verdict.',
      );
    });

    test('the oracle reads deprecation from the SDK, not from a constant', () {
      final oracle = _oracle();
      expect(oracle.flutterDeprecation('WillPopScope'), contains('PopScope'));
      expect(
        oracle.flutterDeprecation('PopScope'),
        isNull,
        reason: 'The replacement must not itself be deprecated.',
      );
      expect(
        oracle.flutterDeprecation('withOpacity'),
        contains('withValues'),
      );
    });

    test('a symbol contained in another is not reported as legacy', () {
      final oracle = _oracle();
      expect(
        oracle.packageSymbolIsLegacy('riverpod', 'StateNotifierProvider'),
        isTrue,
      );
      expect(
        oracle.packageSymbolIsLegacy('riverpod', 'NotifierProvider'),
        isFalse,
        reason:
            'A substring match reports NotifierProvider as legacy because '
            'StateNotifierProvider contains it, which inverts the fixture. '
            'Found by probing the oracle before trusting it.',
      );
    });
  });

  group('scoring reads idioms, never prose', () {
    test('the expired idiom is stale', () {
      final claim = _score(
        'flutter-pop-scope',
        'return WillPopScope(onWillPop: () async => true, child: child);',
      );
      expect(claim.truth, TruthVerdict.stale);
      expect(claim.assertedValue, isNot('neither'));
    });

    test('the installed idiom is correct', () {
      final claim = _score(
        'flutter-pop-scope',
        'return PopScope(canPop: false, onPopInvokedWithResult: (_, __) {});',
      );
      expect(claim.truth, TruthVerdict.correct);
    });

    test('using both, or neither, is unscorable rather than either side', () {
      expect(
        _score('color-with-values', 'c.withOpacity(0.5) // or c.withValues()')
            .truth,
        TruthVerdict.unscorable,
      );
      expect(
        _score('color-with-values', 'Colors.black54').truth,
        TruthVerdict.unscorable,
        reason:
            'A response that answered around the fixture asserted nothing '
            'about the idiom, and must not be counted as though it had.',
      );
    });

    test('freezed is scored on the declaration, not on a mention', () {
      expect(
        _score(
          'freezed-abstract',
          '@freezed\nclass Point with _\$Point {\n  const factory Point(int x, int y) = _Point;\n}',
        ).truth,
        TruthVerdict.stale,
      );
      expect(
        _score(
          'freezed-abstract',
          '@freezed\nabstract class Point with _\$Point {\n  const factory Point(int x, int y) = _Point;\n}',
        ).truth,
        TruthVerdict.correct,
      );
    });
  });

  group('truth and grounding are separate axes', () {
    test('a correct and a stale claim with no grounding differ in truth only', () {
      final correct = _score('riverpod-notifier', 'final p = NotifierProvider(...);');
      final stale = _score(
        'riverpod-notifier',
        'final p = StateNotifierProvider(...);',
      );

      expect(correct.truth, TruthVerdict.correct);
      expect(stale.truth, TruthVerdict.stale);
      expect(correct.grounding, GroundingVerdict.absent);
      expect(stale.grounding, GroundingVerdict.absent);
      expect(correct.provenance, GroundingProvenance.none);
      expect(stale.provenance, GroundingProvenance.none);
    });

    test('the grounded arm is attributed to the prompt, not to a tool result', () {
      final claim = _score(
        'riverpod-notifier',
        'final p = NotifierProvider(...);',
        arm: CensusArm.grounded,
      );

      expect(claim.grounding, GroundingVerdict.supported);
      expect(
        claim.provenance,
        GroundingProvenance.promptContext,
        reason:
            'KC2 evidence arrives in the prompt. Reporting it as an absent '
            'same-turn tool result would make the KC2 block look ineffective '
            'exactly where it worked.',
      );
    });
  });

  group('class 4 is grounded in this repository, not in a lockfile', () {
    test('the convention is read from lib/, and it is unambiguous', () {
      final usage = _oracle().repoUsage(const [
        'NotifierProvider',
        'ChangeNotifierProvider',
        'BlocProvider',
        'StateNotifierProvider',
      ]);

      expect(usage['NotifierProvider'], greaterThan(4));
      expect(usage['ChangeNotifierProvider'], 0);
      expect(usage['BlocProvider'], 0);
      expect(
        usage['StateNotifierProvider'],
        0,
        reason:
            'A repository that used two of these would not establish a '
            'convention, and the fixture would be measuring taste. '
            'verifyFixtures fails the run in that case rather than scoring it.',
      );
    });

    test('the off-convention answer the model actually gives is scored', () {
      // Not hypothetical: the first live run answered
      // `class CounterStateHolder extends ChangeNotifier` three times, and the
      // fixture matched only `ChangeNotifierProvider`, so the arm scored
      // unscorable. `\b` does not match inside the longer name.
      final claim = _score(
        'repo-state-management',
        'class CounterStateHolder extends ChangeNotifier {\n  void increment() => notifyListeners();\n}',
      );
      expect(claim.truth, TruthVerdict.stale);
    });

    test('the version block is deliberately the wrong grounding here', () {
      // Class 4's correct ground is the repo, not a lockfile. Leaving the
      // grounded arm carrying only versions makes it an expected-negative
      // control: if a version block moves a repo-convention question, that is
      // itself worth knowing.
      final oracle = _oracle();
      expect(groundTruthBlock(oracle), isNot(contains('NotifierProvider')));
      expect(
        cutoffCases
            .firstWhere((c) => c.id == 'repo-state-management')
            .cutoffClass,
        CutoffClass.thisRepository,
      );
    });
  });

  group('the negative control', () {
    test('a fixture the toolchain contradicts fails the run', () {
      // The acceptance criterion: an arm fed deliberately stale fixtures must
      // fail against the oracle rather than quietly scoring the model.
      final wrong = CutoffCase(
        id: 'deliberately-wrong',
        cutoffClass: CutoffClass.apiDrift,
        description: 'claims the current idiom is the expired one',
        task: 'irrelevant',
        stale: RegExp(r'\bPopScope\b'),
        current: RegExp(r'\bWillPopScope\b'),
        confirmStale: (oracle) => oracle.flutterDeprecation('PopScope') == null
            ? 'the installed SDK does not deprecate PopScope'
            : null,
      );

      final problems = verifyFixtures([wrong], _oracle());
      expect(problems, hasLength(1));
      expect(problems.single, contains('does not deprecate PopScope'));
    });

    test('a transport failure is recorded, never scored as staleness', () async {
      final options = CensusOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
        '--repeats',
        '1',
      ], const {});

      final summary = await runCutoffCensus(
        options: options!,
        oracle: _oracle(),
        cases: [_caseNamed('flutter-pop-scope')],
        send: (system, user) async => throw StateError('endpoint down'),
      );

      expect(summary.failures(), 2);
      expect(summary.staleRate(CensusArm.bare), 0);
      expect(summary.claims.first.failure, contains('endpoint down'));
    });
  });

  group('the run records what it was', () {
    test('--case restricts the run without changing the fixture set', () async {
      final fixtureCount = cutoffCases.length;
      final options = CensusOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
        '--repeats',
        '1',
        '--case',
        'freezed-abstract',
      ], const {});

      final summary = await runCutoffCensus(
        options: options!,
        oracle: _oracle(),
        send: (system, user) async => 'abstract class Point with _\$Point {}',
      );

      expect(summary.claims.map((c) => c.caseId).toSet(), {'freezed-abstract'});
      expect(
        cutoffCases.length,
        fixtureCount,
        reason:
            'Spot-checking one fixture must not shrink the set the next full '
            'run measures. Compared against the count taken before the run '
            'rather than a literal, so adding a fixture does not fail this.',
      );
    });

    test('both arms run, and the grounded one carries the versions', () async {
      final seen = <String>[];
      final options = CensusOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
        '--repeats',
        '1',
      ], const {});

      final summary = await runCutoffCensus(
        options: options!,
        oracle: _oracle(),
        cases: [_caseNamed('riverpod-notifier')],
        send: (system, user) async {
          seen.add(user.contains('riverpod: 3.4.2') ? 'grounded' : 'bare');
          return 'final p = NotifierProvider(...);';
        },
      );

      expect(seen, ['bare', 'grounded']);
      expect(summary.runIdentity['flutter'], '3.44.8');
      expect(summary.runIdentity['toolCatalog'], 'none');
      expect(
        summary.runIdentity['buildCommit'],
        isNotEmpty,
        reason: 'Grounded logs only: a run without build provenance is not one.',
      );
    });
  });
}
