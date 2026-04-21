import 'dart:convert';

import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/data/datasources/chat_remote_datasource.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/services/tool_result_prompt_builder.dart';

class RoutineToolExecutionResult {
  const RoutineToolExecutionResult({
    required this.output,
    this.toolResults = const <ToolResultInfo>[],
  });

  final String output;
  final List<ToolResultInfo> toolResults;
}

class RoutineToolRunner {
  RoutineToolRunner({required ChatDataSource dataSource})
    : _dataSource = dataSource;

  static const int _maxIterations = 5;

  final ChatDataSource _dataSource;

  Future<RoutineToolExecutionResult> execute({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    required Future<McpToolResult> Function(ToolCallInfo toolCall)
    dispatchToolCall,
    required String model,
    required double temperature,
    required int maxTokens,
  }) async {
    final initialResult = await _dataSource.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    if (!initialResult.hasToolCalls) {
      return RoutineToolExecutionResult(output: initialResult.content.trim());
    }

    final descriptionsByName =
        ToolResultPromptBuilder.descriptionsByNameFromDefinitions(tools);
    final executedToolResults = <ToolResultInfo>[];
    final executedToolCallKeys = <String>{};
    final toolFailureCounts = <String, int>{};
    var currentToolCalls = initialResult.toolCalls!;
    String? currentAssistantContent = initialResult.content.trim().isEmpty
        ? null
        : initialResult.content;
    String? fallbackResponse;
    var iteration = 0;

    while (currentToolCalls.isNotEmpty && iteration < _maxIterations) {
      iteration += 1;
      final batchToolResults = <ToolResultInfo>[];
      var abortLoop = false;

      for (final toolCall in currentToolCalls) {
        final toolCallKey = _toolExecutionKey(toolCall);
        if (executedToolCallKeys.contains(toolCallKey)) {
          continue;
        }

        final result = await dispatchToolCall(toolCall);
        final toolResultText = result.isSuccess
            ? result.result
            : (result.result.trim().isNotEmpty
                  ? result.result
                  : 'Error: ${result.errorMessage ?? 'Tool execution failed'}');

        final toolResult = ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: toolResultText,
        );
        batchToolResults.add(toolResult);
        executedToolResults.add(toolResult);

        if (result.isSuccess) {
          executedToolCallKeys.add(toolCallKey);
          toolFailureCounts.remove(toolCallKey);
        } else {
          final failureCount = (toolFailureCounts[toolCallKey] ?? 0) + 1;
          toolFailureCounts[toolCallKey] = failureCount;
          if (failureCount >= 2) {
            abortLoop = true;
            break;
          }
        }
      }

      if (batchToolResults.isEmpty || abortLoop) {
        break;
      }

      final nextResult = await _dataSource.createChatCompletionWithToolResults(
        messages: messages,
        toolResults: batchToolResults,
        assistantContent: currentAssistantContent,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );

      final nextContent = nextResult.content.trim();
      if (nextResult.hasToolCalls) {
        currentToolCalls = nextResult.toolCalls!;
        currentAssistantContent = nextContent.isEmpty
            ? null
            : nextResult.content;
      } else {
        fallbackResponse = nextContent.isEmpty ? null : nextResult.content;
        break;
      }
    }

    if (executedToolResults.isEmpty) {
      return RoutineToolExecutionResult(output: initialResult.content.trim());
    }

    final answerPrompt = ToolResultPromptBuilder.buildAnswerPrompt(
      executedToolResults,
      descriptionsByName: descriptionsByName,
    );
    final finalResult = await _dataSource.createChatCompletion(
      messages: [
        ...messages,
        Message(
          id: 'routine_tool_result_${DateTime.now().millisecondsSinceEpoch}',
          content: answerPrompt,
          role: MessageRole.user,
          timestamp: DateTime.now(),
        ),
      ],
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    final finalOutput = finalResult.content.trim();
    return RoutineToolExecutionResult(
      output: finalOutput.isNotEmpty
          ? finalOutput
          : (fallbackResponse?.trim() ?? ''),
      toolResults: List<ToolResultInfo>.unmodifiable(executedToolResults),
    );
  }

  String _toolExecutionKey(ToolCallInfo toolCall) {
    return '${toolCall.name}:${_normalizeArguments(toolCall.arguments)}';
  }

  String _normalizeArguments(Map<String, dynamic> arguments) {
    final sortedEntries = arguments.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return jsonEncode(Map<String, dynamic>.fromEntries(sortedEntries));
  }
}
