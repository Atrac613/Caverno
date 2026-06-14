import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_case_manifest.dart';
import '../../tool/personal_eval_replay_run.dart';
import '../../tool/personal_eval_suite_report.dart' as suite;

void main() {
  test('builds a replay run from manifests and replay session logs', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-replay-run-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final pingManifest = _writeManifest(
      directory: directory,
      caseId: 'ping-cli',
      title: 'Ping CLI',
      verificationResult: 'passed',
      toolCallCount: 1,
    );
    final weatherManifest = _writeManifest(
      directory: directory,
      caseId: 'weather-cli',
      title: 'Weather CLI',
      verificationResult: 'passed',
      toolCallCount: 0,
    );
    final pingLog = _writeSessionLog(
      directory: directory,
      fileName: 'ping.jsonl',
      entries: [
        _entry(
          operation: 'streamChatCompletionWithTools',
          finishReason: 'tool_calls',
          content: 'I will inspect the target file.',
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
          content: 'Implemented and verified the ping CLI.',
        ),
        _entry(
          operation: 'createChatCompletion',
          finishReason: 'stop',
          content: jsonEncode({
            'summary': 'Memory extraction after replay.',
            'open_loops': <String>[],
            'profile': <String, Object?>{},
            'memories': <Object?>[],
          }),
        ),
      ],
    );
    final weatherLog = _writeSessionLog(
      directory: directory,
      fileName: 'weather.jsonl',
      entries: [
        _entry(
          operation: 'streamChatCompletion',
          finishReason: 'stream_end',
          content: 'The weather CLI task is complete.',
          durationMs: 1500,
        ),
      ],
    );

    final run = await buildPersonalEvalReplayRun(
      label: 'candidate',
      manifestFiles: [pingManifest, weatherManifest],
      caseLogFiles: {'ping-cli': pingLog, 'weather-cli': weatherLog},
      verificationResults: {
        'ping-cli': PersonalEvalVerificationResult.passed,
        'weather-cli': PersonalEvalVerificationResult.failed,
      },
      model: 'test-model',
      baseUrl: 'http://localhost:1234/v1',
      generatedAt: DateTime.utc(2026, 6, 14, 3, 4, 5),
    );

    expect(run.schemaName, 'caverno_personal_eval_replay_run');
    expect(run.isSuccessful, isFalse);
    expect(run.passedCount, 1);
    expect(run.failedCount, 1);
    expect(run.inconclusiveCount, 0);
    expect(run.totalDurationMs, 4500);
    expect(run.totalToolCallCount, 1);

    final ping = run.cases.singleWhere((entry) => entry.caseId == 'ping-cli');
    expect(ping.durationMs, 3000);
    expect(ping.toolCallCount, 1);
    expect(ping.turnCount, 2);
    expect(ping.summaryResult, 'complete');
    expect(ping.warningCodes, isEmpty);

    final json = run.toJson();
    expect(json['schemaName'], 'caverno_personal_eval_replay_run');
    expect(json['schemaVersion'], 1);
    expect(json['generatedAt'], '2026-06-14T03:04:05.000Z');
    expect(json['label'], 'candidate');
    expect(json['model'], 'test-model');
    expect(json['baseUrl'], 'http://localhost:1234/v1');
    expect(json['caseCount'], 2);
    expect(json['failedCount'], 1);
    expect(json['cases'], hasLength(2));
    expect(run.toMarkdown(), contains('Personal Eval Replay Run'));

    final incumbentFile = _writeReplayRun(directory, 'incumbent.json', run);
    final candidateFile = _writeReplayRun(directory, 'candidate.json', run);
    final report = await suite.buildPersonalEvalSuiteReport(
      manifestFiles: [pingManifest, weatherManifest],
      incumbentResultFile: incumbentFile,
      candidateResultFile: candidateFile,
      generatedAt: DateTime.utc(2026, 6, 14),
    );
    expect(report.result, 'passed');
    expect(report.entries, hasLength(2));
  });

  test('validates manifests, case logs, and verification results', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-replay-run-validation-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final manifest = _writeManifest(
      directory: directory,
      caseId: 'case-a',
      title: 'Case A',
      verificationResult: 'passed',
      toolCallCount: 0,
    );
    final duplicateManifest = _writeManifest(
      directory: directory,
      caseId: 'case-a',
      title: 'Case A duplicate',
      verificationResult: 'passed',
      toolCallCount: 0,
      fileName: 'duplicate.json',
    );
    final blockedManifest = _writeManifest(
      directory: directory,
      caseId: 'case-b',
      title: 'Case B',
      verificationResult: 'passed',
      toolCallCount: 0,
      readiness: 'blocked',
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
      () => buildPersonalEvalReplayRun(
        label: 'candidate',
        manifestFiles: [manifest, duplicateManifest],
        caseLogFiles: {'case-a': log},
        verificationResults: {'case-a': PersonalEvalVerificationResult.passed},
      ),
      throwsFormatException,
    );

    expect(
      () => buildPersonalEvalReplayRun(
        label: 'candidate',
        manifestFiles: [manifest],
        caseLogFiles: {'unknown': log},
        verificationResults: {'case-a': PersonalEvalVerificationResult.passed},
      ),
      throwsFormatException,
    );

    expect(
      () => buildPersonalEvalReplayRun(
        label: 'candidate',
        manifestFiles: [manifest],
        caseLogFiles: {'case-a': log},
        verificationResults: const {},
      ),
      throwsFormatException,
    );

    expect(
      () => buildPersonalEvalReplayRun(
        label: 'candidate',
        manifestFiles: [blockedManifest],
        caseLogFiles: {'case-b': log},
        verificationResults: {'case-b': PersonalEvalVerificationResult.passed},
      ),
      throwsFormatException,
    );

    final missingLog = File('${directory.path}/missing.jsonl');
    expect(
      () => buildPersonalEvalReplayRun(
        label: 'candidate',
        manifestFiles: [manifest],
        caseLogFiles: {'case-a': missingLog},
        verificationResults: {'case-a': PersonalEvalVerificationResult.passed},
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('parses CLI options', () {
    final options = PersonalEvalReplayRunOptions.parse([
      '--label',
      'candidate',
      '--manifest',
      'case-a.json',
      '--manifest',
      'case-b.json',
      '--case-log',
      'case-a=case-a.jsonl',
      '--case-log',
      'case-b=case-b.jsonl',
      '--verification-result',
      'case-a=passed',
      '--verification-result',
      'case-b=inconclusive',
      '--out',
      'run.json',
      '--model',
      'test-model',
      '--base-url',
      'http://localhost:1234/v1',
    ]);

    expect(options, isNotNull);
    expect(options?.label, 'candidate');
    expect(options?.manifestPaths, ['case-a.json', 'case-b.json']);
    expect(options?.caseLogPaths, {
      'case-a': 'case-a.jsonl',
      'case-b': 'case-b.jsonl',
    });
    expect(
      options?.verificationResults['case-b'],
      PersonalEvalVerificationResult.inconclusive,
    );
    expect(options?.outPath, 'run.json');
    expect(options?.model, 'test-model');
    expect(options?.baseUrl, 'http://localhost:1234/v1');

    expect(
      PersonalEvalReplayRunOptions.parse([
        '--label',
        'candidate',
        '--manifest',
        'case-a.json',
        '--case-log',
        'case-a.jsonl',
        '--verification-result',
        'case-a=passed',
        '--out',
        'run.json',
      ]),
      isNull,
    );
    expect(
      PersonalEvalReplayRunOptions.parse([
        '--label',
        'candidate',
        '--manifest',
        'case-a.json',
        '--case-log',
        'case-a=case-a.jsonl',
        '--verification-result',
        'case-a=unknown',
        '--out',
        'run.json',
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
  String readiness = 'ready',
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
      'readiness': readiness,
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

File _writeReplayRun(
  Directory directory,
  String fileName,
  PersonalEvalReplayRunArtifact run,
) {
  final file = File('${directory.path}/$fileName');
  file.writeAsStringSync(jsonEncode(run.toJson()));
  return file;
}
