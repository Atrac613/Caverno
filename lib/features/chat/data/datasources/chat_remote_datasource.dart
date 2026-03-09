import 'dart:convert' as dart_convert;

import 'package:openai_dart/openai_dart.dart' hide MessageRole;

import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/message.dart';

/// Chat completion response
class ChatCompletionResult {
  ChatCompletionResult({
    required this.content,
    this.toolCalls,
    required this.finishReason,
  });

  final String content;
  final List<ToolCallInfo>? toolCalls;
  final String finishReason;

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

class ChatRemoteDataSource {
  ChatRemoteDataSource({String? baseUrl, String? apiKey})
    : _client = OpenAIClient(
        baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
        apiKey: apiKey ?? ApiConstants.defaultApiKey,
      );

  final OpenAIClient _client;

  /// Log message list
  void _logMessages(List<Message> messages) {
    print('[LLM] === Request Messages ===');
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final contentPreview = m.content.length > 200
          ? '${m.content.substring(0, 200)}...'
          : m.content;
      final hasImage = m.imageBase64 != null ? ' [has image]' : '';
      print('[LLM]   [$i] ${m.role.name}$hasImage: $contentPreview');
    }
    print('[LLM] === End Messages ===');
  }

  /// Log tool definitions
  void _logTools(List<Map<String, dynamic>>? tools) {
    if (tools == null || tools.isEmpty) return;
    print('[LLM] === Tools ===');
    for (final tool in tools) {
      final func = tool['function'] as Map<String, dynamic>;
      print('[LLM]   ${func['name']}: ${func['description']}');
      print('[LLM]     params: ${dart_convert.jsonEncode(func['parameters'])}');
    }
    print('[LLM] === End Tools ===');
  }

  /// Get chat completion via streaming (without tools)
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
        print('[LLM] Stripping images from history before sending');
      }
    }
    final formattedMessages = _formatMessages(
      messages,
      stripImages: stripImages,
    );
    final modelId = model ?? ApiConstants.defaultModel;

    print('[LLM] ========== streamChatCompletion ==========');
    print(
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
        ),
      );

      final responseBuffer = StringBuffer();
      await for (final response in stream) {
        final delta = response.choices?.firstOrNull?.delta?.content;
        if (delta != null && delta.isNotEmpty) {
          responseBuffer.write(delta);
          yield delta;
        }
      }

      print('[LLM] === Response (streaming) ===');
      final responseText = responseBuffer.toString();
      print(
        '[LLM] ${responseText.length > 500 ? '${responseText.substring(0, 500)}...' : responseText}',
      );
      print('[LLM] ========================================');
    } catch (e, stackTrace) {
      print('[LLM] streamChatCompletion error: ${e.runtimeType}: $e');
      print('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Get chat completion without streaming (with tool support)
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

    print('[LLM] ========== createChatCompletion ==========');
    print(
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

    print('[LLM] Sending request...');
    try {
      final response = await _client.createChatCompletion(request: request);
      final choice = response.choices.first;
      final message = choice.message;

      print('[LLM] === Response ===');
      print('[LLM] finishReason: ${choice.finishReason}');
      print('[LLM] content: ${message.content ?? "(null)"}');
      print('[LLM] toolCalls count: ${message.toolCalls?.length ?? 0}');

      // Parse tool calls
      List<ToolCallInfo>? toolCalls;
      if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
        print('[LLM] === Tool Calls ===');
        toolCalls = message.toolCalls!.map((tc) {
          print('[LLM]   id: ${tc.id}');
          print('[LLM]   name: ${tc.function.name}');
          print('[LLM]   arguments: ${tc.function.arguments}');
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
            print('[LLM]   Failed to parse arguments: $e');
          }

          return ToolCallInfo(
            id: tc.id,
            name: tc.function.name,
            arguments: args,
          );
        }).toList();
        print('[LLM] === End Tool Calls ===');
      }

      print('[LLM] ==========================================');

      return ChatCompletionResult(
        content: message.content ?? '',
        toolCalls: toolCalls,
        finishReason: choice.finishReason?.name ?? 'stop',
      );
    } catch (e, stackTrace) {
      print('[LLM] createChatCompletion error: ${e.runtimeType}: $e');
      print('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Get chat completion with tool result (streaming)
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

    print('[LLM] ========== streamWithToolResult ==========');
    print('[LLM] model: $modelId, toolCallId: $toolCallId');
    _logMessages(messages);
    print('[LLM] === Tool Call Info ===');
    print('[LLM] toolName: $toolName, arguments: $toolArguments');
    print('[LLM] assistantContent: ${assistantContent ?? "(none)"}');
    print('[LLM] === Tool Result ===');
    print(
      '[LLM] ${toolResult.length > 500 ? '${toolResult.substring(0, 500)}...' : toolResult}',
    );
    print('[LLM] === End Tool Result ===');

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
      ),
    );

    final responseBuffer = StringBuffer();
    await for (final response in stream) {
      final delta = response.choices?.firstOrNull?.delta?.content;
      if (delta != null && delta.isNotEmpty) {
        responseBuffer.write(delta);
        yield delta;
      }
    }

    print('[LLM] === Response (streaming) ===');
    final responseText = responseBuffer.toString();
    print(
      '[LLM] ${responseText.length > 500 ? '${responseText.substring(0, 500)}...' : responseText}',
    );
    print('[LLM] ============================================');
  }

  /// Get chat completion with tool result (non-streaming, with tool definitions)
  ///
  /// For tool loop: LLM may return additional tool calls.
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

    print('[LLM] ========== createChatCompletionWithToolResult ==========');
    print('[LLM] model: $modelId, toolCallId: $toolCallId');
    _logMessages(messages);
    _logTools(tools);
    print('[LLM] === Tool Call Info ===');
    print('[LLM] toolName: $toolName, arguments: $toolArguments');
    print('[LLM] assistantContent: ${assistantContent ?? "(none)"}');
    print('[LLM] === Tool Result ===');
    print(
      '[LLM] ${toolResult.length > 500 ? '${toolResult.substring(0, 500)}...' : toolResult}',
    );
    print('[LLM] === End Tool Result ===');

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

    print('[LLM] Sending request...');
    try {
      final response = await _client.createChatCompletion(request: request);
      final choice = response.choices.first;
      final message = choice.message;

      print('[LLM] === Response ===');
      print('[LLM] finishReason: ${choice.finishReason}');
      print('[LLM] content: ${message.content ?? "(null)"}');
      print('[LLM] toolCalls count: ${message.toolCalls?.length ?? 0}');

      List<ToolCallInfo>? toolCallsResult;
      if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
        print('[LLM] === Tool Calls ===');
        toolCallsResult = message.toolCalls!.map((tc) {
          print('[LLM]   id: ${tc.id}');
          print('[LLM]   name: ${tc.function.name}');
          print('[LLM]   arguments: ${tc.function.arguments}');
          Map<String, dynamic> args = {};
          try {
            final argsStr = tc.function.arguments;
            if (argsStr.isNotEmpty) {
              args = Map<String, dynamic>.from(
                dart_convert.jsonDecode(argsStr) as Map,
              );
            }
          } catch (e) {
            print('[LLM]   Failed to parse arguments: $e');
          }
          return ToolCallInfo(
            id: tc.id,
            name: tc.function.name,
            arguments: args,
          );
        }).toList();
        print('[LLM] === End Tool Calls ===');
      }

      print('[LLM] ==========================================');

      return ChatCompletionResult(
        content: message.content ?? '',
        toolCalls: toolCallsResult,
        finishReason: choice.finishReason?.name ?? 'stop',
      );
    } catch (e, stackTrace) {
      print(
        '[LLM] createChatCompletionWithToolResult error: ${e.runtimeType}: $e',
      );
      print('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
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
