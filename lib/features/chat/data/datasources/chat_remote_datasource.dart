import 'dart:convert' as dart_convert;

import 'package:openai_dart/openai_dart.dart' hide MessageRole;
import '../../../../core/utils/logger.dart';

import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/message.dart';
import 'chat_datasource.dart';

/// Token usage statistics from a completion response.
class TokenUsage {
  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  static const zero = TokenUsage();
}

/// Chat completion response
class ChatCompletionResult {
  ChatCompletionResult({
    required this.content,
    this.toolCalls,
    required this.finishReason,
    this.usage = TokenUsage.zero,
  });

  final String content;
  final List<ToolCallInfo>? toolCalls;
  final String finishReason;
  final TokenUsage usage;

  bool get hasToolCalls =>
      toolCalls != null &&
      toolCalls!.isNotEmpty &&
      (finishReason == 'tool_calls' || finishReason == 'toolCalls');
}

/// Tool call information
class ToolCallInfo {
  ToolCallInfo({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class ChatRemoteDataSource implements ChatDataSource {
  ChatRemoteDataSource({String? baseUrl, String? apiKey})
    : _client = OpenAIClient(
        baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
        apiKey: apiKey ?? ApiConstants.defaultApiKey,
      );

  final OpenAIClient _client;

  /// Last token usage captured from a streaming or non-streaming response.
  TokenUsage lastUsage = TokenUsage.zero;

  /// Log message list
  void _logMessages(List<Message> messages) {
    appLog('[LLM] === Request Messages ===');
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final contentPreview = m.content.length > 200
          ? '${m.content.substring(0, 200)}...'
          : m.content;
      final hasImage = m.imageBase64 != null ? ' [has image]' : '';
      appLog('[LLM]   [$i] ${m.role.name}$hasImage: $contentPreview');
    }
    appLog('[LLM] === End Messages ===');
  }

  /// Log tool definitions
  void _logTools(List<Map<String, dynamic>>? tools) {
    if (tools == null || tools.isEmpty) return;
    appLog('[LLM] === Tools ===');
    for (final tool in tools) {
      final func = tool['function'] as Map<String, dynamic>;
      appLog('[LLM]   ${func['name']}: ${func['description']}');
      appLog('[LLM]     params: ${dart_convert.jsonEncode(func['parameters'])}');
    }
    appLog('[LLM] === End Tools ===');
  }

  /// Get chat completion via streaming (without tools)
  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    // Strip images from history if the latest user message has no image,
    // allowing conversation to continue on non-Vision servers
    final lastUserMessage = messages.lastWhere(
      (m) => m.role == MessageRole.user,
      orElse: () => messages.last,
    );
    final stripImages = lastUserMessage.imageBase64 == null;
    if (stripImages) {
      final hasHistoryImages = messages.any((m) => m.imageBase64 != null);
      if (hasHistoryImages) {
        appLog('[LLM] Stripping images from history before sending');
      }
    }
    final formattedMessages = _formatMessages(
      messages,
      stripImages: stripImages,
    );
    final modelId = model ?? ApiConstants.defaultModel;

    appLog('[LLM] ========== streamChatCompletion ==========');
    appLog(
      '[LLM] model: $modelId, temperature: $temperature, maxTokens: $maxTokens',
    );
    _logMessages(messages);

    try {
      final stream = _client.createChatCompletionStream(
        request: CreateChatCompletionRequest(
          model: ChatCompletionModel.modelId(modelId),
          messages: formattedMessages,
          temperature: temperature ?? ApiConstants.defaultTemperature,
          maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
          streamOptions: ChatCompletionStreamOptions(includeUsage: true),
        ),
      );

      final responseBuffer = StringBuffer();
      var isInReasoning = false;
      await for (final response in stream) {
        // Capture usage from the final chunk (when stream_options is set)
        if (response.usage != null) {
          lastUsage = _extractUsage(response.usage);
        }

        final delta = response.choices?.firstOrNull?.delta;
        if (delta == null) continue;

        // Handle reasoning_content / reasoning fields (DeepSeek, vLLM, OpenRouter)
        final reasoning = delta.reasoningContent ?? delta.reasoning;
        if (reasoning != null && reasoning.isNotEmpty) {
          if (!isInReasoning) {
            isInReasoning = true;
            responseBuffer.write('<think>');
            yield '<think>';
          }
          responseBuffer.write(reasoning);
          yield reasoning;
        }

        final content = delta.content;
        if (content != null && content.isNotEmpty) {
          if (isInReasoning) {
            isInReasoning = false;
            responseBuffer.write('</think>');
            yield '</think>';
          }
          responseBuffer.write(content);
          yield content;
        }
      }
      // Close unclosed reasoning tag at end of stream
      if (isInReasoning) {
        responseBuffer.write('</think>');
        yield '</think>';
      }

      appLog('[LLM] === Response (streaming) ===');
      final responseText = responseBuffer.toString();
      appLog(
        '[LLM] ${responseText.length > 500 ? '${responseText.substring(0, 500)}...' : responseText}',
      );
      appLog('[LLM] ========================================');
    } catch (e, stackTrace) {
      appLog('[LLM] streamChatCompletion error: ${e.runtimeType}: $e');
      appLog('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Get chat completion without streaming (with tool support)
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    // Strip images from history if the latest user message has no image
    final lastUserMessage = messages.lastWhere(
      (m) => m.role == MessageRole.user,
      orElse: () => messages.last,
    );
    final stripImages = lastUserMessage.imageBase64 == null;
    final formattedMessages = _formatMessages(
      messages,
      stripImages: stripImages,
    );
    final modelId = model ?? ApiConstants.defaultModel;

    appLog('[LLM] ========== createChatCompletion ==========');
    appLog(
      '[LLM] model: $modelId, temperature: $temperature, maxTokens: $maxTokens',
    );
    _logMessages(messages);
    _logTools(tools);

    final request = CreateChatCompletionRequest(
      model: ChatCompletionModel.modelId(modelId),
      messages: formattedMessages,
      temperature: temperature ?? ApiConstants.defaultTemperature,
      maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
      tools: tools?.map((t) {
        final function = t['function'] as Map<String, dynamic>;
        return ChatCompletionTool(
          type: ChatCompletionToolType.function,
          function: FunctionObject(
            name: function['name'] as String,
            description: function['description'] as String?,
            parameters: function['parameters'] as Map<String, dynamic>?,
          ),
        );
      }).toList(),
    );

    appLog('[LLM] Sending request...');
    try {
      final response = await _client.createChatCompletion(request: request);
      final choice = response.choices.first;
      final message = choice.message;

      appLog('[LLM] === Response ===');
      appLog('[LLM] finishReason: ${choice.finishReason}');
      appLog('[LLM] content: ${message.content ?? "(null)"}');
      appLog('[LLM] toolCalls count: ${message.toolCalls?.length ?? 0}');

      // Prepend reasoning content as <think> block if present
      final reasoning = message.reasoningContent ?? message.reasoning;
      var responseContent = message.content ?? '';
      if (reasoning != null && reasoning.isNotEmpty) {
        appLog('[LLM] reasoning: ${reasoning.length > 200 ? '${reasoning.substring(0, 200)}...' : reasoning}');
        responseContent = '<think>$reasoning</think>$responseContent';
      }

      // Parse tool calls
      List<ToolCallInfo>? toolCalls;
      if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
        appLog('[LLM] === Tool Calls ===');
        toolCalls = message.toolCalls!.map((tc) {
          appLog('[LLM]   id: ${tc.id}');
          appLog('[LLM]   name: ${tc.function.name}');
          appLog('[LLM]   arguments: ${tc.function.arguments}');
          // Parse arguments
          Map<String, dynamic> args = {};
          try {
            final argsStr = tc.function.arguments;
            if (argsStr.isNotEmpty) {
              args = Map<String, dynamic>.from(
                dart_convert.jsonDecode(argsStr) as Map,
              );
            }
          } catch (e) {
            appLog('[LLM]   Failed to parse arguments: $e');
          }

          return ToolCallInfo(
            id: tc.id,
            name: tc.function.name,
            arguments: args,
          );
        }).toList();
        appLog('[LLM] === End Tool Calls ===');
      }

      appLog('[LLM] ==========================================');

      return ChatCompletionResult(
        content: responseContent,
        toolCalls: toolCalls,
        finishReason: choice.finishReason?.name ?? 'stop',
        usage: lastUsage = _extractUsage(response.usage),
      );
    } catch (e, stackTrace) {
      appLog('[LLM] createChatCompletion error: ${e.runtimeType}: $e');
      appLog('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Get chat completion with tool result (streaming)
  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    // Strip images when sending tool results (images were already processed at tool call time)
    final formattedMessages = _formatMessages(messages, stripImages: true);
    final modelId = model ?? ApiConstants.defaultModel;

    appLog('[LLM] ========== streamWithToolResult ==========');
    appLog('[LLM] model: $modelId, toolCallId: $toolCallId');
    _logMessages(messages);
    appLog('[LLM] === Tool Call Info ===');
    appLog('[LLM] toolName: $toolName, arguments: $toolArguments');
    appLog('[LLM] assistantContent: ${assistantContent ?? "(none)"}');
    appLog('[LLM] === Tool Result ===');
    appLog(
      '[LLM] ${toolResult.length > 500 ? '${toolResult.substring(0, 500)}...' : toolResult}',
    );
    appLog('[LLM] === End Tool Result ===');

    // Add assistant tool_calls message (required by OpenAI API)
    // mlx-lm.server requires content, so use empty string if null
    formattedMessages.add(
      ChatCompletionMessage.assistant(
        content: assistantContent ?? '',
        toolCalls: [
          ChatCompletionMessageToolCall(
            id: toolCallId,
            type: ChatCompletionMessageToolCallType.function,
            function: ChatCompletionMessageFunctionCall(
              name: toolName,
              arguments: toolArguments,
            ),
          ),
        ],
      ),
    );

    // Add tool result message
    formattedMessages.add(
      ChatCompletionMessage.tool(toolCallId: toolCallId, content: toolResult),
    );

    final stream = _client.createChatCompletionStream(
      request: CreateChatCompletionRequest(
        model: ChatCompletionModel.modelId(modelId),
        messages: formattedMessages,
        temperature: temperature ?? ApiConstants.defaultTemperature,
        maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
        streamOptions: ChatCompletionStreamOptions(includeUsage: true),
      ),
    );

    final responseBuffer = StringBuffer();
    var isInReasoning = false;
    await for (final response in stream) {
      // Capture usage from the final chunk
      if (response.usage != null) {
        lastUsage = _extractUsage(response.usage);
      }

      final delta = response.choices?.firstOrNull?.delta;
      if (delta == null) continue;

      // Handle reasoning_content / reasoning fields (DeepSeek, vLLM, OpenRouter)
      final reasoning = delta.reasoningContent ?? delta.reasoning;
      if (reasoning != null && reasoning.isNotEmpty) {
        if (!isInReasoning) {
          isInReasoning = true;
          responseBuffer.write('<think>');
          yield '<think>';
        }
        responseBuffer.write(reasoning);
        yield reasoning;
      }

      final content = delta.content;
      if (content != null && content.isNotEmpty) {
        if (isInReasoning) {
          isInReasoning = false;
          responseBuffer.write('</think>');
          yield '</think>';
        }
        responseBuffer.write(content);
        yield content;
      }
    }
    // Close unclosed reasoning tag at end of stream
    if (isInReasoning) {
      responseBuffer.write('</think>');
      yield '</think>';
    }

    appLog('[LLM] === Response (streaming) ===');
    final responseText = responseBuffer.toString();
    appLog(
      '[LLM] ${responseText.length > 500 ? '${responseText.substring(0, 500)}...' : responseText}',
    );
    appLog('[LLM] ============================================');
  }

  /// Get chat completion with tool result (non-streaming, with tool definitions)
  ///
  /// For tool loop: LLM may return additional tool calls.
  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final formattedMessages = _formatMessages(messages, stripImages: true);
    final modelId = model ?? ApiConstants.defaultModel;

    appLog('[LLM] ========== createChatCompletionWithToolResult ==========');
    appLog('[LLM] model: $modelId, toolCallId: $toolCallId');
    _logMessages(messages);
    _logTools(tools);
    appLog('[LLM] === Tool Call Info ===');
    appLog('[LLM] toolName: $toolName, arguments: $toolArguments');
    appLog('[LLM] assistantContent: ${assistantContent ?? "(none)"}');
    appLog('[LLM] === Tool Result ===');
    appLog(
      '[LLM] ${toolResult.length > 500 ? '${toolResult.substring(0, 500)}...' : toolResult}',
    );
    appLog('[LLM] === End Tool Result ===');

    // Add assistant tool_calls message
    formattedMessages.add(
      ChatCompletionMessage.assistant(
        content: assistantContent ?? '',
        toolCalls: [
          ChatCompletionMessageToolCall(
            id: toolCallId,
            type: ChatCompletionMessageToolCallType.function,
            function: ChatCompletionMessageFunctionCall(
              name: toolName,
              arguments: toolArguments,
            ),
          ),
        ],
      ),
    );

    // Add tool result message
    formattedMessages.add(
      ChatCompletionMessage.tool(toolCallId: toolCallId, content: toolResult),
    );

    final request = CreateChatCompletionRequest(
      model: ChatCompletionModel.modelId(modelId),
      messages: formattedMessages,
      temperature: temperature ?? ApiConstants.defaultTemperature,
      maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
      tools: tools?.map((t) {
        final function = t['function'] as Map<String, dynamic>;
        return ChatCompletionTool(
          type: ChatCompletionToolType.function,
          function: FunctionObject(
            name: function['name'] as String,
            description: function['description'] as String?,
            parameters: function['parameters'] as Map<String, dynamic>?,
          ),
        );
      }).toList(),
    );

    appLog('[LLM] Sending request...');
    try {
      final response = await _client.createChatCompletion(request: request);
      final choice = response.choices.first;
      final message = choice.message;

      appLog('[LLM] === Response ===');
      appLog('[LLM] finishReason: ${choice.finishReason}');
      appLog('[LLM] content: ${message.content ?? "(null)"}');
      appLog('[LLM] toolCalls count: ${message.toolCalls?.length ?? 0}');

      // Prepend reasoning content as <think> block if present
      final reasoning = message.reasoningContent ?? message.reasoning;
      var responseContent = message.content ?? '';
      if (reasoning != null && reasoning.isNotEmpty) {
        appLog('[LLM] reasoning: ${reasoning.length > 200 ? '${reasoning.substring(0, 200)}...' : reasoning}');
        responseContent = '<think>$reasoning</think>$responseContent';
      }

      List<ToolCallInfo>? toolCallsResult;
      if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
        appLog('[LLM] === Tool Calls ===');
        toolCallsResult = message.toolCalls!.map((tc) {
          appLog('[LLM]   id: ${tc.id}');
          appLog('[LLM]   name: ${tc.function.name}');
          appLog('[LLM]   arguments: ${tc.function.arguments}');
          Map<String, dynamic> args = {};
          try {
            final argsStr = tc.function.arguments;
            if (argsStr.isNotEmpty) {
              args = Map<String, dynamic>.from(
                dart_convert.jsonDecode(argsStr) as Map,
              );
            }
          } catch (e) {
            appLog('[LLM]   Failed to parse arguments: $e');
          }
          return ToolCallInfo(
            id: tc.id,
            name: tc.function.name,
            arguments: args,
          );
        }).toList();
        appLog('[LLM] === End Tool Calls ===');
      }

      appLog('[LLM] ==========================================');

      return ChatCompletionResult(
        content: responseContent,
        toolCalls: toolCallsResult,
        finishReason: choice.finishReason?.name ?? 'stop',
        usage: lastUsage = _extractUsage(response.usage),
      );
    } catch (e, stackTrace) {
      appLog(
        '[LLM] createChatCompletionWithToolResult error: ${e.runtimeType}: $e',
      );
      appLog('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Extract token usage from a completion response.
  TokenUsage _extractUsage(CompletionUsage? usage) {
    if (usage == null) return TokenUsage.zero;
    return TokenUsage(
      promptTokens: usage.promptTokens ?? 0,
      completionTokens: usage.completionTokens ?? 0,
      totalTokens: usage.totalTokens ?? 0,
    );
  }

  List<ChatCompletionMessage> _formatMessages(
    List<Message> messages, {
    bool stripImages = false,
  }) {
    return messages.map((m) {
      switch (m.role) {
        case MessageRole.user:
          // Use parts format (multimodal) when image is present
          // Skip images if stripImages=true
          if (m.imageBase64 != null && !stripImages) {
            final parts = <ChatCompletionMessageContentPart>[];
            if (m.content.isNotEmpty) {
              parts.add(ChatCompletionMessageContentPart.text(text: m.content));
            }
            parts.add(
              ChatCompletionMessageContentPart.image(
                imageUrl: ChatCompletionMessageImageUrl(
                  url:
                      'data:${m.imageMimeType ?? 'image/jpeg'};base64,${m.imageBase64}',
                ),
              ),
            );
            return ChatCompletionMessage.user(
              content: ChatCompletionUserMessageContent.parts(parts),
            );
          }
          // Text only (or images stripped)
          final content = m.content.isNotEmpty
              ? m.content
              : (m.imageBase64 != null ? '[image]' : '');
          return ChatCompletionMessage.user(
            content: ChatCompletionUserMessageContent.string(content),
          );
        case MessageRole.assistant:
          return ChatCompletionMessage.assistant(content: m.content);
        case MessageRole.system:
          return ChatCompletionMessage.system(content: m.content);
      }
    }).toList();
  }
}
