import 'dart:convert';

import '../../../core/utils/content_parser.dart';
import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/data/datasources/chat_remote_datasource.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/services/tool_result_prompt_builder.dart';

class RoutineToolExecutionResult {
  const RoutineToolExecutionResult({
    required this.output,
    this.toolResults = const <ToolResultInfo>[],
    this.wasTruncated = false,
  });

  final String output;
  final List<ToolResultInfo> toolResults;
  final bool wasTruncated;
}

class RoutineToolRunner {
  RoutineToolRunner({required ChatDataSource dataSource})
    : _dataSource = dataSource;

  static const int _maxToolLoopIterations = 5;
  static const int _maxFinalToolIterations = 3;
  static const int _maxMissingActionRetries = 2;

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

    final initialToolCalls = _extractToolCalls(initialResult);
    if (initialToolCalls.isEmpty) {
      return RoutineToolExecutionResult(
        output: initialResult.content.trim(),
        wasTruncated: _isCompletionTruncated(initialResult.finishReason),
      );
    }

    final descriptionsByName =
        ToolResultPromptBuilder.descriptionsByNameFromDefinitions(tools);
    final executedToolResults = <ToolResultInfo>[];
    final executedToolCallKeys = <String>{};
    final toolFailureCounts = <String, int>{};
    var currentToolCalls = initialToolCalls;
    String? currentAssistantContent = initialResult.content.trim().isEmpty
        ? null
        : initialResult.content;
    String? fallbackResponse;
    var wasTruncated = _isCompletionTruncated(initialResult.finishReason);
    var iteration = 0;

    while (currentToolCalls.isNotEmpty && iteration < _maxToolLoopIterations) {
      iteration += 1;
      final batchResult = await _executeToolCallBatch(
        toolCalls: currentToolCalls,
        dispatchToolCall: dispatchToolCall,
        executedToolCallKeys: executedToolCallKeys,
        toolFailureCounts: toolFailureCounts,
      );
      final batchToolResults = batchResult.toolResults;
      executedToolResults.addAll(batchToolResults);

      if (batchToolResults.isEmpty || batchResult.abortLoop) {
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
      wasTruncated =
          wasTruncated || _isCompletionTruncated(nextResult.finishReason);

      final nextContent = nextResult.content.trim();
      final nextToolCalls = _extractToolCalls(nextResult);
      if (nextToolCalls.isNotEmpty) {
        currentToolCalls = nextToolCalls;
        currentAssistantContent = nextContent.isEmpty
            ? null
            : nextResult.content;
      } else {
        fallbackResponse = _hasVisibleOutput(nextContent)
            ? nextResult.content
            : null;
        break;
      }
    }

    if (executedToolResults.isEmpty) {
      return RoutineToolExecutionResult(
        output: initialResult.content.trim(),
        wasTruncated: wasTruncated,
      );
    }

    final answerPrompt = _buildRoutineAnswerPrompt(
      executedToolResults,
      descriptionsByName: descriptionsByName,
    );
    var finalResult = await _dataSource.createChatCompletion(
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
      tools: tools,
    );

    var finalOutput = finalResult.content.trim();
    var finalToolCalls = _extractToolCalls(finalResult);
    wasTruncated =
        wasTruncated || _isCompletionTruncated(finalResult.finishReason);
    var executedFinalToolCall = false;
    var finalIteration = 0;
    var missingActionRetries = 0;
    while (true) {
      if (finalToolCalls.isEmpty) {
        final missingToolNames = _missingRequiredRoutineToolNames(
          messages: messages,
          availableToolNames: descriptionsByName.keys.toSet(),
          executedToolResults: executedToolResults,
        );
        if (missingToolNames.isNotEmpty &&
            missingActionRetries < _maxMissingActionRetries) {
          missingActionRetries += 1;
          finalResult = await _dataSource.createChatCompletion(
            messages: [
              ...messages,
              Message(
                id: 'routine_missing_action_${DateTime.now().millisecondsSinceEpoch}',
                content: _buildMissingRequiredActionPrompt(
                  missingToolNames,
                  executedToolResults,
                  descriptionsByName: descriptionsByName,
                  originalMessages: messages,
                ),
                role: MessageRole.user,
                timestamp: DateTime.now(),
              ),
            ],
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
            tools: tools,
          );
          finalOutput = finalResult.content.trim();
          finalToolCalls = _extractToolCalls(finalResult);
          wasTruncated =
              wasTruncated || _isCompletionTruncated(finalResult.finishReason);
          continue;
        }
        break;
      }

      if (finalIteration >= _maxFinalToolIterations) {
        break;
      }

      finalIteration += 1;
      final batchResult = await _executeToolCallBatch(
        toolCalls: finalToolCalls,
        dispatchToolCall: dispatchToolCall,
        executedToolCallKeys: executedToolCallKeys,
        toolFailureCounts: toolFailureCounts,
      );
      final batchToolResults = batchResult.toolResults;
      if (batchToolResults.isEmpty || batchResult.abortLoop) {
        break;
      }
      executedToolResults.addAll(batchToolResults);
      executedFinalToolCall = true;

      final followUpPrompt = _buildRoutineAnswerPrompt(
        executedToolResults,
        descriptionsByName: descriptionsByName,
      );
      finalResult = await _dataSource.createChatCompletion(
        messages: [
          ...messages,
          Message(
            id: 'routine_tool_result_${DateTime.now().millisecondsSinceEpoch}',
            content: followUpPrompt,
            role: MessageRole.user,
            timestamp: DateTime.now(),
          ),
        ],
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
        tools: tools,
      );
      finalOutput = finalResult.content.trim();
      finalToolCalls = _extractToolCalls(finalResult);
      wasTruncated =
          wasTruncated || _isCompletionTruncated(finalResult.finishReason);
    }

    return RoutineToolExecutionResult(
      output: _hasVisibleOutput(finalOutput) && finalToolCalls.isEmpty
          ? finalOutput
          : (wasTruncated
                ? ''
                : fallbackResponse?.trim() ??
                      (executedFinalToolCall
                          ? 'Routine tools completed.'
                          : '')),
      toolResults: List<ToolResultInfo>.unmodifiable(executedToolResults),
      wasTruncated: wasTruncated,
    );
  }

  Future<_RoutineToolBatchResult> _executeToolCallBatch({
    required List<ToolCallInfo> toolCalls,
    required Future<McpToolResult> Function(ToolCallInfo toolCall)
    dispatchToolCall,
    required Set<String> executedToolCallKeys,
    required Map<String, int> toolFailureCounts,
  }) async {
    final toolResults = <ToolResultInfo>[];
    var abortLoop = false;

    for (final toolCall in toolCalls) {
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

      toolResults.add(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: toolResultText,
        ),
      );

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

    return _RoutineToolBatchResult(
      toolResults: toolResults,
      abortLoop: abortLoop,
    );
  }

  List<ToolCallInfo> _extractToolCalls(ChatCompletionResult result) {
    final calls = <ToolCallInfo>[];
    final seenKeys = <String>{};

    for (final toolCall in result.toolCalls ?? const <ToolCallInfo>[]) {
      final key = _toolExecutionKey(toolCall);
      if (seenKeys.add(key)) {
        calls.add(toolCall);
      }
    }

    for (final toolCall in ContentParser.extractCompletedToolCalls(
      result.content,
    )) {
      final info = ToolCallInfo(
        id: toolCall.occurrenceId ?? 'embedded_${toolCall.name}',
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
      final key = _toolExecutionKey(info);
      if (seenKeys.add(key)) {
        calls.add(info);
      }
    }

    return calls;
  }

  String _toolExecutionKey(ToolCallInfo toolCall) {
    return '${toolCall.name}:${_normalizeArguments(toolCall.arguments)}';
  }

  String _normalizeArguments(Map<String, dynamic> arguments) {
    final sortedEntries = arguments.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return jsonEncode(Map<String, dynamic>.fromEntries(sortedEntries));
  }

  bool _hasVisibleOutput(String content) {
    final parsed = ContentParser.parse(content);
    return parsed.segments.any(
      (segment) =>
          segment.type == ContentType.text && segment.content.trim().isNotEmpty,
    );
  }

  bool _isCompletionTruncated(String finishReason) {
    final normalized = finishReason.trim().toLowerCase();
    return normalized == 'length' || normalized == 'max_tokens';
  }

  String _buildRoutineAnswerPrompt(
    List<ToolResultInfo> toolResults, {
    required Map<String, String> descriptionsByName,
  }) {
    final basePrompt = ToolResultPromptBuilder.buildAnswerPrompt(
      toolResults,
      descriptionsByName: descriptionsByName,
    );
    return [
      'Before writing the final answer, check whether the original routine '
          'prompt still requires any tool action based on these results. If a '
          'remaining tool action is required, call that tool now instead of '
          'answering.',
      'If routine_google_chat_post is available and the original routine prompt '
          'asks for a Google Chat notification when a condition is true, call '
          'routine_google_chat_post before the final answer when the results '
          'show that condition is true.',
      'When the original routine prompt limits the Google Chat notification to '
          'newly discovered, changed, failed, or matching items, the posted '
          'text must include only those matching items. Do not include previous '
          'items, unchanged items, or the full current result list as extra '
          'context unless the prompt explicitly asks for them.',
      'If the original routine prompt says to post only the newly discovered IP '
          'list, routine_google_chat_post.text must contain only the newly '
          'discovered IP addresses. Do not include total active hosts, previous '
          'IPs, unchanged IPs, subnet metadata, timestamps, or explanatory '
          'context in that Google Chat text.',
      'Do not claim that a file was updated, a message was posted, or any other '
          'side effect was completed unless the corresponding tool call has '
          'succeeded.',
      basePrompt,
    ].join('\n\n');
  }

  String _buildMissingRequiredActionPrompt(
    List<String> missingToolNames,
    List<ToolResultInfo> toolResults, {
    required Map<String, String> descriptionsByName,
    required List<Message> originalMessages,
  }) {
    final originalPrompt = _combinedUserPrompt(originalMessages);
    final requiresContentsAlias =
        originalPrompt.toLowerCase().contains('contents') &&
        missingToolNames.contains('write_file');
    final alreadyPosted = toolResults.any(
      (result) => result.name == 'routine_google_chat_post',
    );
    return [
      'The routine is not complete. Required tool action(s) are still missing: '
          '${missingToolNames.join(', ')}.',
      'Do not provide a final answer yet. Call the missing tool action now.',
      if (missingToolNames.contains('write_file'))
        'For write_file, write the current detected state required by the '
            'original routine prompt before reporting completion.',
      if (requiresContentsAlias)
        'The original routine prompt requires the write_file argument name '
            '`contents`; use `contents` instead of `content`.',
      if (alreadyPosted)
        'routine_google_chat_post has already succeeded. Do not call it again '
            'unless a new notification is still explicitly required.',
      _buildRoutineAnswerPrompt(
        toolResults,
        descriptionsByName: descriptionsByName,
      ),
    ].join('\n\n');
  }

  List<String> _missingRequiredRoutineToolNames({
    required List<Message> messages,
    required Set<String> availableToolNames,
    required List<ToolResultInfo> executedToolResults,
  }) {
    final missing = <String>[];
    final executedToolNames = executedToolResults
        .map((result) => result.name)
        .toSet();
    final prompt = _combinedUserPrompt(messages).toLowerCase();

    if (availableToolNames.contains('write_file') &&
        !executedToolNames.contains('write_file') &&
        _promptRequiresFileWrite(prompt) &&
        _hasWritableCurrentStateEvidence(executedToolResults)) {
      missing.add('write_file');
    }

    return missing;
  }

  String _combinedUserPrompt(List<Message> messages) {
    return messages
        .where((message) => message.role == MessageRole.user)
        .map((message) => message.content)
        .join('\n');
  }

  bool _promptRequiresFileWrite(String prompt) {
    final mentionsFile =
        prompt.contains('.json') ||
        prompt.contains('.txt') ||
        prompt.contains('.md') ||
        prompt.contains(' file');
    final mentionsWriteIntent =
        prompt.contains('save ') ||
        prompt.contains('update ') ||
        prompt.contains('write ') ||
        prompt.contains('record ');
    return mentionsFile && mentionsWriteIntent;
  }

  bool _hasWritableCurrentStateEvidence(List<ToolResultInfo> toolResults) {
    if (toolResults.isEmpty) {
      return false;
    }

    final lanScanResults = toolResults
        .where((result) => result.name == 'lan_scan')
        .toList(growable: false);
    if (lanScanResults.isEmpty) {
      return true;
    }

    return lanScanResults.any((result) {
      final text = result.result.toLowerCase();
      if (text.contains('"ok":false') ||
          text.contains('lan_scan_failed') ||
          text.contains('unavailable')) {
        return false;
      }
      return text.contains('"hosts"') ||
          text.contains('"hosts_found"') ||
          text.contains('"ip"');
    });
  }
}

class _RoutineToolBatchResult {
  const _RoutineToolBatchResult({
    required this.toolResults,
    required this.abortLoop,
  });

  final List<ToolResultInfo> toolResults;
  final bool abortLoop;
}
