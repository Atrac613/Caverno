import 'dart:async';
import 'dart:convert';

import '../../domain/entities/chat_completion_terminal_metadata.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';

export '../../domain/entities/chat_completion_terminal_metadata.dart';

/// Result of a streaming chat completion with tool support.
final class StreamWithToolsResult {
  StreamWithToolsResult({required this.stream, required this.completion}) {
    unawaited(
      completion.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  final Stream<String> stream;
  final Future<ChatCompletionResult> completion;
}

/// Atomic result of a non-streaming or tool-aware completion.
final class ChatCompletionResult {
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

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

final class ChatCompletionStreamCancelledException implements Exception {
  const ChatCompletionStreamCancelledException();

  @override
  String toString() => 'Chat completion stream was cancelled.';
}

/// A content stream paired with metadata from that exact request.
final class StreamedChatCompletion extends Stream<String> {
  StreamedChatCompletion({required this.stream, required this.terminal});

  /// Wraps a content stream whose terminal response facts are already known.
  factory StreamedChatCompletion.fromStream(
    Stream<String> stream, {
    String? finishReason,
    TokenUsage usage = TokenUsage.zero,
  }) {
    return StreamedChatCompletion.capture(
      stream: stream,
      terminalMetadata: () => ChatCompletionTerminalMetadata(
        finishReason: finishReason,
        usage: usage,
      ),
    );
  }

  factory StreamedChatCompletion.capture({
    required Stream<String> stream,
    required FutureOr<ChatCompletionTerminalMetadata> Function()
    terminalMetadata,
    void Function(ChatCompletionTerminalMetadata metadata)? onTerminal,
  }) {
    final completer = Completer<ChatCompletionTerminalMetadata>();
    final terminal = completer.future;
    unawaited(
      terminal.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );

    Stream<String> guardedStream() async* {
      var completedNormally = false;
      try {
        await for (final chunk in stream) {
          yield chunk;
        }
        final metadata = await terminalMetadata();
        completer.complete(metadata);
        onTerminal?.call(metadata);
        completedNormally = true;
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        rethrow;
      } finally {
        if (!completedNormally && !completer.isCompleted) {
          completer.completeError(
            const ChatCompletionStreamCancelledException(),
            StackTrace.current,
          );
        }
      }
    }

    return StreamedChatCompletion(stream: guardedStream(), terminal: terminal);
  }

  final Stream<String> stream;
  final Future<ChatCompletionTerminalMetadata> terminal;

  @override
  StreamSubscription<String> listen(
    void Function(String event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// Opt-in capability for data sources that track the finish reason of their
/// most recent completion (e.g. `'stop'`, `'length'`). Read by the chat loop to
/// detect truncation at the max-token limit. Kept separate from [ChatDataSource]
/// so existing implementers are not forced to provide it.
abstract interface class FinishReasonAware {
  String? get lastFinishReason;
}

/// Opt-in capability for data sources that report which request parameters the
/// endpoint refused, after the 400-driven fallback has rewritten the request.
///
/// Anything that varies a parameter to measure its effect has to read this:
/// a sweep over temperature 0.0-0.7 against an endpoint that rejects
/// `temperature` (GPT-5 class) is otherwise the same request repeated N times,
/// reported as a clean sweep. Kept separate from [ChatDataSource] so existing
/// implementers are not forced to provide it.
abstract interface class RequestParameterFallbackAware {
  /// True once the endpoint has 400'd on `temperature`, after which every
  /// request omits it and runs at the server default.
  bool get endpointIgnoresRequestedTemperature;

  /// Reads the flag off any data source, false when it does not report one.
  ///
  /// Takes [Object] because this capability is not part of [ChatDataSource]:
  /// `is` against an unrelated type does not promote a [ChatDataSource]
  /// variable, so callers would otherwise need a cast at every site.
  static bool ignoresTemperature(Object? dataSource) =>
      dataSource is RequestParameterFallbackAware &&
      dataSource.endpointIgnoresRequestedTemperature;
}

enum StructuredOutputFormat { jsonSchema, jsonObject }

class StructuredOutputRequest {
  const StructuredOutputRequest.jsonSchema({
    required this.name,
    required this.schema,
  }) : format = StructuredOutputFormat.jsonSchema;

  const StructuredOutputRequest.jsonObject()
    : format = StructuredOutputFormat.jsonObject,
      name = '',
      schema = const <String, dynamic>{};

  final StructuredOutputFormat format;
  final String name;
  final Map<String, dynamic> schema;
}

/// Opt-in chat-completions capability for OpenAI-compatible structured output.
///
/// This stays separate from [ChatDataSource] because local and demo providers
/// do not necessarily expose the `response_format` request field.
abstract interface class StructuredOutputChatDataSource {
  Future<ChatCompletionResult> createStructuredChatCompletion({
    required List<Message> messages,
    required StructuredOutputRequest responseFormat,
    String? model,
    double? temperature,
    int? maxTokens,
  });
}

/// Opt-in capability for streaming batched tool-result follow-ups.
abstract interface class StreamingToolResultsChatDataSource {
  StreamWithToolsResult streamChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  });
}

/// Abstract interface for chat data sources.
///
/// Both [ChatRemoteDataSource] (real API) and [DemoDataSource] implement this.
abstract class ChatDataSource {
  StreamedChatCompletion streamChatCompletion({
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
