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

EnvironmentCase _environmentCaseNamed(String id) =>
    environmentCases.firstWhere((testCase) => testCase.id == id);

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
  promptSupportsClaim: promptSupportsClaimFor(
    testCase: _caseNamed(id),
    arm: arm,
    oracle: _oracle(),
  ),
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

    test('the environment fixture reads the installed Material 3 default', () {
      final oracle = _oracle();
      expect(verifyEnvironmentFixtures(environmentCases, oracle), isEmpty);
      expect(oracle.flutterThemeDataUseMaterial3Default(), isTrue);
      expect(environmentCases.single.readDefault(oracle), isTrue);
    });

    test('environment context does not alter the existing replay block', () {
      final oracle = _oracle();
      expect(groundTruthBlock(oracle), isNot(contains('useMaterial3')));
      expect(
        environmentGroundTruthBlock(oracle),
        contains('Flutter ThemeData.useMaterial3 default: true'),
      );
    });

    test('the environment task does not prescribe the assertion', () {
      expect(
        environmentCases.single.task,
        isNot(contains('Include the useMaterial3 setting')),
      );
      expect(
        environmentCases.single.task,
        contains('Do not add redundant overrides'),
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
      expect(oracle.flutterDeprecation('withOpacity'), contains('withValues'));
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

  group('class 3 environment verdicts', () {
    test(
      'distinguishes required, inherited, unnecessary, wrong, and unscorable',
      () {
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: true)',
            defaultValue: false,
          ),
          EnvironmentVerdict.required,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: true)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unnecessary,
        );
        expect(
          scoreEnvironmentSetting(response: 'ThemeData()', defaultValue: true),
          EnvironmentVerdict.inherited,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: false)',
            defaultValue: true,
          ),
          EnvironmentVerdict.wrong,
        );
        expect(
          scoreEnvironmentSetting(response: 'ThemeData()', defaultValue: true),
          EnvironmentVerdict.inherited,
        );
        expect(
          scoreEnvironmentSetting(response: 'ThemeData()', defaultValue: false),
          EnvironmentVerdict.wrong,
        );
        expect(
          scoreEnvironmentSetting(response: 'SizedBox()', defaultValue: true),
          EnvironmentVerdict.unscorable,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData() // useMaterial3: true',
            defaultValue: true,
          ),
          EnvironmentVerdict.inherited,
        );
        expect(
          scoreEnvironmentSetting(
            response: "final text = 'useMaterial3: true'; ThemeData()",
            defaultValue: true,
          ),
          EnvironmentVerdict.inherited,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: enabled)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unscorable,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: null)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unscorable,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: true && enabled)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unscorable,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: true ? enabled : false)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unscorable,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData.light()',
            defaultValue: true,
          ),
          EnvironmentVerdict.inherited,
        );
        expect(
          scoreEnvironmentSetting(
            response:
                'ThemeData.from(colorScheme: ColorScheme.light(), useMaterial3: true)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unnecessary,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData.lerp(a, b, 0.5)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unscorable,
        );
        expect(
          scoreEnvironmentSetting(
            response: 'ThemeData(useMaterial3: true, useMaterial3: false)',
            defaultValue: true,
          ),
          EnvironmentVerdict.unscorable,
        );
      },
    );

    test('keeps environment verdict separate from grounding', () {
      final testCase = _environmentCaseNamed('flutter-material3-default');
      final claim = scoreEnvironmentResponse(
        testCase: testCase,
        arm: CensusArm.grounded,
        repeat: 1,
        response: 'ThemeData(useMaterial3: true)',
        truthSource: 'test',
        promptSupportsClaim: true,
        defaultValue: true,
      );

      expect(claim.environmentVerdict, EnvironmentVerdict.unnecessary);
      expect(claim.truth, TruthVerdict.correct);
      expect(claim.grounding, GroundingVerdict.supported);
      expect(claim.provenance, GroundingProvenance.promptContext);
      expect(claim.assertedValue, 'true');
      expect(claim.expectedValue, 'omitted');
      expect(claim.toJson()['environment_verdict'], 'unnecessary');
    });

    test('records an omitted default override as inherited', () {
      final testCase = _environmentCaseNamed('flutter-material3-default');
      final claim = scoreEnvironmentResponse(
        testCase: testCase,
        arm: CensusArm.bare,
        repeat: 1,
        response: 'ThemeData()',
        truthSource: 'test',
        promptSupportsClaim: false,
        defaultValue: true,
      );

      expect(claim.environmentVerdict, EnvironmentVerdict.inherited);
      expect(claim.truth, TruthVerdict.correct);
      expect(claim.assertedValue, 'omitted');
      expect(claim.expectedValue, 'omitted');
      expect(claim.grounding, GroundingVerdict.absent);
    });

    test(
      'records the required assertion when the installed default is false',
      () {
        final testCase = _environmentCaseNamed('flutter-material3-default');
        final claim = scoreEnvironmentResponse(
          testCase: testCase,
          arm: CensusArm.bare,
          repeat: 1,
          response: 'ThemeData(useMaterial3: true)',
          truthSource: 'test',
          promptSupportsClaim: false,
          defaultValue: false,
        );

        expect(claim.environmentVerdict, EnvironmentVerdict.required);
        expect(claim.assertedValue, 'true');
        expect(claim.expectedValue, 'true');
        expect(claim.truth, TruthVerdict.correct);
      },
    );

    test('the environment negative control fails before replay', () {
      final wrong = EnvironmentCase(
        id: 'deliberately-wrong-environment',
        task: 'irrelevant',
        description: 'claims an unavailable environment fact',
        readDefault: (_) => null,
        confirmEnvironment: (_) => 'the environment oracle is unavailable',
      );

      expect(verifyEnvironmentFixtures([wrong], _oracle()), [
        'deliberately-wrong-environment: the environment oracle is unavailable',
      ]);
    });

    test('the replay records class 3 verdicts in the summary', () async {
      final options = CensusOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
        '--repeats',
        '1',
        '--case',
        'flutter-material3-default',
      ], const {});
      final summary = await runCutoffCensus(
        options: options!,
        oracle: _oracle(),
        environmentCases: [_environmentCaseNamed('flutter-material3-default')],
        send: (system, user) async => 'ThemeData(useMaterial3: true)',
      );

      expect(summary.claims, hasLength(CensusArm.values.length));
      expect(
        summary.environmentVerdicts(CensusArm.grounded),
        containsPair(EnvironmentVerdict.unnecessary, 1),
      );
      expect(
        summary
            .toJson()['arms']['grounded']['environmentVerdicts']['unnecessary'],
        1,
      );
      expect(summary.environmentExposureRateFor(CensusArm.grounded), 1);
      expect(
        summary
            .toJson()['byClass']['environment']['grounded']['environmentExposureRate'],
        1,
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
        _score(
          'color-with-values',
          'c.withOpacity(0.5) // or c.withValues()',
        ).truth,
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
    test(
      'a correct and a stale claim with no grounding differ in truth only',
      () {
        final correct = _score(
          'riverpod-notifier',
          'final p = NotifierProvider(...);',
        );
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
      },
    );

    test(
      'the delta arm is attributed to the prompt, not to a tool result',
      () {
        final claim = _score(
          'color-with-values',
          'base.withValues(alpha: 0.5)',
          arm: CensusArm.deltaGrounded,
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
      },
    );

    test('a stale delta claim contradicts the prompt context', () {
      final claim = _score(
        'color-with-values',
        'base.withOpacity(0.5)',
        arm: CensusArm.deltaGrounded,
      );

      expect(claim.truth, TruthVerdict.stale);
      expect(claim.grounding, GroundingVerdict.contradicted);
      expect(claim.provenance, GroundingProvenance.promptContext);
    });

    test('a version-only API claim has absent grounding', () {
      final claim = _score(
        'color-with-values',
        'base.withValues(alpha: 0.5)',
        arm: CensusArm.grounded,
      );

      expect(claim.truth, TruthVerdict.correct);
      expect(claim.grounding, GroundingVerdict.absent);
      expect(claim.provenance, GroundingProvenance.none);
    });

    test('an unscorable delta response has no grounding provenance', () {
      final claim = _score(
        'color-with-values',
        'base.withOpacity(0.5) and base.withValues(alpha: 0.5)',
        arm: CensusArm.deltaGrounded,
      );

      expect(claim.truth, TruthVerdict.unscorable);
      expect(claim.grounding, GroundingVerdict.absent);
      expect(claim.provenance, GroundingProvenance.none);
    });

    test('an uncovered delta claim has absent grounding', () {
      final claim = _score(
        'flutter-pop-scope',
        'return PopScope(canPop: false);',
        arm: CensusArm.deltaGrounded,
      );

      expect(claim.truth, TruthVerdict.correct);
      expect(claim.grounding, GroundingVerdict.absent);
      expect(claim.provenance, GroundingProvenance.none);
    });

    test('summary reports stale and unsupported rates separately', () {
      final summary = CensusSummary(
        claims: [
          _score(
            'color-with-values',
            'base.withValues(alpha: 0.5)',
            arm: CensusArm.deltaGrounded,
          ),
          _score(
            'color-with-values',
            'base.withOpacity(0.5)',
            arm: CensusArm.deltaGrounded,
          ),
        ],
        runIdentity: const {},
      );

      expect(summary.staleRate(CensusArm.deltaGrounded), 0.5);
      expect(summary.unsupportedRate(CensusArm.deltaGrounded), 0.5);
      expect(
        summary.unsupportedRateFor(
          CutoffClass.apiDrift,
          CensusArm.deltaGrounded,
        ),
        0.5,
      );
      final json = summary.toJson();
      expect(json['schemaVersion'], 3);
      expect(
        (json['arms'] as Map)['deltaGrounded']['unsupportedRate'],
        0.5,
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

  group('the delta arm', () {
    test('the digest is assembled from disk, not written down', () {
      final digest = deltaBlock(_oracle());

      expect(digest, contains('withValues'));
      expect(
        digest,
        contains('StateNotifierProvider'),
        reason:
            'riverpod declares it as `final class`, and a regex that only knew '
            '`abstract class` returned one legacy symbol out of five -- a '
            'digest missing the idiom its own fixture is about.',
      );
      expect(digest, contains('abstract'));
    });

    test('the digest does not name a replacement per fixture', () {
      // If it did, the arm would measure instruction-following: the model would
      // be reading back an answer it had just been handed.
      final oracle = _oracle();

      expect(
        digestCovers(_caseNamed('flutter-pop-scope'), oracle),
        isFalse,
        reason:
            'WillPopScope was deprecated at v3.12, far outside the recency '
            'window, so this case is the control for what the digest does not '
            'reach. If it ever becomes covered, the window changed and the '
            'control has to move with it.',
      );
      expect(digestCovers(_caseNamed('color-with-values'), oracle), isTrue);
    });

    test('deprecations are deduplicated on the advice, not the site', () {
      final entries = _oracle().recentFlutterDeprecations(limit: 40);
      final keys = entries
          .map((entry) => '${entry.symbol}|${entry.advice}')
          .toList(growable: false);

      expect(
        keys.toSet(),
        hasLength(keys.length),
        reason:
            'One deprecated parameter reappears on every widget that takes it. '
            'Undeduplicated, the digest spent eight of its first entries on '
            'cacheExtent.',
      );
    });

    test('the delta arm carries the version block as well', () async {
      final seen = <String>[];
      final options = CensusOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
        '--repeats',
        '1',
        '--case',
        'color-with-values',
      ], const {});

      await runCutoffCensus(
        options: options!,
        oracle: _oracle(),
        send: (system, user) async {
          seen.add(
            user.contains('Recent changes')
                ? 'delta'
                : user.contains('Installed toolchain')
                ? 'grounded'
                : 'bare',
          );
          return '.withValues(alpha: 0.5)';
        },
      );

      expect(seen, ['bare', 'grounded', 'delta']);
    });

    test('an uncovered delta response is not marked as grounded', () async {
      final options = CensusOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
        '--repeats',
        '1',
        '--case',
        'flutter-pop-scope',
      ], const {});

      final summary = await runCutoffCensus(
        options: options!,
        oracle: _oracle(),
        cases: [_caseNamed('flutter-pop-scope')],
        send: (system, user) async => 'return PopScope(canPop: false);',
      );
      final deltaClaim = summary.claims.firstWhere(
        (claim) => claim.arm == CensusArm.deltaGrounded,
      );

      expect(deltaClaim.truth, TruthVerdict.correct);
      expect(deltaClaim.grounding, GroundingVerdict.absent);
      expect(deltaClaim.provenance, GroundingProvenance.none);
    });

    test('prompt-context coverage is case-specific', () {
      final groundedVersionClaim = _score(
        'color-with-values',
        'base.withValues(alpha: 0.5)',
        arm: CensusArm.grounded,
      );
      final deltaApiClaim = _score(
        'color-with-values',
        'base.withValues(alpha: 0.5)',
        arm: CensusArm.deltaGrounded,
      );

      expect(groundedVersionClaim.grounding, GroundingVerdict.absent);
      expect(
        groundedVersionClaim.provenance,
        GroundingProvenance.none,
      );
      expect(deltaApiClaim.grounding, GroundingVerdict.supported);
      expect(deltaApiClaim.provenance, GroundingProvenance.promptContext);
      expect(
        _score('color-with-values', 'base.withValues(alpha: 0.5)').grounding,
        GroundingVerdict.absent,
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

    test(
      'a transport failure is recorded, never scored as staleness',
      () async {
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

        expect(summary.failures(), CensusArm.values.length);
        expect(summary.staleRate(CensusArm.bare), isNull);
        expect(summary.unsupportedRate(CensusArm.bare), isNull);
        expect(summary.report(), contains('stale  - unsupported'));
        expect(summary.claims.first.failure, contains('endpoint down'));
      },
    );
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

    test('every arm runs, and each carries what it is meant to', () async {
      final seen = <String>[];
      final oracle = _oracle();
      final riverpodVersion = oracle.packageVersion('riverpod');
      expect(
        riverpodVersion,
        isNotNull,
        reason:
            'The grounded arm is identified by the installed version. A '
            'hard-coded literal expires on the next riverpod bump.',
      );
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
        oracle: oracle,
        cases: [_caseNamed('riverpod-notifier')],
        send: (system, user) async {
          seen.add(
            user.contains('Recent changes')
                ? 'delta'
                : user.contains('riverpod: $riverpodVersion')
                ? 'grounded'
                : 'bare',
          );
          return 'final p = NotifierProvider(...);';
        },
      );

      expect(seen, ['bare', 'grounded', 'delta']);
      // Same reason the riverpod version above is read rather than written:
      // a literal here expires on the next SDK bump, and `3.44.8` duly did
      // when .fvmrc moved to 3.47.4. What is worth pinning is that the run
      // records the pinned SDK at all, not which one it happens to be.
      expect(oracle.flutterVersion, isNotNull);
      expect(summary.runIdentity['flutter'], oracle.flutterVersion);
      expect(summary.runIdentity['toolCatalog'], 'none');
      expect(
        summary.runIdentity['buildCommit'],
        isNotEmpty,
        reason:
            'Grounded logs only: a run without build provenance is not one.',
      );
    });
  });
}
