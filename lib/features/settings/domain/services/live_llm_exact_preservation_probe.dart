import 'dart:convert';

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/entities/tool_call_info.dart';
import '../../../chat/domain/services/tool_results/tool_result_prompt_builder.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

typedef ExactPreservationProbeCompletion =
    Future<ChatCompletionResult> Function({required List<Message> messages});

/// Measures literal values across direct, tool-result and URL prompts.
/// Selection, request settings, thinking, errors and publication stay in service.
class LiveLlmExactPreservationProbe {
  const LiveLlmExactPreservationProbe({
    required ExactPreservationProbeCompletion complete,
    required List<Message> Function(String user) messages,
    DateTime Function() now = DateTime.now,
  }) : _complete = complete,
       _messages = messages,
       _now = now;

  static const probeId = 'exact_preservation';
  static const _exactDirectEchoValue = '12 GiB, \u00a53,980';
  static const _exactToolResultValue = 'ZX-900_\u03b1 2026-06-12';
  static const _exactUrlValue =
      'https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def';

  final ExactPreservationProbeCompletion _complete;
  final List<Message> Function(String user) _messages;
  final DateTime Function() _now;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final directResult = await _complete(
      messages: _messages(
        'Reply with exactly this text and no extra characters:\n'
        '$_exactDirectEchoValue',
      ),
    );

    final toolResultMessages = _messages(
      'Return only the product_label value from the diagnostic tool result. '
      'Do not add quotes, punctuation, or explanatory text.',
    );
    toolResultMessages.add(
      Message(
        id: 'live-llm-diagnostic-tool-result-${_now().microsecondsSinceEpoch}',
        content: ToolResultPromptBuilder.buildAnswerPrompt(
          [
            ToolResultInfo(
              id: 'diagnostic-exact-value-call',
              name: 'diagnostic_exact_value',
              arguments: const {'field': 'product_label'},
              result:
                  'Raw result:\n'
                  '${jsonEncode({'product_label': _exactToolResultValue})}',
            ),
          ],
          descriptionsByName: const {
            'diagnostic_exact_value':
                'Provides exact raw values for preservation diagnostics.',
          },
        ),
        role: MessageRole.user,
        timestamp: _now(),
      ),
    );
    final toolResult = await _complete(messages: toolResultMessages);

    final urlResult = await _complete(
      messages: _messages(
        'Reply with exactly this URL and no extra characters:\n'
        '$_exactUrlValue',
      ),
    );

    final outcomes = [
      _ExactPreservationProbeOutcome(
        label: 'direct_echo_money_unit',
        expected: _exactDirectEchoValue,
        actual: LiveLlmResponseScoring.visibleContent(directResult.content),
        rawActual: directResult.content.trim(),
      ),
      _ExactPreservationProbeOutcome(
        label: 'tool_result_raw_value',
        expected: _exactToolResultValue,
        actual: LiveLlmResponseScoring.visibleContent(toolResult.content),
        rawActual: toolResult.content.trim(),
      ),
      _ExactPreservationProbeOutcome(
        label: 'url_preservation',
        expected: _exactUrlValue,
        actual: LiveLlmResponseScoring.visibleContent(urlResult.content),
        rawActual: urlResult.content.trim(),
      ),
    ];
    final failed = outcomes.where((outcome) => !outcome.passed).toList();
    final status = failed.isEmpty
        ? LiveLlmDiagnosticStatus.passed
        : failed.length == outcomes.length
        ? LiveLlmDiagnosticStatus.failed
        : LiveLlmDiagnosticStatus.warning;
    final summary = failed.isEmpty
        ? 'The model preserved exact literal values across direct and tool-result prompts.'
        : failed.length == outcomes.length
        ? 'The model changed every exact literal preservation probe value.'
        : 'The model changed at least one exact literal preservation probe value.';

    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: status,
      summary: summary,
      details: outcomes.map(_formatExactPreservationDetail).join('\n\n'),
      modelContent: outcomes
          .map(
            (outcome) =>
                '${outcome.label}: ${LiveLlmDiagnosticEvidence.preview(outcome.rawActual, maxChars: 360)}',
          )
          .join('\n'),
      usage: LiveLlmDiagnosticEvidence.totalUsage([
        directResult,
        toolResult,
        urlResult,
      ]),
      passedChecks: outcomes.length - failed.length,
      totalChecks: outcomes.length,
    );
  }

  String _formatExactPreservationDetail(
    _ExactPreservationProbeOutcome outcome,
  ) {
    return [
      '${outcome.label}: ${outcome.passed ? 'passed' : 'failed'}',
      'Expected: ${outcome.expected}',
      'Actual: ${LiveLlmDiagnosticEvidence.preview(outcome.actual, maxChars: 800)}',
    ].join('\n');
  }
}

class _ExactPreservationProbeOutcome {
  const _ExactPreservationProbeOutcome({
    required this.label,
    required this.expected,
    required this.actual,
    required this.rawActual,
  });

  final String label;
  final String expected;
  final String actual;
  final String rawActual;

  bool get passed => actual == expected;
}
