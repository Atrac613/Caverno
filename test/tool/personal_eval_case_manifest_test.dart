import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_case_manifest.dart';

void main() {
  test(
    'builds a local-only eval case manifest from a completed session',
    () async {
      final logFile = _writeSessionLog([
        _entry(
          operation: 'streamChatCompletionWithTools',
          finishReason: 'tool_calls',
          content: 'I will inspect the target file.',
          requestMessages: [_message('user', 'Add a ping CLI.')],
          requestTools: [_toolDefinition('read_file')],
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
          content: 'Implemented the ping CLI and verified the focused test.',
          requestMessages: [_message('user', 'Summarize the result.')],
        ),
      ]);

      final manifest = await buildPersonalEvalCaseManifest(
        logFile: logFile,
        caseId: 'ping-cli-2026-06-14',
        title: 'Ping CLI focused task',
        prompt: 'Add a small ping CLI and verify it.',
        repoStateRef: '553263e0',
        verificationCommand: 'fvm flutter test test/tool/ping_cli_test.dart',
        verificationResult: PersonalEvalVerificationResult.passed,
        workspaceMode: 'coding',
        consent: true,
        generatedAt: DateTime.utc(2026, 6, 14, 1, 2, 3),
      );

      expect(manifest.readiness, PersonalEvalCaseReadiness.ready);
      expect(manifest.source.sessionLogSummary.toolCallCount, 1);
      expect(manifest.source.sessionLogSummary.totalDurationMs, 2000);
      expect(
        manifest.source.sessionLogSummary.operationCounts,
        containsPair('streamChatCompletionWithTools', 1),
      );

      final json = manifest.toJson();
      expect(json['schemaName'], 'caverno_personal_eval_case_manifest');
      expect(json['schemaVersion'], 1);
      expect(json['generatedAt'], '2026-06-14T01:02:03.000Z');
      expect(json['caseId'], 'ping-cli-2026-06-14');
      expect(json['readiness'], 'ready');
      expect(
        json['task'],
        containsPair('prompt', 'Add a small ping CLI and verify it.'),
      );
      expect(json['task'], containsPair('repoStateRef', '553263e0'));
      expect(json['task'], containsPair('verificationResult', 'passed'));
      expect(
        json['task'],
        containsPair(
          'verificationCommand',
          'fvm flutter test test/tool/ping_cli_test.dart',
        ),
      );
      expect(json['task'], containsPair('workspaceMode', 'coding'));
      expect(json['consent'], containsPair('explicitUserConsent', isTrue));
      expect(
        json['consent'],
        containsPair('scope', 'personal_eval_case_recording'),
      );
      expect(json['privacy'], containsPair('localOnly', isTrue));
      expect(json['privacy'], containsPair('anonymization', 'none'));
      expect(
        json['privacy'],
        containsPair('exportPolicy', 'excluded_by_default'),
      );
      expect(
        (json['source'] as Map<String, dynamic>)['sessionLogSummary'],
        containsPair('finalAnswerLineNumber', 2),
      );
    },
  );

  test('marks warning-bearing sessions as review recommended', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stream_end',
        content:
            'The root cause is stream_end because the connection was cut off.',
      ),
    ]);

    final manifest = await buildPersonalEvalCaseManifest(
      logFile: logFile,
      caseId: 'stream-end-review',
      title: 'Stream end review',
      prompt: 'Investigate the run.',
      repoStateRef: 'HEAD',
      verificationResult: PersonalEvalVerificationResult.inconclusive,
      consent: true,
    );

    expect(manifest.readiness, PersonalEvalCaseReadiness.reviewRecommended);
    expect(manifest.source.sessionLogSummary.warningCodes, [
      'stream_end_misinterpretation',
    ]);
  });

  test('requires explicit consent before manifest creation', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletion',
        finishReason: 'stream_end',
        content: 'Done.',
      ),
    ]);

    expect(
      () => buildPersonalEvalCaseManifest(
        logFile: logFile,
        caseId: 'no-consent',
        title: 'No consent',
        prompt: 'Do the work.',
        repoStateRef: 'HEAD',
        verificationResult: PersonalEvalVerificationResult.passed,
        consent: false,
      ),
      throwsArgumentError,
    );
  });

  test('rejects incomplete session logs', () async {
    final logFile = _writeSessionLog([
      _entry(
        operation: 'streamChatCompletionWithTools',
        finishReason: 'tool_calls',
        content: 'I need a tool.',
        toolCalls: [
          _toolCall(
            id: 'tool-read',
            name: 'read_file',
            arguments: {'path': 'lib/main.dart'},
          ),
        ],
      ),
    ]);

    expect(
      () => buildPersonalEvalCaseManifest(
        logFile: logFile,
        caseId: 'incomplete-session',
        title: 'Incomplete session',
        prompt: 'Do the work.',
        repoStateRef: 'HEAD',
        verificationResult: PersonalEvalVerificationResult.failed,
        consent: true,
      ),
      throwsStateError,
    );
  });

  test('parses CLI options and resolves prompt files', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-options-test-',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final promptFile = File('${directory.path}/prompt.txt')
      ..writeAsStringSync('Replay this task.');

    final options = PersonalEvalCaseManifestOptions.parse([
      '--log',
      'session.jsonl',
      '--case-id',
      'case-1',
      '--title',
      'Case 1',
      '--prompt-file',
      promptFile.path,
      '--repo-state-ref',
      'abc123',
      '--verification-result',
      'failed',
      '--verification-command',
      'tool/codex_verify.sh',
      '--workspace-mode',
      'coding',
      '--out',
      'case.json',
      '--consent',
    ]);

    expect(options, isNotNull);
    expect(options?.verificationResult, PersonalEvalVerificationResult.failed);
    expect(options?.consent, isTrue);
    expect(await options?.resolvePrompt(), 'Replay this task.');
    expect(
      PersonalEvalCaseManifestOptions.parse([
        '--log',
        'session.jsonl',
        '--case-id',
        'case-1',
        '--title',
        'Case 1',
        '--prompt',
        'inline',
        '--prompt-file',
        promptFile.path,
        '--repo-state-ref',
        'abc123',
        '--verification-result',
        'passed',
      ]),
      isNull,
    );
    expect(
      PersonalEvalCaseManifestOptions.parse([
        '--log',
        'session.jsonl',
        '--case-id',
        'case-1',
        '--title',
        'Case 1',
        '--prompt',
        'inline',
        '--repo-state-ref',
        'abc123',
        '--verification-result',
        'unknown',
      ]),
      isNull,
    );
  });
}

File _writeSessionLog(List<Map<String, Object?>> entries) {
  final directory = Directory.systemTemp.createTempSync(
    'personal-eval-case-test-',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  final logFile = File('${directory.path}/session.jsonl');
  logFile.writeAsStringSync(
    entries.map((entry) => jsonEncode(entry)).join('\n'),
  );
  return logFile;
}

Map<String, Object?> _entry({
  required String operation,
  String? finishReason,
  String content = '',
  List<Map<String, Object?>> requestMessages = const [],
  List<Map<String, Object?>> requestTools = const [],
  List<Map<String, Object?>> toolCalls = const [],
  Map<String, Object?>? error,
}) {
  return {
    'schemaName': 'caverno_llm_session_log_entry',
    'schemaVersion': 1,
    'timestamp': '2026-06-14T00:00:00.000',
    'startedAt': '2026-06-14T00:00:00.000',
    'finishedAt': '2026-06-14T00:00:01.000',
    'durationMs': 1000,
    'operation': operation,
    'context': {'phase': 'chat_turn', 'workspaceMode': 'coding'},
    'request': {
      'messages': requestMessages,
      'tools': requestTools,
      'model': 'test-model',
      'temperature': 0.2,
      'maxTokens': 4096,
    },
    if (error == null)
      'response': {
        ...?finishReason == null ? null : {'finishReason': finishReason},
        'content': content,
        'toolCalls': toolCalls,
      },
    ...?error == null ? null : {'error': error},
  };
}

Map<String, Object?> _message(String role, String content) {
  return {'role': role, 'content': content};
}

Map<String, Object?> _toolDefinition(String name) {
  return {
    'type': 'function',
    'function': {'name': name},
  };
}

Map<String, Object?> _toolCall({
  required String id,
  required String name,
  required Map<String, Object?> arguments,
}) {
  return {'id': id, 'name': name, 'arguments': arguments};
}
