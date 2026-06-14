import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    );

    expect(report.result, 'passed');
    expect(report.recommendation, 'candidate_ready');
    expect(report.hardRegressionCount, 0);
    expect(report.watchSignalCount, 0);
    expect(report.improvementCount, 7);
    expect(report.incumbent.passRate, 0.5);
    expect(report.candidate.passRate, 1.0);
    expect(report.candidate.averageToolCallDelta, 0);

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
    expect(json['schemaVersion'], 1);
    expect(json['generatedAt'], '2026-06-14T02:03:04.000Z');
    expect(json['label'], 'incumbent vs candidate');
    expect(json['result'], 'passed');
    expect(json['recommendation'], 'candidate_ready');
    expect(json['candidate'], containsPair('passedCount', 2));
    expect(json['entries'], hasLength(2));

    final markdown = report.toMarkdown();
    expect(markdown, contains('Personal Eval Suite Report'));
    expect(markdown, contains('Recommendation: `candidate_ready`'));
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
}

File _writeManifest({
  required Directory directory,
  required String caseId,
  required String title,
  required String verificationResult,
  required int toolCallCount,
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
  required String verificationResult,
  required int durationMs,
  required int toolCallCount,
  required int turnCount,
}) {
  return {
    'caseId': caseId,
    'verificationResult': verificationResult,
    'durationMs': durationMs,
    'toolCallCount': toolCallCount,
    'turnCount': turnCount,
  };
}
