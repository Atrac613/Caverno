import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_paired_statistics.dart';
import '../../tool/personal_eval_suite_report.dart';

void main() {
  test('passes when the candidate has no hard regressions', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-report-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final manifests = [
      _writeManifest(
        directory: directory,
        caseId: 'ping-cli',
        title: 'Ping CLI',
        verificationResult: 'passed',
        toolCallCount: 2,
      ),
      _writeManifest(
        directory: directory,
        caseId: 'weather-cli',
        title: 'Weather CLI',
        verificationResult: 'failed',
        toolCallCount: 4,
      ),
    ];
    final incumbent = _writeReplayRun(
      directory: directory,
      fileName: 'incumbent.json',
      label: 'incumbent',
      model: 'qwen3',
      cases: [
        _caseResult(
          caseId: 'ping-cli',
          verificationResult: 'passed',
          durationMs: 5000,
          toolCallCount: 3,
          turnCount: 4,
        ),
        _caseResult(
          caseId: 'weather-cli',
          verificationResult: 'failed',
          durationMs: 9000,
          toolCallCount: 6,
          turnCount: 5,
        ),
      ],
    );
    final candidate = _writeReplayRun(
      directory: directory,
      fileName: 'candidate.json',
      label: 'candidate',
      model: 'glm',
      cases: [
        _caseResult(
          caseId: 'ping-cli',
          verificationResult: 'passed',
          durationMs: 3500,
          toolCallCount: 2,
          turnCount: 3,
        ),
        _caseResult(
          caseId: 'weather-cli',
          verificationResult: 'passed',
          durationMs: 8000,
          toolCallCount: 4,
          turnCount: 4,
        ),
      ],
    );

    final report = await buildPersonalEvalSuiteReport(
      manifestFiles: manifests,
      incumbentResultFile: incumbent,
      candidateResultFile: candidate,
      label: 'incumbent vs candidate',
      generatedAt: DateTime.utc(2026, 6, 14, 2, 3, 4),
      experimentProtocol: _modelSelectionProtocol(minimumEffectTaskCount: 2),
    );

    expect(report.result, 'passed');
    // No hard regression is not evidence of an improvement; the fixture's
    // interval includes zero.
    expect(report.recommendation, 'no_difference_established');
    expect(report.hardRegressionCount, 0);
    expect(report.watchSignalCount, 0);
    expect(report.improvementCount, 7);
    expect(report.incumbent.passRate, 0.5);
    expect(report.candidate.passRate, 1.0);
    expect(report.candidate.averageToolCallDelta, 0);
    expect(report.statistics.binaryPairCount, 2);
    expect(report.statistics.candidateOnlyPassedCount, 1);
    expect(report.statistics.incumbentOnlyPassedCount, 0);
    expect(report.statistics.passRateDifference, 0.5);
    expect(report.statistics.mcnemarExactPValue, 1.0);
    expect(report.statistics.medianDurationDifferenceMs, -1250);
    expect(report.statistics.medianTurnCountDifference, -1);
    expect(report.statistics.medianToolCallCountDifference, -1.5);

    final ping = report.entries.singleWhere(
      (entry) => entry.caseId == 'ping-cli',
    );
    expect(ping.status, 'improved');
    expect(
      ping.improvements,
      contains('tool-call fidelity delta decreased 1->0'),
    );
    expect(ping.improvements, contains('duration decreased 5000->3500 ms'));

    final weather = report.entries.singleWhere(
      (entry) => entry.caseId == 'weather-cli',
    );
    expect(weather.status, 'improved');
    expect(
      weather.improvements,
      contains('verification result improved failed->passed'),
    );

    final json = report.toJson();
    expect(json['schemaName'], 'caverno_personal_eval_suite_report');
    expect(json['schemaVersion'], 7);
    expect(json['evidenceOrigins'], ['recorded']);
    expect(json['splitCounts'], {'heldIn': 2, 'heldOut': 0});
    expect(
      json['experimentProtocol'],
      containsPair('studyIntent', 'model_selection'),
    );
    expect(json['decisionEligibility'], containsPair('isEligible', true));
    expect(json['generatedAt'], '2026-06-14T02:03:04.000Z');
    expect(json['label'], 'incumbent vs candidate');
    expect(json['result'], 'passed');
    expect(json['recommendation'], 'no_difference_established');
    expect(json['candidate'], containsPair('passedCount', 2));
    expect(
      json['pairedStatistics'],
      containsPair('differenceDirection', 'candidate_minus_incumbent'),
    );
    expect(json['entries'], hasLength(2));

    final markdown = report.toMarkdown();
    expect(markdown, contains('Personal Eval Suite Report'));
    expect(markdown, contains('Recommendation: `no_difference_established`'));
    expect(markdown, contains('## Paired Statistics'));
    expect(markdown, contains('+50.0 pp'));
    expect(markdown, contains('1.000000'));
    expect(markdown, contains('tool-call fidelity delta decreased'));
  });

  test('fails when the candidate regresses or misses a case', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-report-regression-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final manifests = [
      _writeManifest(
        directory: directory,
        caseId: 'case-a',
        title: 'Case A',
        verificationResult: 'passed',
        toolCallCount: 2,
      ),
      _writeManifest(
        directory: directory,
        caseId: 'case-b',
        title: 'Case B',
        verificationResult: 'passed',
        toolCallCount: 1,
      ),
    ];
    final incumbent = _writeReplayRun(
      directory: directory,
      fileName: 'incumbent.json',
      label: 'incumbent',
      cases: [
        _caseResult(
          caseId: 'case-a',
          verificationResult: 'passed',
          durationMs: 2000,
          toolCallCount: 2,
          turnCount: 2,
        ),
        _caseResult(
          caseId: 'case-b',
          verificationResult: 'passed',
          durationMs: 1000,
          toolCallCount: 1,
          turnCount: 1,
        ),
      ],
    );
    final candidate = _writeReplayRun(
      directory: directory,
      fileName: 'candidate.json',
      label: 'candidate',
      cases: [
        _caseResult(
          caseId: 'case-a',
          verificationResult: 'failed',
          durationMs: 5000,
          toolCallCount: 5,
          turnCount: 5,
        ),
      ],
    );

    final report = await buildPersonalEvalSuiteReport(
      manifestFiles: manifests,
      incumbentResultFile: incumbent,
      candidateResultFile: candidate,
      generatedAt: DateTime.utc(2026, 6, 14),
      experimentProtocol: _modelSelectionProtocol(),
    );

    expect(report.result, 'failed');
    expect(report.recommendation, 'reject_candidate');
    expect(report.hardRegressionCount, 2);
    expect(report.watchSignalCount, 3);
    expect(report.candidate.missingCaseCount, 1);
    final caseA = report.entries.singleWhere(
      (entry) => entry.caseId == 'case-a',
    );
    expect(caseA.status, 'regressed');
    expect(
      caseA.hardRegressions,
      contains('verification result regressed passed->failed'),
    );
    expect(caseA.watchSignals, contains('duration increased 2000->5000 ms'));
    expect(caseA.watchSignals, contains('turn count increased 2->5'));
    expect(
      caseA.watchSignals,
      contains('tool-call fidelity delta increased 0->3'),
    );
    final caseB = report.entries.singleWhere(
      (entry) => entry.caseId == 'case-b',
    );
    expect(caseB.hardRegressions, ['missing candidate result']);
  });

  test('weights repeated trials by task and preserves trial counts', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-report-repeated-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final manifests = [
      _writeManifest(
        directory: directory,
        caseId: 'many-trials',
        title: 'Many trials',
        verificationResult: 'failed',
        toolCallCount: 1,
      ),
      _writeManifest(
        directory: directory,
        caseId: 'one-trial',
        title: 'One trial',
        verificationResult: 'passed',
        toolCallCount: 1,
      ),
    ];
    final incumbentCases = <Map<String, Object?>>[
      for (var index = 1; index <= 9; index += 1)
        _caseResult(
          caseId: 'many-trials',
          trialId: 'trial-$index',
          verificationResult: 'failed',
          durationMs: 1000,
          toolCallCount: 1,
          turnCount: 2,
        ),
      _caseResult(
        caseId: 'one-trial',
        verificationResult: 'passed',
        durationMs: 1000,
        toolCallCount: 1,
        turnCount: 2,
      ),
    ];
    final candidateCases = <Map<String, Object?>>[
      for (var index = 1; index <= 9; index += 1)
        _caseResult(
          caseId: 'many-trials',
          trialId: 'trial-$index',
          verificationResult: 'passed',
          durationMs: 900,
          toolCallCount: 1,
          turnCount: 1,
        ),
      _caseResult(
        caseId: 'one-trial',
        verificationResult: 'failed',
        durationMs: 1100,
        toolCallCount: 1,
        turnCount: 3,
      ),
    ];

    final report = await buildPersonalEvalSuiteReport(
      manifestFiles: manifests,
      incumbentResultFile: _writeReplayRun(
        directory: directory,
        fileName: 'incumbent-repeated.json',
        label: 'incumbent',
        cases: incumbentCases,
      ),
      candidateResultFile: _writeReplayRun(
        directory: directory,
        fileName: 'candidate-repeated.json',
        label: 'candidate',
        cases: candidateCases,
      ),
    );

    expect(report.entries, hasLength(2));
    expect(report.statistics.caseCount, 2);
    expect(report.statistics.effectTaskCount, 2);
    expect(report.statistics.repeatedTaskCount, 1);
    expect(report.statistics.pairedTrialCount, 10);
    expect(report.statistics.passRateDifference, 0);
    expect(report.statistics.candidateOnlyPassedCount, 1);
    expect(report.statistics.incumbentOnlyPassedCount, 1);
    expect(report.statistics.medianDurationDifferenceMs, 0);
    expect(report.entries.first.incumbentTrialCount, 9);
    expect(report.entries.first.candidateTrialCount, 9);
    final statisticsJson =
        report.toJson()['pairedStatistics'] as Map<String, dynamic>;
    expect(statisticsJson['effectTaskCount'], 2);
    expect(statisticsJson['pairedTrialCount'], 10);
    expect(statisticsJson['repeatedTaskCount'], 1);
    expect(
      statisticsJson['bootstrap'],
      containsPair('method', 'hierarchical_paired_task_percentile'),
    );
    expect(report.toMarkdown(), contains('Hierarchical paired'));
  });

  test('rejects a candidate run with a missing repeated trial', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-report-missing-trial-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final manifest = _writeManifest(
      directory: directory,
      caseId: 'case-a',
      title: 'Case A',
      verificationResult: 'passed',
      toolCallCount: 1,
    );
    final first = _caseResult(
      caseId: 'case-a',
      trialId: 'trial-1',
      verificationResult: 'passed',
      durationMs: 1000,
      toolCallCount: 1,
      turnCount: 1,
    );

    final report = await buildPersonalEvalSuiteReport(
      manifestFiles: [manifest],
      incumbentResultFile: _writeReplayRun(
        directory: directory,
        fileName: 'incumbent-missing-trial.json',
        label: 'incumbent',
        cases: [
          first,
          _caseResult(
            caseId: 'case-a',
            trialId: 'trial-2',
            verificationResult: 'passed',
            durationMs: 1000,
            toolCallCount: 1,
            turnCount: 1,
          ),
        ],
      ),
      candidateResultFile: _writeReplayRun(
        directory: directory,
        fileName: 'candidate-missing-trial.json',
        label: 'candidate',
        cases: [first],
      ),
      experimentProtocol: _modelSelectionProtocol(),
    );

    expect(report.recommendation, 'reject_candidate');
    expect(
      report.entries.single.hardRegressions,
      contains('missing candidate trial trial-2'),
    );
    expect(report.statistics.pairedTrialCount, 2);
    expect(report.statistics.excludedBinaryTrialPairCount, 1);
  });

  test(
    'keeps corpus design evidence out of model-selection verdicts',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'personal-eval-suite-report-design-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final manifest = _writeManifest(
        directory: directory,
        caseId: 'design-case',
        title: 'Design case',
        verificationResult: 'passed',
        toolCallCount: 1,
      );
      final incumbent = _writeReplayRun(
        directory: directory,
        fileName: 'design-incumbent.json',
        label: 'incumbent',
        cases: [
          _caseResult(
            caseId: 'design-case',
            verificationResult: 'passed',
            durationMs: 1000,
            toolCallCount: 1,
            turnCount: 1,
          ),
        ],
      );
      final candidate = _writeReplayRun(
        directory: directory,
        fileName: 'design-candidate.json',
        label: 'candidate',
        cases: [
          _caseResult(
            caseId: 'design-case',
            verificationResult: 'failed',
            durationMs: 1000,
            toolCallCount: 1,
            turnCount: 1,
          ),
        ],
      );

      final report = await buildPersonalEvalSuiteReport(
        manifestFiles: [manifest],
        incumbentResultFile: incumbent,
        candidateResultFile: candidate,
        experimentProtocol: _corpusDesignProtocol(),
      );

      expect(report.result, 'failed');
      expect(report.hardRegressionCount, 1);
      expect(report.recommendation, 'not_applicable');
      expect(report.decisionEligibility.isEligible, isFalse);
      expect(
        report.decisionEligibility.blockers,
        contains('corpus_design studies do not authorize model selection'),
      );
    },
  );

  test('reports insufficient evidence before evaluating adoption', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-report-insufficient-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final manifest = _writeManifest(
      directory: directory,
      caseId: 'small-case',
      title: 'Small case',
      verificationResult: 'passed',
      toolCallCount: 1,
    );
    final run = _writeReplayRun(
      directory: directory,
      fileName: 'small-run.json',
      label: 'run',
      cases: [
        _caseResult(
          caseId: 'small-case',
          verificationResult: 'passed',
          durationMs: 1000,
          toolCallCount: 1,
          turnCount: 1,
        ),
      ],
    );

    final report = await buildPersonalEvalSuiteReport(
      manifestFiles: [manifest],
      incumbentResultFile: run,
      candidateResultFile: run,
      experimentProtocol: _modelSelectionProtocol(minimumEffectTaskCount: 2),
    );

    expect(report.recommendation, 'insufficient_evidence');
    expect(report.decisionEligibility.isEligible, isFalse);
    expect(report.toMarkdown(), contains('Decision blockers:'));
  });

  test('fails closed when model-selection criteria are missing', () {
    final eligibility = PersonalEvalDecisionEligibility.evaluate(
      experimentProtocol: const PersonalEvalExperimentProtocolProvenance(
        path: '/tmp/protocol.json',
        sha256: 'protocol-digest',
        label: 'Incomplete model selection',
        validationStatus: 'validated',
        studyIntent: 'model_selection',
        minimumEffectTaskCount: null,
        minimumHeldOutEffectTaskCount: null,
        validatedTrialCount: 2,
        validatedExecutionEventCount: 4,
      ),
      effectTaskCount: 1,
      heldOutEffectTaskCount: 0,
    );

    expect(eligibility.isEligible, isFalse);
    expect(
      eligibility.blockers,
      contains('model_selection requires pre-registered decision criteria'),
    );
  });

  test('validates manifests and replay result files', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-report-validation-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final manifest = _writeManifest(
      directory: directory,
      caseId: 'case-a',
      title: 'Case A',
      verificationResult: 'passed',
      toolCallCount: 1,
    );
    final duplicateManifest = _writeManifest(
      directory: directory,
      caseId: 'case-a',
      title: 'Case A duplicate',
      verificationResult: 'passed',
      toolCallCount: 1,
      fileName: 'duplicate.json',
    );
    final run = _writeReplayRun(
      directory: directory,
      fileName: 'run.json',
      label: 'run',
      cases: [
        _caseResult(
          caseId: 'case-a',
          verificationResult: 'passed',
          durationMs: 1000,
          toolCallCount: 1,
          turnCount: 1,
        ),
      ],
    );

    expect(
      () => buildPersonalEvalSuiteReport(
        manifestFiles: [manifest, duplicateManifest],
        incumbentResultFile: run,
        candidateResultFile: run,
      ),
      throwsFormatException,
    );

    final invalidRun = File('${directory.path}/invalid-run.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaName': 'wrong_schema',
          'schemaVersion': 1,
          'label': 'invalid',
          'cases': <Object?>[],
        }),
      );
    expect(
      () => buildPersonalEvalSuiteReport(
        manifestFiles: [manifest],
        incumbentResultFile: invalidRun,
        candidateResultFile: run,
      ),
      throwsFormatException,
    );
  });

  test(
    'preserves authored provenance and rejects a mismatched replay',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'personal-eval-suite-report-provenance-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final manifest = _writeManifest(
        directory: directory,
        caseId: 'authored-case',
        title: 'Authored Case',
        verificationResult: 'inconclusive',
        toolCallCount: 0,
        origin: 'authored',
        split: 'heldOut',
      );
      final authoredResult = _caseResult(
        caseId: 'authored-case',
        verificationResult: 'passed',
        durationMs: 1000,
        toolCallCount: 1,
        turnCount: 2,
        origin: 'authored',
        split: 'heldOut',
      );
      final authoredRun = _writeReplayRun(
        directory: directory,
        fileName: 'authored-run.json',
        label: 'authored',
        cases: [authoredResult],
      );

      final report = await buildPersonalEvalSuiteReport(
        manifestFiles: [manifest],
        incumbentResultFile: authoredRun,
        candidateResultFile: authoredRun,
      );

      expect(report.evidenceOrigins, ['authored']);
      expect(report.splitCounts, {'heldIn': 0, 'heldOut': 1});
      expect(report.entries.single.origin, 'authored');
      expect(report.entries.single.split, 'heldOut');
      expect(report.toMarkdown(), contains('Evidence origins: `authored`'));

      final mismatchedRun = _writeReplayRun(
        directory: directory,
        fileName: 'mismatched-run.json',
        label: 'mismatched',
        cases: [
          {...authoredResult, 'origin': 'recorded'},
        ],
      );
      expect(
        () => buildPersonalEvalSuiteReport(
          manifestFiles: [manifest],
          incumbentResultFile: mismatchedRun,
          candidateResultFile: authoredRun,
        ),
        throwsFormatException,
      );
    },
  );

  test('reports paired statistics by tier and prompt style', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-report-strata-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final guided = _writeManifest(
      directory: directory,
      caseId: 'guided-tier-1',
      title: 'Guided tier 1',
      verificationResult: 'passed',
      toolCallCount: 1,
      origin: 'authored',
      tier: 1,
      promptStyle: 'guided',
    );
    final unguided = _writeManifest(
      directory: directory,
      caseId: 'unguided-tier-2',
      title: 'Unguided tier 2',
      verificationResult: 'failed',
      toolCallCount: 1,
      origin: 'authored',
      split: 'heldOut',
      tier: 2,
      promptStyle: 'unguided',
    );
    Map<String, Object?> result(
      String caseId,
      String verificationResult, {
      required String split,
      required int tier,
      required String promptStyle,
    }) => _caseResult(
      caseId: caseId,
      verificationResult: verificationResult,
      durationMs: 1000,
      toolCallCount: 1,
      turnCount: 1,
      origin: 'authored',
      split: split,
      tier: tier,
      promptStyle: promptStyle,
    );
    final incumbent = _writeReplayRun(
      directory: directory,
      fileName: 'strata-incumbent.json',
      label: 'incumbent',
      cases: [
        result(
          'guided-tier-1',
          'passed',
          split: 'heldIn',
          tier: 1,
          promptStyle: 'guided',
        ),
        result(
          'unguided-tier-2',
          'failed',
          split: 'heldOut',
          tier: 2,
          promptStyle: 'unguided',
        ),
      ],
    );
    final candidate = _writeReplayRun(
      directory: directory,
      fileName: 'strata-candidate.json',
      label: 'candidate',
      cases: [
        result(
          'guided-tier-1',
          'passed',
          split: 'heldIn',
          tier: 1,
          promptStyle: 'guided',
        ),
        result(
          'unguided-tier-2',
          'passed',
          split: 'heldOut',
          tier: 2,
          promptStyle: 'unguided',
        ),
      ],
    );

    final report = await buildPersonalEvalSuiteReport(
      manifestFiles: [guided, unguided],
      incumbentResultFile: incumbent,
      candidateResultFile: candidate,
      experimentProtocol: _modelSelectionProtocol(
        minimumEffectTaskCount: 2,
        minimumHeldOutEffectTaskCount: 1,
      ),
    );

    expect(report.schemaVersion, 7);
    expect(report.tierCounts, {'1': 1, '2': 1});
    expect(report.promptStyleCounts, {'guided': 1, 'unguided': 1});
    expect(report.entries.last.tier, 2);
    expect(report.entries.last.promptStyle, 'unguided');
    final tierTwo = report.strata.singleWhere(
      (stratum) => stratum.dimension == 'tier' && stratum.value == '2',
    );
    expect(tierTwo.caseCount, 1);
    expect(tierTwo.statistics.passRateDifference, 1);
    expect(report.toMarkdown(), contains('## Stratified Statistics'));

    final mismatchedCandidate = _writeReplayRun(
      directory: directory,
      fileName: 'strata-mismatched-candidate.json',
      label: 'candidate',
      cases: [
        result(
          'guided-tier-1',
          'passed',
          split: 'heldIn',
          tier: 2,
          promptStyle: 'guided',
        ),
        result(
          'unguided-tier-2',
          'passed',
          split: 'heldOut',
          tier: 2,
          promptStyle: 'unguided',
        ),
      ],
    );
    expect(
      () => buildPersonalEvalSuiteReport(
        manifestFiles: [guided, unguided],
        incumbentResultFile: incumbent,
        candidateResultFile: mismatchedCandidate,
      ),
      throwsFormatException,
    );
  });

  test('parses CLI options', () {
    final options = PersonalEvalSuiteReportOptions.parse([
      '--manifest',
      'case-a.json',
      '--manifest',
      'case-b.json',
      '--incumbent',
      'incumbent.json',
      '--candidate',
      'candidate.json',
      '--out-dir',
      'reports',
      '--label',
      'candidate check',
    ]);

    expect(options, isNotNull);
    expect(options?.manifestPaths, ['case-a.json', 'case-b.json']);
    expect(options?.incumbentPath, 'incumbent.json');
    expect(options?.candidatePath, 'candidate.json');
    expect(options?.outDir, 'reports');
    expect(options?.label, 'candidate check');
    expect(
      PersonalEvalSuiteReportOptions.parse([
        '--incumbent',
        'incumbent.json',
        '--candidate',
        'candidate.json',
        '--out-dir',
        'reports',
      ]),
      isNull,
    );
  });

  test('a candidate proven better is recommended', () {
    // Every task flips from incumbent-fail to candidate-pass, so the interval
    // sits well above zero.
    final statistics = PersonalEvalPairedStatistics.calculateTasks([
      for (var index = 0; index < 12; index += 1)
        PersonalEvalPairedTaskObservation(
          taskId: 'task-$index',
          trials: const [
            PersonalEvalPairedObservation(
              incumbentPassed: false,
              candidatePassed: true,
            ),
          ],
        ),
    ]);

    expect(statistics.passRateDifference95Ci!.lower, greaterThan(0));
  });

  test('a candidate proven worse is rejected', () {
    final statistics = PersonalEvalPairedStatistics.calculateTasks([
      for (var index = 0; index < 12; index += 1)
        PersonalEvalPairedTaskObservation(
          taskId: 'task-$index',
          trials: const [
            PersonalEvalPairedObservation(
              incumbentPassed: true,
              candidatePassed: false,
            ),
          ],
        ),
    ]);

    expect(statistics.passRateDifference95Ci!.upper, lessThan(0));
  });
}

PersonalEvalExperimentProtocolProvenance _modelSelectionProtocol({
  int minimumEffectTaskCount = 1,
  int minimumHeldOutEffectTaskCount = 0,
}) {
  return PersonalEvalExperimentProtocolProvenance(
    path: '/tmp/protocol.json',
    sha256: 'protocol-digest',
    label: 'Model selection',
    validationStatus: 'validated',
    studyIntent: 'model_selection',
    minimumEffectTaskCount: minimumEffectTaskCount,
    minimumHeldOutEffectTaskCount: minimumHeldOutEffectTaskCount,
    validatedTrialCount: 2,
    validatedExecutionEventCount: 4,
  );
}

PersonalEvalExperimentProtocolProvenance _corpusDesignProtocol() {
  return const PersonalEvalExperimentProtocolProvenance(
    path: '/tmp/protocol.json',
    sha256: 'protocol-digest',
    label: 'Corpus design',
    validationStatus: 'validated',
    studyIntent: 'corpus_design',
    minimumEffectTaskCount: null,
    minimumHeldOutEffectTaskCount: null,
    validatedTrialCount: 2,
    validatedExecutionEventCount: 4,
  );
}

File _writeManifest({
  required Directory directory,
  required String caseId,
  required String title,
  required String verificationResult,
  required int toolCallCount,
  String origin = 'recorded',
  String split = 'heldIn',
  int? tier,
  String? promptStyle,
  String? fileName,
}) {
  final file = File('${directory.path}/${fileName ?? '$caseId.json'}');
  file.writeAsStringSync(
    jsonEncode({
      'schemaName': 'caverno_personal_eval_case_manifest',
      'schemaVersion': 1,
      'generatedAt': '2026-06-14T00:00:00.000Z',
      'caseId': caseId,
      'title': title,
      'readiness': 'ready',
      'origin': origin,
      'split': split,
      'tier': ?tier,
      'promptStyle': ?promptStyle,
      'task': {
        'prompt': 'Do $title.',
        'repoStateRef': 'HEAD',
        'verificationResult': verificationResult,
      },
      'source': {
        'sessionLogPath': '/tmp/$caseId.jsonl',
        'sessionLogSummary': {
          'result': 'complete',
          'entryCount': 2,
          'malformedLineCount': 0,
          'toolCallCount': toolCallCount,
          'totalDurationMs': 1000,
          'operationCounts': {'streamChatCompletion': 1},
          'finishReasonCounts': {'stream_end': 1},
          'warningCodes': <String>[],
          'finalAnswerLineNumber': 2,
        },
      },
      'consent': {
        'explicitUserConsent': true,
        'recordedAt': '2026-06-14T00:00:00.000Z',
        'scope': 'personal_eval_case_recording',
      },
      'privacy': {
        'localOnly': true,
        'anonymization': 'none',
        'exportPolicy': 'excluded_by_default',
      },
    }),
  );
  return file;
}

File _writeReplayRun({
  required Directory directory,
  required String fileName,
  required String label,
  String? model,
  String? baseUrl,
  required List<Map<String, Object?>> cases,
}) {
  final file = File('${directory.path}/$fileName');
  file.writeAsStringSync(
    jsonEncode({
      'schemaName': 'caverno_personal_eval_replay_run',
      'schemaVersion': 1,
      'label': label,
      'model': ?model,
      'baseUrl': ?baseUrl,
      'cases': cases,
    }),
  );
  return file;
}

Map<String, Object?> _caseResult({
  required String caseId,
  String trialId = 'trial-1',
  required String verificationResult,
  required int durationMs,
  required int toolCallCount,
  required int turnCount,
  String origin = 'recorded',
  String split = 'heldIn',
  int? tier,
  String? promptStyle,
}) {
  return {
    'caseId': caseId,
    'trialId': trialId,
    'origin': origin,
    'split': split,
    'tier': ?tier,
    'promptStyle': ?promptStyle,
    'verificationResult': verificationResult,
    'durationMs': durationMs,
    'toolCallCount': toolCallCount,
    'turnCount': turnCount,
  };
}
