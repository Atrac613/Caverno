import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/model_benchmark_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps only same-profile, same-suite scored revisions', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [
        _revision(points: 900),
        _revision(points: 910, profileId: 'other-model'),
        _revision(points: 920, suite: 'cavernobench-v1'),
        _revision(points: null),
        _revision(points: 930),
      ],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(history.samples.map((revision) => revision.benchmarkPoints), [
      900,
      930,
    ]);
  });

  test('reports no delta until two comparable runs exist', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [_revision(points: 900)],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(history.latestPoints, 900);
    expect(history.delta, isNull);
    expect(history.priorSpread, isNull);
    expect(history.regressionDetected, isFalse);
    expect(history.summaryLine(), 'benchmark 900/1000 (first scored run)');
  });

  test('a drop on the second run is not a regression yet', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [_revision(points: 900), _revision(points: 700)],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    // There is no measured noise floor yet, so nothing can be called a
    // regression without inventing one.
    expect(history.delta, -200);
    expect(history.priorSpread, isNull);
    expect(history.regressionDetected, isFalse);
  });

  test('a drop inside the measured spread is treated as noise', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [
        _revision(points: 900),
        _revision(points: 940),
        _revision(points: 910),
      ],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(history.priorSpread, 40);
    expect(history.delta, -30);
    expect(history.regressionDetected, isFalse);
  });

  test('a drop beyond the measured spread is a regression', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [
        _revision(points: 900),
        _revision(points: 910),
        _revision(points: 700),
      ],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(history.priorSpread, 10);
    expect(history.delta, -210);
    expect(history.regressionDetected, isTrue);
    expect(
      history.summaryLine(),
      'benchmark 700/1000 (-210 vs previous, spread 10 over 2 runs) REGRESSION',
    );
  });

  test('an improvement beyond the spread is never a regression', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [
        _revision(points: 700),
        _revision(points: 710),
        _revision(points: 960),
      ],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(history.delta, 250);
    expect(history.regressionDetected, isFalse);
    expect(history.summaryLine(), contains('+250 vs previous'));
  });

  test('regressionFor judges a candidate before it is appended', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [
        _revision(points: 900),
        _revision(points: 905),
        _revision(points: 900),
      ],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(history.regressionFor(895), isFalse);
    expect(history.regressionFor(600), isTrue);
    // An unscored run must not read as a drop to zero.
    expect(history.regressionFor(null), isFalse);
  });

  test('a history with no comparable runs answers nothing', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [_revision(points: 900, suite: 'cavernobench-v1')],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(history.isEmpty, isTrue);
    expect(history.summaryLine(), isNull);
    expect(history.regressionFor(100), isFalse);
  });

  test('a narrower run is not compared with the runs before it', () {
    // The endpoint stopped accepting `temperature`, so the 200-point sampler
    // block became unmeasurable. The points fall by 200 with no change in the
    // model, and comparing across that would report a huge regression.
    final revisions = [
      _revision(points: 980, attempted: 980),
      _revision(points: 975, attempted: 980),
      _revision(points: 980, attempted: 980),
    ];

    final sameWidth = ModelBenchmarkHistory.forProfile(
      revisions: revisions,
      profileId: 'model-a',
      suite: 'cavernobench-v2',
      attemptedPoints: 980,
    );
    final narrower = ModelBenchmarkHistory.forProfile(
      revisions: revisions,
      profileId: 'model-a',
      suite: 'cavernobench-v2',
      attemptedPoints: 780,
    );

    expect(sameWidth.samples, hasLength(3));
    expect(sameWidth.regressionFor(762), isTrue);
    expect(narrower.samples, isEmpty);
    expect(narrower.regressionFor(762), isFalse);
  });

  test('revisions that predate the attempted field stay comparable', () {
    final history = ModelBenchmarkHistory.forProfile(
      revisions: [
        _revision(points: 980),
        _revision(points: 975),
        _revision(points: 980),
      ],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
      attemptedPoints: 980,
    );

    expect(history.samples, hasLength(3));
  });

  test('the summary line is denominated by what the run measured', () {
    final narrow = ModelBenchmarkHistory.forProfile(
      revisions: [_revision(points: 762, attempted: 780)],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(
      narrow.summaryLine(),
      'benchmark 762/780 measured (first scored run)',
    );

    final full = ModelBenchmarkHistory.forProfile(
      revisions: [_revision(points: 980, attempted: 1000)],
      profileId: 'model-a',
      suite: 'cavernobench-v2',
    );

    expect(full.summaryLine(), 'benchmark 980/1000 (first scored run)');
  });
}

ModelCapabilityProfileRevision _revision({
  required int? points,
  String profileId = 'model-a',
  String suite = 'cavernobench-v2',
  int? attempted,
}) {
  return ModelCapabilityProfileRevision(
    profileId: profileId,
    probedAt: DateTime.utc(2026, 8, 11),
    toolCallStyle: ModelToolCallStyle.nativeToolCalls,
    structuredOutputSupport: ModelStructuredOutputSupport.jsonObject,
    editFormatPreference: ModelEditFormatPreference.unknown,
    usableContextTokens: 8192,
    benchmarkPoints: points,
    benchmarkAttemptedPoints: attempted,
    benchmarkMaxPoints: points == null ? null : 1000,
    benchmarkSuite: points == null ? '' : suite,
  );
}
