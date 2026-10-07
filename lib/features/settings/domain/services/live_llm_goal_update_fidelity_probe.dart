import 'dart:convert';

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/services/goal_update_ack.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

/// Measures exact goal-completion arguments without executing model calls.
/// Request shape, thinking observation and report lifecycle stay in the service.
class LiveLlmGoalUpdateFidelityProbe {
  const LiveLlmGoalUpdateFidelityProbe({
    required Future<ChatCompletionResult> Function() complete,
    required Map<String, String> Function() requestMetadata,
  }) : _complete = complete,
       _requestMetadata = requestMetadata;

  static const probeId = 'update_goal_fidelity';
  static const prompt =
      'The active goal is complete. Report that state by calling '
      'update_goal exactly once with completed set to the JSON boolean '
      'literal true, not the string "true" or "True". Do not add '
      'message or blocked_reason, and do not answer in text.';
  final Future<ChatCompletionResult> Function() _complete;
  final Map<String, String> Function() _requestMetadata;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final result = await _complete();
    final calls = LiveLlmResponseScoring.toolCallsFrom(result);
    final names = calls.map((call) => call.name).toList(growable: false);
    final argumentValidationError =
        calls.length == 1 && calls.single.name == 'update_goal'
        ? GoalUpdateInput.validateArguments(calls.single.arguments)
        : null;
    final passed =
        calls.length == 1 &&
        calls.single.name == 'update_goal' &&
        argumentValidationError == null &&
        calls.single.arguments.length == 1 &&
        calls.single.arguments['completed'] == true;
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.failed,
      summary: passed
          ? 'The model emitted the exact goal-completion tool call.'
          : 'The model did not emit the exact goal-completion tool call.',
      details: passed
          ? 'Observed update_goal with {"completed":true}; it was not executed.'
          : calls.isEmpty
          ? 'No tool calls were returned.'
          : [
              ?argumentValidationError,
              ...calls.map(
                (call) => '${call.name}: ${jsonEncode(call.arguments)}',
              ),
            ].join('\n'),
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      toolCalls: names,
      usage: LiveLlmDiagnosticEvidence.usage(result),
      metadata: {
        ..._requestMetadata(),
        'argumentValidationError': ?argumentValidationError,
      },
    );
  }
}
