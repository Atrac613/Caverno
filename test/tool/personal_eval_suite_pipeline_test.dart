import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_case_manifest.dart';
import '../../tool/personal_eval_suite_pipeline.dart';

void main() {
  test('writes replay runs and a suite comparison report', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-pipeline-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final manifests = [
      _writeManifest(
        directory: directory,
        caseId: 'ping-cli',
        title: 'Ping CLI',
        verificationResult: 'passed',
        toolCallCount: 1,
      ),
      _writeManifest(
        directory: directory,
        caseId: 'weather-cli',
        title: 'Weather CLI',
        verificationResult: 'failed',
        toolCallCount: 0,
      ),
    ];
    final incumbentPingLog = _writeSessionLog(
      directory: directory,
      fileName: 'incumbent-ping.jsonl',
      entries: [
        _entry(
          operation: 'streamChatCompletionWithTools',
          finishReason: 'tool_calls',
          content: 'I will inspect the file.',
          toolCalls: [
            _toolCall(
              id: 'tool-read',
              name: 'read_file',
              arguments: {'path': 'lib/ping.dart'},
            ),
          ],
        ),
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content: 'Ping CLI complete.',
        ),
      ],
    );
    final candidatePingLog = _writeSessionLog(
      directory: directory,
      fileName: 'candidate-ping.jsonl',
      entries: [
        _entry(
          operation: 'streamChatCompletionWithTools',
          finishReason: 'tool_calls',
          content: 'I will inspect the file.',
          durationMs: 500,
          toolCalls: [
            _toolCall(
              id: 'tool-read',
              name: 'read_file',
              arguments: {'path': 'lib/ping.dart'},
            ),
          ],
        ),
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content: 'Ping CLI complete.',
          durationMs: 500,
        ),
      ],
    );
    final incumbentWeatherLog = _writeSessionLog(
      directory: directory,
      fileName: 'incumbent-weather.jsonl',
      entries: [
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content: 'Weather CLI could not be completed.',
          durationMs: 3000,
        ),
      ],
    );
    final candidateWeatherLog = _writeSessionLog(
      directory: directory,
      fileName: 'candidate-weather.jsonl',
      entries: [
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content: 'Weather CLI complete.',
          durationMs: 1200,
        ),
      ],
    );
    final outDir = Directory('${directory.path}/reports');

    final result = await runPersonalEvalSuitePipeline(
      manifestFiles: manifests,
      incumbent: PersonalEvalSuitePipelineRunInput(
        label: 'incumbent',
        caseLogFiles: {
          'ping-cli': incumbentPingLog,
          'weather-cli': incumbentWeatherLog,
        },
        verificationResults: {
          'ping-cli': PersonalEvalVerificationResult.passed,
          'weather-cli': PersonalEvalVerificationResult.failed,
        },
        model: 'incumbent-model',
        baseUrl: 'http://localhost:1234/v1',
      ),
      candidate: PersonalEvalSuitePipelineRunInput(
        label: 'candidate',
        caseLogFiles: {
          'ping-cli': candidatePingLog,
          'weather-cli': candidateWeatherLog,
        },
        verificationResults: {
          'ping-cli': PersonalEvalVerificationResult.passed,
          'weather-cli': PersonalEvalVerificationResult.passed,
        },
        model: 'candidate-model',
        baseUrl: 'http://localhost:1235/v1',
      ),
      outDir: outDir,
      label: 'incumbent vs candidate',
      generatedAt: DateTime.utc(2026, 6, 14, 4, 5, 6),
    );

    expect(result.incumbentRunFile.existsSync(), isTrue);
    expect(result.candidateRunFile.existsSync(), isTrue);
    expect(result.reportJsonFile.existsSync(), isTrue);
    expect(result.reportMarkdownFile.existsSync(), isTrue);
    expect(result.profileHandoffJsonFile.existsSync(), isTrue);
    expect(result.profileHandoffMarkdownFile.existsSync(), isTrue);
    expect(result.incumbentRun.totalDurationMs, 5000);
    expect(result.candidateRun.totalDurationMs, 2200);
    expect(result.report.result, 'passed');
    expect(result.report.recommendation, 'candidate_ready');
    expect(result.report.hardRegressionCount, 0);
    expect(result.report.improvementCount, greaterThan(0));
    expect(result.profileHandoff.readyForProfileUpdate, isTrue);
    expect(
      result.profileHandoff.target.profileId,
      'openAiCompatible|http://localhost:1235/v1|candidate-model',
    );

    final incumbentJson = _readJson(result.incumbentRunFile);
    expect(incumbentJson['schemaName'], 'caverno_personal_eval_replay_run');
    expect(incumbentJson['model'], 'incumbent-model');
    expect(incumbentJson['caseCount'], 2);

    final reportJson = _readJson(result.reportJsonFile);
    expect(reportJson['schemaName'], 'caverno_personal_eval_suite_report');
    expect(reportJson['generatedAt'], '2026-06-14T04:05:06.000Z');
    expect(reportJson['label'], 'incumbent vs candidate');
    expect(reportJson['result'], 'passed');
    final profileHandoffJson = _readJson(result.profileHandoffJsonFile);
    expect(
      profileHandoffJson['schemaName'],
      'caverno_personal_eval_profile_handoff',
    );
    expect(profileHandoffJson['readyForProfileUpdate'], isTrue);
    expect(
      result.reportMarkdownFile.readAsStringSync(),
      contains('Personal Eval Suite Report'),
    );
    expect(
      result.profileHandoffMarkdownFile.readAsStringSync(),
      contains('Personal Eval Profile Handoff'),
    );
  });

  test('validates missing candidate replay inputs', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-suite-pipeline-validation-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final manifest = _writeManifest(
      directory: directory,
      caseId: 'case-a',
      title: 'Case A',
      verificationResult: 'passed',
      toolCallCount: 0,
    );
    final log = _writeSessionLog(
      directory: directory,
      fileName: 'case-a.jsonl',
      entries: [
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content: 'Done.',
        ),
      ],
    );

    expect(
      () => runPersonalEvalSuitePipeline(
        manifestFiles: [manifest],
        incumbent: PersonalEvalSuitePipelineRunInput(
          label: 'incumbent',
          caseLogFiles: {'case-a': log},
          verificationResults: {
            'case-a': PersonalEvalVerificationResult.passed,
          },
        ),
        candidate: PersonalEvalSuitePipelineRunInput(
          label: 'candidate',
          caseLogFiles: const {},
          verificationResults: {
            'case-a': PersonalEvalVerificationResult.passed,
          },
        ),
        outDir: Directory('${directory.path}/reports'),
      ),
      throwsFormatException,
    );
  });

  test('parses CLI options', () {
    final options = PersonalEvalSuitePipelineOptions.parse([
      '--manifest',
      'case-a.json',
      '--manifest',
      'case-b.json',
      '--incumbent-label',
      'incumbent',
      '--candidate-label',
      'candidate',
      '--incumbent-case-log',
      'case-a=incumbent-a.jsonl',
      '--candidate-case-log',
      'case-a=candidate-a.jsonl',
      '--incumbent-verification-result',
      'case-a=passed',
      '--candidate-verification-result',
      'case-a=inconclusive',
      '--out-dir',
      'reports',
      '--label',
      'suite check',
      '--incumbent-model',
      'old-model',
      '--candidate-model',
      'new-model',
      '--incumbent-base-url',
      'http://localhost:1234/v1',
      '--candidate-base-url',
      'http://localhost:1235/v1',
    ]);

    expect(options, isNotNull);
    expect(options?.manifestPaths, ['case-a.json', 'case-b.json']);
    expect(options?.incumbentLabel, 'incumbent');
    expect(options?.candidateLabel, 'candidate');
    expect(options?.incumbentCaseLogPaths, {'case-a': 'incumbent-a.jsonl'});
    expect(
      options?.candidateVerificationResults['case-a'],
      PersonalEvalVerificationResult.inconclusive,
    );
    expect(options?.outDir, 'reports');
    expect(options?.label, 'suite check');
    expect(options?.incumbentModel, 'old-model');
    expect(options?.candidateModel, 'new-model');

    expect(
      PersonalEvalSuitePipelineOptions.parse([
        '--manifest',
        'case-a.json',
        '--incumbent-label',
        'incumbent',
        '--candidate-label',
        'candidate',
        '--incumbent-case-log',
        'case-a=incumbent-a.jsonl',
        '--candidate-case-log',
        'case-a=candidate-a.jsonl',
        '--incumbent-verification-result',
        'case-a=passed',
        '--candidate-verification-result',
        'case-a=unknown',
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
}) {
  final file = File('${directory.path}/$caseId.json');
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
          'entryCount': 1,
          'malformedLineCount': 0,
          'toolCallCount': toolCallCount,
          'totalDurationMs': 1000,
          'operationCounts': {'streamChatCompletion': 1},
          'finishReasonCounts': {'stream_end': 1},
          'warningCodes': <String>[],
          'finalAnswerLineNumber': 1,
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

File _writeSessionLog({
  required Directory directory,
  required String fileName,
  required List<Map<String, Object?>> entries,
}) {
  final file = File('${directory.path}/$fileName');
  file.writeAsStringSync(entries.map((entry) => jsonEncode(entry)).join('\n'));
  return file;
}

Map<String, Object?> _entry({
  required String operation,
  String? finishReason,
  String content = '',
  int durationMs = 1000,
  List<Map<String, Object?>> toolCalls = const [],
}) {
  return {
    'schemaName': 'caverno_llm_session_log_entry',
    'schemaVersion': 1,
    'timestamp': '2026-06-14T00:00:00.000',
    'startedAt': '2026-06-14T00:00:00.000',
    'finishedAt': '2026-06-14T00:00:01.000',
    'durationMs': durationMs,
    'operation': operation,
    'context': {'phase': 'chat_turn', 'workspaceMode': 'coding'},
    'request': {
      'messages': [
        {'role': 'user', 'content': 'Run the replay task.'},
      ],
      'tools': <Object?>[],
      'model': 'test-model',
      'temperature': 0.2,
      'maxTokens': 4096,
    },
    'response': {
      'finishReason': ?finishReason,
      'content': content,
      'toolCalls': toolCalls,
    },
  };
}

Map<String, Object?> _toolCall({
  required String id,
  required String name,
  required Map<String, Object?> arguments,
}) {
  return {'id': id, 'name': name, 'arguments': arguments};
}

Map<String, dynamic> _readJson(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}
