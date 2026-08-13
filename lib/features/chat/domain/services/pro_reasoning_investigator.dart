import 'dart:async';
import 'dart:convert';

import '../../data/datasources/chat_datasource.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import '../entities/tool_call_info.dart';
import 'pro_reasoning_models.dart';
import 'pro_reasoning_prompt_builder.dart';

typedef ProReasoningReadOnlyToolRunner =
    Future<McpToolResult> Function(ToolCallInfo toolCall);

typedef ProReasoningInvestigationCallObserver =
    FutureOr<void> Function({
      required List<Message> messages,
      required List<Map<String, dynamic>> tools,
      required ChatCompletionResult result,
      required DateTime startedAt,
      required DateTime finishedAt,
    });

/// Runs the bounded, read-only evidence pass used by Pro Reasoning.
///
/// Tool results are fed back as user-role evidence messages. This follows the
/// main chat loop's compatibility path for local models that mishandle native
/// tool-role history while still keeping the investigator mutation-free.
final class ProReasoningInvestigator {
  const ProReasoningInvestigator({
    this.promptBuilder = const ProReasoningPromptBuilder(),
    this.maxResultCharacters = 6000,
    this.maxEvidenceCharacters = 24000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ProReasoningPromptBuilder promptBuilder;
  final int maxResultCharacters;
  final int maxEvidenceCharacters;
  final DateTime Function() _clock;

  static const allowedToolNames = <String>{
    'get_current_datetime',
    'web_search',
    'web_url_read',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
    'list_directory',
  };

  List<Map<String, dynamic>> readOnlyDefinitions(
    List<Map<String, dynamic>> definitions,
  ) {
    return definitions
        .where((definition) {
          if (definition[McpToolEntity.openAiExternalToolKey] == true) {
            return false;
          }
          return allowedToolNames.contains(_definitionName(definition));
        })
        .map((definition) => Map<String, dynamic>.from(definition))
        .toList(growable: false);
  }

  Future<String> investigate({
    required ChatDataSource dataSource,
    required String model,
    required String question,
    required ProReasoningFrame frame,
    required int maxIterations,
    required DateTime deadline,
    required bool Function() isCancelled,
    required List<Map<String, dynamic>> toolDefinitions,
    required ProReasoningReadOnlyToolRunner runTool,
    ProReasoningInvestigationCallObserver? onLlmCall,
  }) async {
    final tools = readOnlyDefinitions(toolDefinitions);
    final now = _clock();
    final messages = <Message>[
      Message(
        id: 'pro_reasoning_investigation_system',
        role: MessageRole.system,
        timestamp: now,
        content:
            'You are a careful research assistant. Gather evidence, then '
            'return a concise evidence summary with uncertainties.',
      ),
      Message(
        id: 'pro_reasoning_investigation_user',
        role: MessageRole.user,
        timestamp: now,
        content: promptBuilder.buildInvestigationPrompt(
          question: question,
          frame: frame,
        ),
      ),
    ];
    final evidence = <String>[];
    final iterations = maxIterations < 0 ? 0 : maxIterations;

    for (var iteration = 0; iteration < iterations; iteration++) {
      if (isCancelled() || !_clock().isBefore(deadline)) break;
      final callMessages = List<Message>.unmodifiable(messages);
      final startedAt = _clock();
      final result = await dataSource.createChatCompletion(
        messages: callMessages,
        tools: tools.isEmpty ? null : tools,
        model: model,
        temperature: 0.1,
        maxTokens: 1200,
      );
      final finishedAt = _clock();
      await onLlmCall?.call(
        messages: callMessages,
        tools: tools,
        result: result,
        startedAt: startedAt,
        finishedAt: finishedAt,
      );

      final toolCalls = result.toolCalls ?? const <ToolCallInfo>[];
      if (toolCalls.isEmpty) {
        final summary = result.content.trim();
        if (summary.isNotEmpty) {
          evidence.add('Investigator summary:\n${_truncate(summary)}');
        }
        break;
      }

      final feedback = <Map<String, dynamic>>[];
      for (final toolCall in toolCalls) {
        if (isCancelled() || !_clock().isBefore(deadline)) break;
        if (!allowedToolNames.contains(toolCall.name) ||
            !_containsDefinition(tools, toolCall.name)) {
          feedback.add({
            'tool': toolCall.name,
            'ok': false,
            'error': 'Tool denied by the Pro Reasoning read-only policy.',
          });
          continue;
        }
        McpToolResult toolResult;
        try {
          toolResult = await runTool(toolCall);
        } catch (error) {
          toolResult = McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: error.toString(),
          );
        }
        final resultText = _truncate(toolResult.result);
        final record = <String, dynamic>{
          'tool': toolCall.name,
          'arguments': toolCall.arguments,
          'ok': toolResult.isSuccess,
          if (resultText.isNotEmpty) 'result': resultText,
          if (toolResult.errorMessage?.trim().isNotEmpty == true)
            'error': toolResult.errorMessage!.trim(),
        };
        feedback.add(record);
        evidence.add(_renderEvidence(record));
      }
      if (feedback.isEmpty) break;
      messages.add(
        Message(
          id: 'pro_reasoning_investigation_feedback_$iteration',
          role: MessageRole.user,
          timestamp: _clock(),
          content:
              'Read-only tool evidence follows. Use it to decide whether more '
              'evidence is needed. Do not repeat a completed lookup.\n'
              '${jsonEncode(feedback)}',
        ),
      );
      if (_renderEvidenceBlock(evidence).length >= maxEvidenceCharacters) {
        break;
      }
    }

    return _renderEvidenceBlock(evidence);
  }

  String _renderEvidence(Map<String, dynamic> record) {
    final buffer = StringBuffer('- ${record['tool']}');
    final arguments = record['arguments'];
    if (arguments is Map && arguments.isNotEmpty) {
      buffer.write(' ${jsonEncode(arguments)}');
    }
    buffer.write(record['ok'] == true ? '\n  Result: ' : '\n  Error: ');
    buffer.write(record['result'] ?? record['error'] ?? 'No result returned.');
    return buffer.toString();
  }

  String _renderEvidenceBlock(List<String> evidence) {
    if (evidence.isEmpty) return '';
    final rendered = evidence.join('\n');
    if (rendered.length <= maxEvidenceCharacters) return rendered;
    return '${rendered.substring(0, maxEvidenceCharacters).trimRight()}\n'
        '[Evidence truncated to the Pro Reasoning context budget.]';
  }

  String _truncate(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= maxResultCharacters) return trimmed;
    return '${trimmed.substring(0, maxResultCharacters).trimRight()}\n'
        '[Tool result truncated.]';
  }

  bool _containsDefinition(
    List<Map<String, dynamic>> definitions,
    String name,
  ) => definitions.any((definition) => _definitionName(definition) == name);

  String _definitionName(Map<String, dynamic> definition) {
    final function = definition['function'];
    if (function is! Map) return '';
    return function['name']?.toString().trim() ?? '';
  }
}
