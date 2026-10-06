import 'dart:convert';

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';
import 'live_llm_tool_depth_staircase.dart';

/// Tools are supplied for scripted steps and omitted for the final answer.
typedef ToolDepthProbeCompletion =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      List<Map<String, dynamic>>? tools,
    });

/// One staircase measurement, published together by the diagnostic service.
class LiveLlmToolDepthProbeMeasurement {
  const LiveLlmToolDepthProbeMeasurement({
    required this.result,
    required this.metrics,
  });

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticToolDepthMetrics metrics;
}

/// Scripted tool-chain headroom; no tool is executed. Selection, request
/// settings, thinking observation and report publication stay with the service.
class LiveLlmToolDepthProbe {
  const LiveLlmToolDepthProbe({
    required ToolDepthProbeCompletion complete,
    required List<Message> Function(String user) messages,
    DateTime Function() now = DateTime.now,
  }) : _complete = complete,
       _messages = messages,
       _now = now;

  static const probeId = 'tool_state_staircase';

  final ToolDepthProbeCompletion _complete;
  final List<Message> Function(String user) _messages;
  final DateTime Function() _now;

  /// [startedAt] precedes running publication, preserving its elapsed time.
  Future<LiveLlmToolDepthProbeMeasurement> run({
    required DateTime startedAt,
  }) async {
    final completed = <ChatCompletionResult>[];
    final attempted = <int>[];
    var deepest = 0;
    var failureDetail = '';
    String lastContent = '';

    for (final rung in LiveLlmToolDepthStaircase.rungs) {
      attempted.add(rung.depth);
      final outcome = await _runToolDepthRung(rung, completed);
      lastContent = outcome.finalContent;
      if (!outcome.passed) {
        failureDetail = 'depth ${rung.depth}: ${outcome.detail}';
        break;
      }
      deepest = rung.depth;
    }

    final metrics = LiveLlmDiagnosticToolDepthMetrics(
      deepestPassedDepth: deepest,
      attemptedDepths: List.unmodifiable(attempted),
      failureDetail: failureDetail,
    );
    final deepestRung = LiveLlmToolDepthStaircase.stageDepths.last;
    // Never failed. This is headroom above the conformance floor, so a rung
    // the model could not reach is a position on the axis rather than a
    // defect: `multi_round_tool_loop` is the scored floor for tool chaining
    // and does report failure. Failing here would drag a run's overall status
    // down for a probe deliberately worth zero points.
    final status = deepest >= deepestRung
        ? LiveLlmDiagnosticStatus.passed
        : LiveLlmDiagnosticStatus.warning;

    return LiveLlmToolDepthProbeMeasurement(
      result: LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: status,
        summary: deepest == 0
            ? 'The model did not carry state through two tool calls.'
            : deepest >= deepestRung
            ? 'The model carried state through every rung of the staircase.'
            : 'The model carried state through $deepest sequential tool calls.',
        details: [
          'Deepest passed depth: $deepest of $deepestRung',
          'Attempted depths: ${attempted.join(', ')}',
          if (failureDetail.isNotEmpty) failureDetail,
        ].join('\n'),
        modelContent: LiveLlmDiagnosticEvidence.preview(
          LiveLlmResponseScoring.visibleContent(lastContent),
          maxChars: 240,
        ),
        usage: LiveLlmDiagnosticEvidence.totalUsage(completed),
        passedChecks: deepest == 0 ? 0 : attempted.indexOf(deepest) + 1,
        totalChecks: LiveLlmToolDepthStaircase.stageDepths.length,
        elapsed: _now().difference(startedAt),
      ),
      metrics: metrics,
    );
  }

  /// Drives one rung: each scripted step must be the call the model makes, and
  /// the final answer must carry the values only the tool results could supply.
  Future<_ToolDepthRungOutcome> _runToolDepthRung(
    LiveLlmToolDepthRung rung,
    List<ChatCompletionResult> completed,
  ) async {
    var messages = _messages(rung.prompt);

    for (final step in rung.steps) {
      final ChatCompletionResult result;
      try {
        result = await _complete(
          messages: messages,
          tools: LiveLlmToolDepthStaircase.toolDefinitions,
        );
      } on Object catch (error) {
        return _ToolDepthRungOutcome(
          passed: false,
          detail:
              'the request failed (${LiveLlmDiagnosticEvidence.preview('$error', maxChars: 120)})',
        );
      }
      completed.add(result);

      final call = result.toolCalls?.firstOrNull;
      if (call == null) {
        return _ToolDepthRungOutcome(
          passed: false,
          detail: 'expected a ${step.toolName} call and got a text answer',
          finalContent: result.content,
        );
      }
      if (call.name != step.toolName) {
        return _ToolDepthRungOutcome(
          passed: false,
          detail: 'called ${call.name} where ${step.toolName} was expected',
          finalContent: result.content,
        );
      }
      final mismatch = LiveLlmResponseScoring.firstArgumentMismatch(
        call.arguments,
        step.expectedArguments,
      );
      if (mismatch != null) {
        return _ToolDepthRungOutcome(
          passed: false,
          detail: '${step.toolName} carried $mismatch',
          finalContent: result.content,
        );
      }

      // A plain observation, NOT ToolResultPromptBuilder.buildAnswerPrompt.
      // That builder opens with "Please answer the user's question based on
      // the following tool results" and instructs the model to report any
      // action that "remains unexecuted" -- so mid-loop it tells the model to
      // stop and wrap up, and the staircase then scored it for stopping. The
      // first live run returned exactly "doc-ds-42; open_doc remains
      // unexecuted", the phrase lifted from that prompt.
      messages = [
        ...messages,
        Message(
          id: 'live-llm-tool-depth-${step.toolName}-${_now().microsecondsSinceEpoch}',
          content:
              'Tool result for ${step.toolName}:\n'
              '${jsonEncode(step.result)}\n\n'
              'The task is not finished. Call the next tool you need, using '
              'the values this result gave you. Do not answer in text yet.',
          role: MessageRole.user,
          timestamp: _now(),
        ),
      ];
    }

    messages = [
      ...messages,
      Message(
        id: 'live-llm-tool-depth-final-${_now().microsecondsSinceEpoch}',
        content:
            'Every tool call is done. Now answer, using the exact values the '
            'tool results gave you and no other text.',
        role: MessageRole.user,
        timestamp: _now(),
      ),
    ];

    final ChatCompletionResult finalResult;
    try {
      finalResult = await _complete(messages: messages);
    } on Object catch (error) {
      return _ToolDepthRungOutcome(
        passed: false,
        detail:
            'the final request failed (${LiveLlmDiagnosticEvidence.preview('$error', maxChars: 120)})',
      );
    }
    completed.add(finalResult);

    // The visible answer, not the reasoning: a think block that names the
    // carried id on the way to losing it is not the model carrying it.
    final visible = LiveLlmResponseScoring.visibleContent(finalResult.content);
    final missing = rung.expectedFinalValues
        .where((value) => !visible.contains(value))
        .toList();
    if (missing.isNotEmpty) {
      return _ToolDepthRungOutcome(
        passed: false,
        detail: 'the answer lost ${missing.join(', ')}',
        finalContent: finalResult.content,
      );
    }
    return _ToolDepthRungOutcome(
      passed: true,
      finalContent: finalResult.content,
    );
  }
}

class _ToolDepthRungOutcome {
  const _ToolDepthRungOutcome({
    required this.passed,
    this.detail = '',
    this.finalContent = '',
  });

  final bool passed;
  final String detail;
  final String finalContent;
}
