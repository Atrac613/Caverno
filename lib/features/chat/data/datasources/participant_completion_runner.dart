import 'dart:async';
import 'dart:convert';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/conversation_participant.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import 'chat_datasource.dart';
import 'chat_remote_datasource.dart';
import 'mesh_secondary_completion_runner.dart';

typedef ParticipantToolCallExecutor =
    Future<McpToolResult> Function(ToolCallInfo toolCall);

class ParticipantCompletionRequest {
  const ParticipantCompletionRequest({
    required this.participant,
    required this.messages,
    required this.model,
    required this.temperature,
    required this.maxTokens,
    this.toolDefinitions = const <Map<String, dynamic>>[],
    this.executeToolCall,
    this.maxToolIterations = 4,
  });

  final ConversationParticipant participant;
  final List<Message> messages;
  final String model;
  final double temperature;
  final int maxTokens;
  final List<Map<String, dynamic>> toolDefinitions;
  final ParticipantToolCallExecutor? executeToolCall;
  final int maxToolIterations;

  bool get hasToolSupport =>
      toolDefinitions.isNotEmpty && executeToolCall != null;
}

class ParticipantCompletionRunner {
  const ParticipantCompletionRunner({required this.meshRunner});

  final MeshSecondaryCompletionRunner<ChatDataSource> meshRunner;

  Future<void> stream({
    required ChatDataSource primary,
    required AppSettings settings,
    required ParticipantCompletionRequest request,
    required bool Function() shouldContinue,
    required FutureOr<void> Function(String chunk) onChunk,
  }) {
    final endpointId = settings.llmProvider == LlmProvider.openAiCompatible
        ? request.participant.endpointId
        : '';
    return meshRunner.run<void>(
      primary: primary,
      primaryBaseUrl: settings.baseUrl,
      primaryApiKey: settings.apiKey,
      endpoints: settings.namedEndpoints,
      endpointId: endpointId,
      model: request.model,
      fallbackModel: settings.effectiveModel,
      call: (dataSource, resolvedModel) async {
        if (request.hasToolSupport) {
          await _streamWithTools(
            dataSource: dataSource,
            request: request,
            resolvedModel: resolvedModel,
            shouldContinue: shouldContinue,
            onChunk: onChunk,
          );
          return;
        }
        await _streamPlain(
          dataSource: dataSource,
          request: request,
          resolvedModel: resolvedModel,
          shouldContinue: shouldContinue,
          onChunk: onChunk,
        );
      },
    );
  }

  Future<void> _streamPlain({
    required ChatDataSource dataSource,
    required ParticipantCompletionRequest request,
    required String resolvedModel,
    required bool Function() shouldContinue,
    required FutureOr<void> Function(String chunk) onChunk,
  }) async {
    final stream = dataSource.streamChatCompletion(
      messages: request.messages,
      model: resolvedModel,
      temperature: request.temperature,
      maxTokens: request.maxTokens,
    );
    await for (final chunk in stream) {
      if (!shouldContinue()) {
        return;
      }
      await onChunk(chunk);
    }
  }

  Future<void> _streamWithTools({
    required ChatDataSource dataSource,
    required ParticipantCompletionRequest request,
    required String resolvedModel,
    required bool Function() shouldContinue,
    required FutureOr<void> Function(String chunk) onChunk,
  }) async {
    final executeToolCall = request.executeToolCall;
    if (executeToolCall == null) {
      await _streamPlain(
        dataSource: dataSource,
        request: request,
        resolvedModel: resolvedModel,
        shouldContinue: shouldContinue,
        onChunk: onChunk,
      );
      return;
    }

    final messages = [...request.messages];
    final executedToolCallKeys = <String>{};
    final maxToolIterations = request.maxToolIterations.clamp(1, 8);

    for (var iteration = 0; iteration < maxToolIterations; iteration += 1) {
      final result = dataSource.streamChatCompletionWithTools(
        messages: messages,
        tools: request.toolDefinitions,
        model: resolvedModel,
        temperature: request.temperature,
        maxTokens: request.maxTokens,
      );
      final streamedContent = StringBuffer();
      await for (final chunk in result.stream) {
        if (!shouldContinue()) {
          return;
        }
        streamedContent.write(chunk);
      }

      final completion = await result.completion;
      if (!shouldContinue()) {
        return;
      }

      if (!completion.hasToolCalls) {
        final visibleContent = streamedContent.isNotEmpty
            ? streamedContent.toString()
            : completion.content;
        if (visibleContent.isNotEmpty) {
          await onChunk(visibleContent);
        }
        return;
      }

      final toolResults = <ToolResultInfo>[];
      for (final toolCall in completion.toolCalls!) {
        if (!shouldContinue()) {
          return;
        }
        final toolCallKey = _toolCallKey(toolCall);
        if (!executedToolCallKeys.add(toolCallKey)) {
          toolResults.add(_duplicateToolResult(toolCall));
          continue;
        }
        final toolResult = await executeToolCall(toolCall);
        toolResults.add(_toPromptToolResult(toolCall, toolResult));
      }

      final assistantContent = _assistantContentForToolResultContext(
        completion: completion,
        streamedContent: streamedContent.toString(),
      );
      if (assistantContent != null) {
        messages.add(
          Message(
            id: 'participant_tool_assistant_${DateTime.now().microsecondsSinceEpoch}',
            content: assistantContent,
            role: MessageRole.assistant,
            timestamp: DateTime.now(),
            participantId: request.participant.id,
            participantDisplayName: request.participant.effectiveDisplayName,
            participantRoleLabel: request.participant.effectiveRoleLabel,
            participantColorValue: request.participant.colorValue,
          ),
        );
      }
      messages.add(_buildToolResultMessage(toolResults));
    }

    if (shouldContinue()) {
      await onChunk(
        '\n\nParticipant tool calls stopped after reaching the safety limit.',
      );
    }
  }

  ToolResultInfo _toPromptToolResult(
    ToolCallInfo toolCall,
    McpToolResult toolResult,
  ) {
    final resultText = toolResult.isSuccess
        ? toolResult.result
        : (toolResult.result.trim().isNotEmpty
              ? toolResult.result
              : 'Error: ${toolResult.errorMessage ?? 'Tool execution failed'}');
    return ToolResultInfo(
      id: toolCall.id,
      name: toolCall.name,
      arguments: toolCall.arguments,
      result: resultText,
    );
  }

  ToolResultInfo _duplicateToolResult(ToolCallInfo toolCall) {
    return ToolResultInfo(
      id: toolCall.id,
      name: toolCall.name,
      arguments: toolCall.arguments,
      result: jsonEncode({
        'error':
            'This participant tool call was already executed in the current '
            'turn. Use the previous result instead of repeating the call.',
        'code': 'duplicate_participant_tool_call',
      }),
    );
  }

  Message _buildToolResultMessage(List<ToolResultInfo> toolResults) {
    final timestamp = DateTime.now();
    final budgetedToolResults = ToolResultPromptBuilder.budgetToolResults(
      toolResults,
      mode: ToolResultPromptBudgetMode.compact,
    );
    return Message(
      id: 'participant_tool_result_${timestamp.microsecondsSinceEpoch}',
      content:
          'Continue your participant turn using these application-executed '
          'tool results. Stay within the participant tool allowlist.\n\n'
          '${ToolResultPromptBuilder.buildAnswerPrompt(budgetedToolResults)}',
      role: MessageRole.user,
      timestamp: timestamp,
    );
  }

  String? _assistantContentForToolResultContext({
    required ChatCompletionResult completion,
    required String streamedContent,
  }) {
    final content = completion.content.isNotEmpty
        ? completion.content
        : streamedContent;
    final trimmed = content.trim();
    if (trimmed.isEmpty || _containsEmbeddedToolCall(trimmed)) {
      return null;
    }
    return content;
  }

  bool _containsEmbeddedToolCall(String content) {
    final normalized = content.toLowerCase();
    return normalized.contains('<tool_call') ||
        normalized.contains('<tool_use');
  }

  String _toolCallKey(ToolCallInfo toolCall) {
    return '${toolCall.name}:${jsonEncode(toolCall.arguments)}';
  }
}
