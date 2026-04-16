import 'dart:convert';

import '../../domain/entities/message.dart';
import 'chat_remote_datasource.dart';

/// Abstract interface for chat data sources.
///
/// Both [ChatRemoteDataSource] (real API) and [DemoDataSource] implement this.
abstract class ChatDataSource {
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  });

  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  });

  /// Streams a chat completion while also detecting tool calls.
  ///
  /// Returns a [StreamWithToolsResult] containing a content stream and a
  /// [Future] that resolves with accumulated tool calls once streaming ends.
  /// The default implementation falls back to [createChatCompletion].
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    // Default: non-streaming fallback for data sources that don't support it.
    final future = createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: future,
    );
  }

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
  });

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
  });

  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if (toolResults.length != 1) {
      throw UnimplementedError(
        'Batch tool results are not supported by this data source.',
      );
    }

    final toolResult = toolResults.single;
    return createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolResult.id,
      toolName: toolResult.name,
      toolArguments: jsonEncode(toolResult.arguments),
      toolResult: toolResult.result,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}
