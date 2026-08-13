import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_scoring.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weight table covers exactly the declared probe set', () {
    final probeIds = LiveLlmDiagnosticService.probeDefinitions
        .map((definition) => definition.id)
        .toSet();

    expect(LiveLlmDiagnosticSuite.probePoints.keys.toSet(), probeIds);
  });

  test('declared point totals agree with the weight table', () {
    final sum = LiveLlmDiagnosticSuite.probePoints.values.fold<int>(
      0,
      (total, points) => total + points,
    );

    expect(sum, LiveLlmDiagnosticSuite.probePointsTotal);
    expect(
      LiveLlmDiagnosticSuite.maxPoints,
      LiveLlmDiagnosticSuite.probePointsTotal +
          LiveLlmDiagnosticSuite.samplerStabilityPoints,
    );
    expect(LiveLlmDiagnosticSuite.version, 8);
    expect(LiveLlmDiagnosticSuite.pointsFor('effective_context'), 0);
    expect(
      LiveLlmDiagnosticSuite.pointsFor('structured_output'),
      greaterThan(0),
    );
    expect(
      LiveLlmDiagnosticSuite.pointsFor('embeddings_capability'),
      greaterThan(0),
    );
  });

  test('a fully passing run earns the fixed maximum', () {
    final report = _report(
      results: [
        for (final id in LiveLlmDiagnosticSuite.probePoints.keys)
          _result(id, LiveLlmDiagnosticStatus.passed),
      ],
      trials: _trials(passed: 8, failed: 0),
    );

    final score = LiveLlmDiagnosticScore.fromReport(report);

    expect(score.earnedPoints, LiveLlmDiagnosticSuite.maxPoints);
    expect(score.attemptedPoints, LiveLlmDiagnosticSuite.maxPoints);
    expect(score.coverage, 1);
  });

  test('skipped probes lower coverage instead of raising the score', () {
    final ids = LiveLlmDiagnosticSuite.probePoints.keys.toList();
    final passingOnly = _report(
      results: [
        for (final id in ids.take(3))
          _result(id, LiveLlmDiagnosticStatus.passed),
        for (final id in ids.skip(3))
          _result(id, LiveLlmDiagnosticStatus.skipped),
      ],
    );

    final score = LiveLlmDiagnosticScore.fromReport(passingOnly);
    final expectedEarned = ids
        .take(3)
        .fold<int>(
          0,
          (total, id) => total + LiveLlmDiagnosticSuite.pointsFor(id),
        );

    // The legacy ratio reports a perfect run here; the benchmark does not.
    expect(passingOnly.score, 1);
    expect(score.earnedPoints, expectedEarned);
    expect(score.earnedPoints, lessThan(LiveLlmDiagnosticSuite.maxPoints));
    expect(score.attemptedPoints, expectedEarned);
    expect(score.coverage, lessThan(1));
  });

  test('a warning earns its sub-check ratio when the probe counted them', () {
    final report = _report(
      results: [
        _result(
          'exact_preservation',
          LiveLlmDiagnosticStatus.warning,
          passedChecks: 2,
          totalChecks: 3,
        ),
      ],
    );

    final score = LiveLlmDiagnosticScore.fromReport(report);
    final weight = LiveLlmDiagnosticSuite.pointsFor('exact_preservation');

    expect(score.earnedPoints, (weight * 2 / 3).round());
    expect(score.attemptedPoints, weight);
  });

  test('a warning without sub-checks falls back to flat partial credit', () {
    final report = _report(
      results: [_result('narrow_tool_call', LiveLlmDiagnosticStatus.warning)],
    );

    final score = LiveLlmDiagnosticScore.fromReport(report);
    final weight = LiveLlmDiagnosticSuite.pointsFor('narrow_tool_call');

    expect(
      score.earnedPoints,
      (weight * LiveLlmDiagnosticSuite.warningCreditRatio).round(),
    );
  });

  test('a failed probe is attempted but earns nothing', () {
    final report = _report(
      results: [_result('narrow_tool_call', LiveLlmDiagnosticStatus.failed)],
    );

    final score = LiveLlmDiagnosticScore.fromReport(report);

    expect(score.earnedPoints, 0);
    expect(
      score.attemptedPoints,
      LiveLlmDiagnosticSuite.pointsFor('narrow_tool_call'),
    );
  });

  test('sampler trials contribute a stability block scaled by pass rate', () {
    final report = _report(
      results: const [],
      trials: _trials(passed: 6, failed: 2),
    );

    final score = LiveLlmDiagnosticScore.fromReport(report);

    expect(score.samplerTrialCount, 8);
    expect(score.samplerPassedCount, 6);
    expect(
      score.earnedPoints,
      (LiveLlmDiagnosticSuite.samplerStabilityPoints * 6 / 8).round(),
    );
    expect(
      score.attemptedPoints,
      LiveLlmDiagnosticSuite.samplerStabilityPoints,
    );
  });

  test('a run without sampler trials keeps the block out of attempted', () {
    final report = _report(results: const []);

    final score = LiveLlmDiagnosticScore.fromReport(report);

    expect(score.samplerAttempted, isFalse);
    expect(score.attemptedPoints, 0);
    expect(score.attemptedRatio, 0);
  });

  test('the export carries the suite identity with the score', () {
    final report = _report(
      results: [_result('instruction_echo', LiveLlmDiagnosticStatus.passed)],
    );

    final export = buildLiveLlmDiagnosticExport(report);
    final benchmark = export['benchmark'] as Map<String, dynamic>;

    expect(export['model'], 'test-model');
    expect(benchmark['suiteId'], LiveLlmDiagnosticSuite.id);
    expect(benchmark['suiteVersion'], LiveLlmDiagnosticSuite.version);
    expect(benchmark['maxPoints'], LiveLlmDiagnosticSuite.maxPoints);
    expect(
      benchmark['earnedPoints'],
      LiveLlmDiagnosticSuite.pointsFor('instruction_echo'),
    );
  });
}

LiveLlmDiagnosticReport _report({
  required List<LiveLlmDiagnosticProbeResult> results,
  List<LiveLlmDiagnosticSamplerTrial> trials =
      const <LiveLlmDiagnosticSamplerTrial>[],
}) {
  return LiveLlmDiagnosticReport(
    startedAt: DateTime.utc(2026, 8, 11),
    finishedAt: DateTime.utc(2026, 8, 11, 0, 1),
    baseUrl: 'http://localhost:1234/v1',
    model: 'test-model',
    demoMode: false,
    mcpEnabled: true,
    results: results,
    samplerCalibrationTrials: trials,
  );
}

LiveLlmDiagnosticProbeResult _result(
  String id,
  LiveLlmDiagnosticStatus status, {
  int passedChecks = 0,
  int totalChecks = 0,
}) {
  return LiveLlmDiagnosticProbeResult(
    id: id,
    status: status,
    summary: '$id: ${status.label}',
    passedChecks: passedChecks,
    totalChecks: totalChecks,
  );
}

List<LiveLlmDiagnosticSamplerTrial> _trials({
  required int passed,
  required int failed,
}) {
  return [
    for (var index = 0; index < passed; index += 1)
      const LiveLlmDiagnosticSamplerTrial(
        requestClass: 'toolLoop',
        temperature: 0,
        passed: true,
      ),
    for (var index = 0; index < failed; index += 1)
      const LiveLlmDiagnosticSamplerTrial(
        requestClass: 'toolLoop',
        temperature: 0,
        passed: false,
      ),
  ];
}
