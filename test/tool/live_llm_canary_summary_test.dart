import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_canary_summary.dart';

void main() {
  test('builds a passing summary from Flutter JSON reporter output', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        'The following plugins do not support Swift Package Manager for ios:',
        jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
        jsonEncode({
          'test': {
            'id': 1,
            'name': 'loading tool/canaries/chat_live_llm_canary_test.dart',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 0,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': false,
          'hidden': true,
          'type': 'testDone',
          'time': 10,
        }),
        jsonEncode({
          'test': {
            'id': 2,
            'name': 'live LLM embedded tool call executes once',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 20,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[ChatNotifier] Recovered content-tool continuation with non-streaming completion',
          'type': 'print',
          'time': 30,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[ContentTool] Recovering incomplete tool_call(s): 1',
          'type': 'print',
          'time': 31,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[ContentTool] Ignoring assistant-authored tool_result tag(s): arp',
          'type': 'print',
          'time': 32,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[LLM] model: test-model, temperature: 1.7, maxTokens: 2048',
          'type': 'print',
          'time': 32,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[LLM] model: test-model, temperature: 0.2, maxTokens: 2048',
          'type': 'print',
          'time': 32,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              'assistant: I can fix it now.\n\n[Tool: edit_file]\nArguments: {"path":"lib/src/ping_command.dart"}',
          'type': 'print',
          'time': 33,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[CodingDiagnostics] Analyzer feedback summary: {"toolName":"dart_analyze_feedback","diagnosticCount":2,"files":["lib/main.dart"],"durationMs":80,"commandAttemptCount":2,"fallbackCommandCount":1,"timedOutCommandCount":0,"startErrorCommandCount":0}',
          'type': 'print',
          'time': 34,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[CodingVerification] Test feedback summary: {"toolName":"dart_test_feedback","trigger":"completionClaim","validationStatus":"failed","files":["lib/canary_value.dart"],"passedCount":1,"failedCount":1,"skippedCount":0,"durationMs":120,"commandAttemptCount":1,"fallbackCommandCount":0,"timedOutCommandCount":0,"startErrorCommandCount":0}',
          'type': 'print',
          'time': 35,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[CodingOutputGuardrail] Feedback summary: {"toolName":"coding_output_feedback","provider":"command_output_guardrail","validationStatus":"failed","issueCount":1,"commands":["python3 get_weather.py"]}',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[GoalAutoContinue] continue 2/5: incomplete evidence remains; conversation=goal-1; evidence=3 unresolved Error diagnostic(s) in lib/main.dart',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[GoalAutoContinue] continue 3/5: diagnostics improved; one repair extension granted; conversation=goal-1; evidence=1 unresolved Error diagnostic(s) in lib/main.dart',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[DiagnosticRepairContract] diagnostic signature changed',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[DiagnosticRepairContract] activated; signatureStreak=2',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[CommandDiagnostic] observed; signatureStreak=6; signatureChanged=false',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[CommandDiagnosticRepairFocus] activated; signatureStreak=1',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[CommandDiagnosticRepairFocus] blocked unchanged verifier replay; signatureStreak=1',
          'type': 'print',
          'time': 37,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[ExecutionShadow] contract=1234abcd stage=implement action=repair activeTaskRef=89abcdef taskStatus=inProgress validation=failed tasks=0/1 questions=0 requiresValidation=true hasDiagnostic=true diagnosticStreak=1',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[Tool] Arguments: {command: dart run tool/verify_fixture.dart, working_directory: /tmp/app}',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[LLM] {"canary":"fixture","command":"dart run tool/verify_fixture.dart","exit_code":0}',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              '[GoalAutoContinue] stopAndBlock: diagnostic repair continuation budget reached; conversation=goal-1; evidence=1 unresolved Error diagnostic(s) in lib/main.dart',
          'type': 'print',
          'time': 36,
        }),
        jsonEncode({
          'testID': 2,
          'message':
              'First call process_start with command "sleep 3 && echo ok".',
          'type': 'print',
          'time': 37,
        }),
        jsonEncode({
          'testID': 2,
          'message': '{"name":"process_start","description":"Starts one"}',
          'type': 'print',
          'time': 38,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[Tool] Executing tool: process_start',
          'type': 'print',
          'time': 39,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[Tool] Executing tool: process_wait',
          'type': 'print',
          'time': 40,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[ToolCall] process_start',
          'type': 'print',
          'time': 41,
        }),
        jsonEncode({
          'testID': 2,
          'message': '[ToolCall] process_wait',
          'type': 'print',
          'time': 42,
        }),
        jsonEncode({
          'testID': 2,
          'message': '{"code":"background_process_still_running"}',
          'type': 'print',
          'time': 43,
        }),
        jsonEncode({
          'testID': 2,
          'message': '{"code":"background_process_completed"}',
          'type': 'print',
          'time': 44,
        }),
        jsonEncode({
          'testID': 2,
          'message': '{"code":"background_process_status_unverified"}',
          'type': 'print',
          'time': 45,
        }),
        jsonEncode({
          'testID': 2,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 120,
        }),
        jsonEncode({
          'test': {
            'id': 3,
            'name': 'live LLM answers from compacted oversized tool results',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 130,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[Compaction] Retrying tool-result follow-up after context-length error with compact tool results',
          'type': 'print',
          'time': 135,
        }),
        jsonEncode({
          'testID': 3,
          'message': '[Tool] Requesting coding continuation recovery',
          'type': 'print',
          'time': 136,
        }),
        jsonEncode({
          'testID': 3,
          'message': '[Tool] Coding continuation recovery requested tool calls',
          'type': 'print',
          'time': 137,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[Tool] Coding continuation recovery requested follow-up tool calls',
          'type': 'print',
          'time': 138,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[PendingActionLengthRecovery] Deferring truncated incomplete coding work',
          'type': 'print',
          'time': 138,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[PendingActionLengthRecovery] Requesting one bounded tool-aware retry',
          'type': 'print',
          'time': 138,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[PendingActionLengthRecovery] Tool-aware retry requested one or more tool calls',
          'type': 'print',
          'time': 138,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[InspectionReplay] Replayed successful read_file result for mutation generation 2',
          'type': 'print',
          'time': 138,
        }),
        jsonEncode({
          'testID': 3,
          'message': '[Tool] Terminal success accepted for current generation',
          'type': 'print',
          'time': 135,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[TurnFinalization] Requesting recovery before saving response',
          'type': 'print',
          'time': 139,
        }),
        jsonEncode({
          'testID': 3,
          'message': '[TurnFinalization] Recovery requested tool calls',
          'type': 'print',
          'time': 140,
        }),
        jsonEncode({
          'testID': 3,
          'message':
              '[LLM] model: test-model, temperature: 0.2, maxTokens: 2048',
          'type': 'print',
          'time': 141,
        }),
        jsonEncode({
          'testID': 3,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 240,
        }),
        jsonEncode({'success': true, 'type': 'done', 'time': 250}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'chat_live_llm_canary',
      surface: 'chat',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_chat_live_llm_canary.sh',
      generatedAt: DateTime.utc(2026, 5, 23, 1, 2, 3),
    );

    expect(summary.result, 'passed');
    expect(summary.isSuccessful, isTrue);
    expect(summary.testCount, 2);
    expect(summary.passedCount, 2);
    expect(summary.failedCount, 0);
    expect(summary.skippedCount, 0);
    expect(summary.hiddenTestCount, 1);
    expect(summary.durationMs, 250);
    expect(summary.signals.recoveredStreamFallbackCount, 1);
    expect(summary.signals.toolResultCompactionRetryCount, 1);
    expect(summary.signals.codingContinuationRecoveryRequestCount, 1);
    expect(summary.signals.codingContinuationRecoveryToolCallCount, 2);
    expect(summary.signals.pendingActionLengthDeferralCount, 1);
    expect(summary.signals.pendingActionLengthRecoveryRequestCount, 1);
    expect(summary.signals.pendingActionLengthRecoveryToolCallCount, 1);
    expect(summary.signals.successfulReadResultReplayCount, 1);
    expect(summary.signals.turnFinalizationRecoveryRequestCount, 1);
    expect(summary.signals.turnFinalizationRecoveryToolCallCount, 1);
    expect(summary.signals.incompleteContentToolRecoveryCount, 1);
    expect(summary.signals.ignoredAssistantToolResultCount, 1);
    expect(summary.signals.assistantAuthoredToolBlockCount, 1);
    expect(summary.signals.dartAnalyzeFeedback.observed, isTrue);
    expect(summary.signals.dartAnalyzeFeedback.feedbackCount, 1);
    expect(summary.signals.dartAnalyzeFeedback.diagnosticCount, 2);
    expect(summary.signals.dartAnalyzeFeedback.files, ['lib/main.dart']);
    expect(summary.signals.dartAnalyzeFeedback.durationMs, 80);
    expect(summary.signals.dartAnalyzeFeedback.commandAttemptCount, 2);
    expect(summary.signals.dartAnalyzeFeedback.fallbackCommandCount, 1);
    expect(summary.signals.dartAnalyzeFeedback.timedOutCommandCount, 0);
    expect(summary.signals.dartAnalyzeFeedback.startErrorCommandCount, 0);
    expect(summary.signals.dartTestFeedback.observed, isTrue);
    expect(summary.signals.dartTestFeedback.feedbackCount, 1);
    expect(summary.signals.dartTestFeedback.passedCount, 1);
    expect(summary.signals.dartTestFeedback.failedCount, 1);
    expect(summary.signals.dartTestFeedback.skippedCount, 0);
    expect(summary.signals.dartTestFeedback.files, ['lib/canary_value.dart']);
    expect(summary.signals.dartTestFeedback.triggers, ['completionClaim']);
    expect(summary.signals.dartTestFeedback.validationStatuses, ['failed']);
    expect(summary.signals.dartTestFeedback.durationMs, 120);
    expect(summary.signals.dartTestFeedback.commandAttemptCount, 1);
    expect(summary.signals.dartTestFeedback.fallbackCommandCount, 0);
    expect(summary.signals.dartTestFeedback.timedOutCommandCount, 0);
    expect(summary.signals.dartTestFeedback.startErrorCommandCount, 0);
    expect(summary.signals.codingOutputFeedback.observed, isTrue);
    expect(summary.signals.codingOutputFeedback.feedbackCount, 1);
    expect(summary.signals.codingOutputFeedback.issueCount, 1);
    expect(summary.signals.codingOutputFeedback.commands, [
      'python3 get_weather.py',
    ]);
    expect(summary.signals.codingOutputFeedback.validationStatuses, ['failed']);
    expect(summary.signals.processStartCount, 2);
    expect(summary.signals.processWaitCount, 2);
    expect(summary.signals.backgroundProcessStillRunningCount, 1);
    expect(summary.signals.backgroundProcessCompletedCount, 1);
    expect(summary.signals.backgroundProcessFailedCount, 0);
    expect(summary.signals.backgroundProcessStatusUnverifiedCount, 1);
    expect(summary.signals.goalAutoContinue.continuationCount, 2);
    expect(summary.signals.goalAutoContinue.diagnosticCounts, [3, 1, 1]);
    expect(summary.signals.goalAutoContinue.progressExtensionCount, 1);
    expect(
      summary.signals.goalAutoContinue.finalStopReason,
      'diagnostic repair continuation budget reached',
    );
    expect(summary.signals.goalAutoContinue.firstVerifierTurn, 3);
    expect(summary.signals.goalAutoContinue.successfulVerifierObserved, isTrue);
    expect(
      summary.signals.goalAutoContinue.terminalSuccessExitObserved,
      isTrue,
    );
    expect(
      summary.signals.goalAutoContinue.blockedAfterSuccessfulVerifier,
      isTrue,
    );
    expect(summary.signals.goalAutoContinue.repairContractActivationCount, 1);
    expect(
      summary
          .signals
          .goalAutoContinue
          .commandDiagnosticRepairFocusActivationCount,
      1,
    );
    expect(
      summary
          .signals
          .goalAutoContinue
          .commandDiagnosticRepairFocusActivationStreaks,
      [1],
    );
    expect(
      summary.signals.goalAutoContinue.unchangedVerifierReplayBeforeRepairCount,
      0,
    );
    expect(
      summary.signals.goalAutoContinue.blockedUnchangedVerifierReplayCount,
      1,
    );
    expect(summary.signals.goalAutoContinue.diagnosticSignatureChangeCount, 1);
    expect(
      summary.signals.goalAutoContinue.maxIdenticalDiagnosticSignatureStreak,
      6,
    );
    expect(summary.signals.requestTemperatures.totalRequestCount, 3);
    expect(summary.signals.requestTemperatures.distinctTemperatures, [
      '0.2',
      '1.7',
    ]);
    expect(summary.signals.requestTemperatures.countsByTemperature, {
      '0.2': 2,
      '1.7': 1,
    });

    final json = summary.toJson();
    expect(json['schemaName'], 'live_llm_canary_summary');
    expect(json['schemaVersion'], 3);
    expect(json['generatedAt'], '2026-05-23T01:02:03.000Z');
    expect(json['mainReadiness'], containsPair('status', 'ready'));
    expect(json['tests'], hasLength(2));
    expect(
      (json['tests'] as List<dynamic>).first,
      containsPair('category', 'core_tool'),
    );
    expect(
      (json['tests'] as List<dynamic>).first,
      containsPair('readinessImpact', 'satisfied'),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['dartAnalyzeFeedback'],
      containsPair('diagnosticCount', 2),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['dartAnalyzeFeedback'],
      containsPair('durationMs', 80),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['dartTestFeedback'],
      containsPair('failedCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['codingOutputFeedback'],
      containsPair('issueCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('codingContinuationRecoveryRequestCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('pendingActionLengthDeferralCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('pendingActionLengthRecoveryRequestCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('pendingActionLengthRecoveryToolCallCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('successfulReadResultReplayCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('turnFinalizationRecoveryRequestCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('processStartCount', 2),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('processWaitCount', 2),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('backgroundProcessCompletedCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>),
      containsPair('backgroundProcessStatusUnverifiedCount', 1),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['requestTemperatures'],
      containsPair('totalRequestCount', 3),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['goalAutoContinue'],
      containsPair('diagnosticCounts', [3, 1, 1]),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['goalAutoContinue'],
      containsPair('commandDiagnosticRepairFocusActivationStreaks', [1]),
    );
    expect(
      (json['signals'] as Map<String, dynamic>)['goalAutoContinue'],
      containsPair('blockedUnchangedVerifierReplayCount', 1),
    );
    expect(
      ((json['signals'] as Map<String, dynamic>)['requestTemperatures']
          as Map<String, dynamic>)['countsByTemperature'],
      {'0.2': 2, '1.7': 1},
    );
    expect(summary.toMarkdown(), contains('Live LLM Canary Summary'));
    expect(summary.toMarkdown(), contains('Main readiness: `ready`'));
    expect(summary.toMarkdown(), contains('## Main Readiness'));
    expect(summary.toMarkdown(), contains('## Goal Auto-Continue'));
    expect(
      summary.toMarkdown(),
      contains('Diagnostic progression: `3 -> 1 -> 1`'),
    );
    expect(
      summary.toMarkdown(),
      contains('Blocked after successful verifier: `yes`'),
    );
    expect(
      summary.toMarkdown(),
      contains('Terminal success exit observed: `yes`'),
    );
    expect(
      summary.toMarkdown(),
      contains('Goal repair contract activation count: `1`'),
    );
    expect(
      summary.toMarkdown(),
      contains('Command diagnostic repair focus activation count: `1`'),
    );
    expect(
      summary.toMarkdown(),
      contains('Unchanged verifier replays before repair focus: `0`'),
    );
    expect(
      summary.toMarkdown(),
      contains('Blocked unchanged verifier replays after repair focus: `1`'),
    );
    expect(summary.toMarkdown(), contains('Recovered stream fallback count'));
    expect(
      summary.toMarkdown(),
      contains('Coding continuation recovery request count'),
    );
    expect(
      summary.toMarkdown(),
      contains('Turn-finalization recovery request count'),
    );
    expect(
      summary.toMarkdown(),
      contains('Incomplete content-tool recovery count'),
    );
    expect(summary.toMarkdown(), contains('Assistant-authored tool block'));
    expect(summary.toMarkdown(), contains('Process-start call count'));
    expect(summary.toMarkdown(), contains('Process-wait call count'));
    expect(
      summary.toMarkdown(),
      contains('Background process still-running count'),
    );
    expect(summary.toMarkdown(), contains('## Request Temperatures'));
    expect(summary.toMarkdown(), contains('Requests at `0.2`: `2`'));
    expect(
      summary.toMarkdown(),
      contains('Dart analyzer feedback observed: `yes`'),
    );
    expect(summary.toMarkdown(), contains('lib/main.dart'));
    expect(summary.toMarkdown(), contains('Dart analyzer command attempts'));
    expect(
      summary.toMarkdown(),
      contains('Dart test feedback observed: `yes`'),
    );
    expect(summary.toMarkdown(), contains('Dart test command attempts'));
    expect(
      summary.toMarkdown(),
      contains('Command output feedback observed: `yes`'),
    );
    expect(summary.toMarkdown(), contains('python3 get_weather.py'));
  });

  test('uses ExecutionShadow as a repair-focus compatibility fallback', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repair_focus_shadow_summary_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl')
      ..writeAsStringSync(
        [
          jsonEncode({
            'testID': 1,
            'message':
                '[ExecutionShadow] contract=1234abcd stage=implement action=repair activeTaskRef=89abcdef taskStatus=inProgress validation=failed tasks=0/1 questions=0 requiresValidation=true hasDiagnostic=true diagnosticStreak=2',
            'type': 'print',
            'time': 10,
          }),
          jsonEncode({
            'testID': 1,
            'result': 'success',
            'skipped': false,
            'hidden': false,
            'type': 'testDone',
            'time': 20,
          }),
          jsonEncode({'success': true, 'type': 'done', 'time': 20}),
        ].join('\n'),
      );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'repair_focus_shadow_canary',
      surface: 'coding_mvp',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_repair_focus_shadow_canary.sh',
      generatedAt: DateTime.utc(2026, 7, 13),
    );

    expect(
      summary
          .signals
          .goalAutoContinue
          .commandDiagnosticRepairFocusActivationCount,
      1,
    );
    expect(
      summary
          .signals
          .goalAutoContinue
          .commandDiagnosticRepairFocusActivationStreaks,
      [2],
    );
    expect(
      summary.signals.goalAutoContinue.unchangedVerifierReplayBeforeRepairCount,
      1,
    );
  });

  test('terminal success implies successful verifier evidence', () async {
    final directory = await Directory.systemTemp.createTemp(
      'terminal_success_summary_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl')
      ..writeAsStringSync(
        [
          jsonEncode({
            'testID': 1,
            'message':
                '[Tool] Terminal success accepted for current generation',
            'type': 'print',
            'time': 10,
          }),
          jsonEncode({
            'testID': 1,
            'result': 'success',
            'skipped': false,
            'hidden': false,
            'type': 'testDone',
            'time': 20,
          }),
          jsonEncode({'success': true, 'type': 'done', 'time': 20}),
        ].join('\n'),
      );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'terminal_success_canary',
      surface: 'coding_mvp',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'test command',
      generatedAt: DateTime.utc(2026, 7, 12),
    );

    expect(
      summary.signals.goalAutoContinue.terminalSuccessExitObserved,
      isTrue,
    );
    expect(summary.signals.goalAutoContinue.successfulVerifierObserved, isTrue);
  });

  test('marks skipped live canaries as skipped instead of passed', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-skipped-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        jsonEncode({
          'test': {
            'id': 1,
            'name': 'live LLM produces a plain chat response without tools',
            'metadata': {
              'skip': true,
              'skipReason': 'Set CAVERNO_CHAT_LIVE_CANARY=1 to run.',
            },
          },
          'type': 'testStart',
          'time': 0,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': true,
          'hidden': false,
          'type': 'testDone',
          'time': 1,
        }),
        jsonEncode({'success': true, 'type': 'done', 'time': 2}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'chat_live_llm_canary',
      surface: 'chat',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_chat_live_llm_canary.sh',
      generatedAt: DateTime.utc(2026, 5, 23),
    );

    expect(summary.result, 'skipped');
    expect(summary.isSuccessful, isFalse);
    expect(summary.skippedCount, 1);
    expect(summary.tests.single.skipReason, contains('CAVERNO_CHAT'));
  });

  test(
    'marks warning-only chat canary failures as usable with warnings',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'live-llm-summary-warning-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final logFile = File('${directory.path}/flutter_test.jsonl');
      await logFile.writeAsString(
        [
          jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
          jsonEncode({
            'test': {
              'id': 1,
              'name': 'live LLM produces a plain chat response without tools',
              'metadata': {'skip': false, 'skipReason': null},
            },
            'type': 'testStart',
            'time': 0,
          }),
          jsonEncode({
            'testID': 1,
            'result': 'success',
            'skipped': false,
            'hidden': false,
            'type': 'testDone',
            'time': 20,
          }),
          jsonEncode({
            'test': {
              'id': 2,
              'name':
                  'live LLM continues after recovered incomplete content tool call',
              'metadata': {'skip': false, 'skipReason': null},
            },
            'type': 'testStart',
            'time': 30,
          }),
          jsonEncode({
            'testID': 2,
            'error':
                'Expected inline_recovery_marker but the model stopped early.',
            'isFailure': true,
            'type': 'error',
            'time': 40,
          }),
          jsonEncode({
            'testID': 2,
            'result': 'failure',
            'skipped': false,
            'hidden': false,
            'type': 'testDone',
            'time': 50,
          }),
          jsonEncode({
            'test': {
              'id': 3,
              'name': 'live LLM trims load_skill follow-up inspection text',
              'metadata': {'skip': false, 'skipReason': null},
            },
            'type': 'testStart',
            'time': 60,
          }),
          jsonEncode({
            'testID': 3,
            'error': 'Expected git_execute_command and list_directory.',
            'isFailure': true,
            'type': 'error',
            'time': 70,
          }),
          jsonEncode({
            'testID': 3,
            'result': 'failure',
            'skipped': false,
            'hidden': false,
            'type': 'testDone',
            'time': 90,
          }),
          jsonEncode({'success': false, 'type': 'done', 'time': 100}),
        ].join('\n'),
      );

      final summary = await buildLiveLlmCanarySummary(
        logFile: logFile,
        canaryName: 'chat_live_llm_canary',
        surface: 'chat',
        baseUrl: 'http://127.0.0.1:1234/v1',
        model: 'test-model',
        command: 'tool/run_chat_live_llm_canary.sh',
        generatedAt: DateTime.utc(2026, 6, 10),
      );

      expect(summary.result, 'failed');
      expect(summary.readiness.status, 'usable_with_warnings');
      expect(summary.readiness.warningFailedCount, 2);
      expect(summary.readiness.blockerFailedCount, 0);
      expect(summary.tests[1].category, 'recovery');
      expect(summary.tests[1].readinessImpact, 'warning');
      expect(summary.tests[1].failureMessage, contains('stopped early'));
      expect(summary.tests[2].category, 'skill_follow_up');
      expect(summary.toMarkdown(), contains('usable_with_warnings'));
      expect(summary.toMarkdown(), contains('Failed Test Details'));
    },
  );

  test('marks core chat failures as blocked readiness', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-blocked-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        jsonEncode({
          'test': {
            'id': 1,
            'name': 'live LLM produces a plain chat response without tools',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 0,
        }),
        jsonEncode({
          'testID': 1,
          'error': 'Expected BASIC marker.',
          'isFailure': true,
          'type': 'error',
          'time': 5,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'failure',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 10,
        }),
        jsonEncode({'success': false, 'type': 'done', 'time': 11}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'chat_live_llm_canary',
      surface: 'chat',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_chat_live_llm_canary.sh',
      generatedAt: DateTime.utc(2026, 6, 10),
    );

    expect(summary.readiness.status, 'blocked');
    expect(summary.readiness.blockerFailedCount, 1);
    expect(summary.tests.single.category, 'core_chat');
    expect(summary.tests.single.readinessImpact, 'blocker');
  });

  test('marks exact preservation failures as blocked readiness', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-exact-preservation-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
        jsonEncode({
          'test': {
            'id': 1,
            'name': 'live LLM preserves exact raw tool result values',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 0,
        }),
        jsonEncode({
          'testID': 1,
          'error': 'Expected exact raw value but got a reformatted URL.',
          'isFailure': true,
          'type': 'error',
          'time': 5,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'failure',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 10,
        }),
        jsonEncode({'success': false, 'type': 'done', 'time': 11}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'chat_live_llm_canary',
      surface: 'chat',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_chat_live_llm_canary.sh',
      generatedAt: DateTime.utc(2026, 6, 10),
    );

    expect(summary.readiness.status, 'blocked');
    expect(summary.readiness.blockerFailedCount, 1);
    expect(summary.tests.single.category, 'exact_preservation');
    expect(summary.tests.single.readinessImpact, 'blocker');
  });

  test('marks transport-disconnect failures as inconclusive readiness', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-inconclusive-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        jsonEncode({
          'test': {
            'id': 1,
            'name':
                'live LLM discovers a deferred tool and reads its persisted artifact',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 0,
        }),
        jsonEncode({
          'testID': 1,
          'message':
              'ClientException: Connection closed before full header was received',
          'type': 'print',
          'time': 4,
        }),
        jsonEncode({
          'testID': 1,
          'error': 'Expected persisted artifact read_file call.',
          'isFailure': true,
          'type': 'error',
          'time': 5,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'failure',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 10,
        }),
        jsonEncode({'success': false, 'type': 'done', 'time': 11}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'chat_live_llm_canary',
      surface: 'chat',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_chat_live_llm_canary.sh',
      generatedAt: DateTime.utc(2026, 6, 10),
    );

    expect(summary.readiness.status, 'inconclusive');
    expect(summary.readiness.blockerFailedCount, 1);
    expect(summary.signals.transportDisconnectCount, 1);
    expect(summary.toMarkdown(), contains('Transport disconnects occurred'));
  });

  test('aggregates repeated Flutter JSON reporter output', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-summary-repeat-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final logFile = File('${directory.path}/flutter_test.jsonl');
    await logFile.writeAsString(
      [
        jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
        jsonEncode({
          'test': {
            'id': 1,
            'name': '[run_01] live LLM edits code and runs the fixture test',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 10,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 110,
        }),
        jsonEncode({'success': true, 'type': 'done', 'time': 120}),
        jsonEncode({'protocolVersion': '0.1.1', 'type': 'start', 'time': 0}),
        jsonEncode({
          'test': {
            'id': 1,
            'name': '[run_02] live LLM edits code and runs the fixture test',
            'metadata': {'skip': false, 'skipReason': null},
          },
          'type': 'testStart',
          'time': 20,
        }),
        jsonEncode({
          'testID': 1,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 140,
        }),
        jsonEncode({'success': false, 'type': 'done', 'time': 160}),
      ].join('\n'),
    );

    final summary = await buildLiveLlmCanarySummary(
      logFile: logFile,
      canaryName: 'coding_goal_live_edit_canary',
      surface: 'coding_goal_edit',
      baseUrl: 'http://127.0.0.1:1234/v1',
      model: 'test-model',
      command: 'tool/run_coding_goal_live_edit_canary.sh',
      generatedAt: DateTime.utc(2026, 5, 26),
    );

    expect(summary.result, 'failed');
    expect(summary.runnerSuccess, isFalse);
    expect(summary.testCount, 2);
    expect(summary.passedCount, 2);
    expect(summary.failedCount, 0);
    expect(summary.durationMs, 280);
    expect(summary.tests.map((test) => test.name), [
      '[run_01] live LLM edits code and runs the fixture test',
      '[run_02] live LLM edits code and runs the fixture test',
    ]);
  });
}
