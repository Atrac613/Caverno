import 'dart:async';
import 'dart:convert' as dart_convert;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' hide MessageRole;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/content_parser.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/chat_request_prefix_stability_service.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import 'chat_datasource.dart';

export '../../domain/entities/tool_call_info.dart'
    show ToolCallInfo, ToolResultInfo;

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

/// Result of a streaming chat completion with tool support.
///
/// Contains the stream of content chunks (including `<think>` tags for
/// reasoning) and a [Future] that resolves to the accumulated tool calls
/// and finish reason once the stream is fully consumed.
class StreamWithToolsResult {
  StreamWithToolsResult({required this.stream, required this.completion});

  /// Stream of content/reasoning chunks (same format as [streamChatCompletion]).
  final Stream<String> stream;

  /// Resolves after the stream ends with the accumulated tool calls, finish
  /// reason, and any content that was only delivered as structured data
  /// (not via delta.content).
  final Future<ChatCompletionResult> completion;
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

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

class ChatRemoteDataSource implements ChatDataSource, FinishReasonAware {
  ChatRemoteDataSource({
    String? baseUrl,
    String? apiKey,
    String? reasoningEffort,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  }) : _reasoningEffort = _normalizeReasoningEffort(reasoningEffort),
       _client = OpenAIClient.withApiKey(
         apiKey ?? ApiConstants.defaultApiKey,
         baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
         httpClient: httpClient,
         streamClientFactory: streamClientFactory,
       );

  final OpenAIClient _client;
  final String? _reasoningEffort;
  static final RegExp _rawParseFailurePattern = RegExp(
    r'Failed to parse input at pos \d+:\s*(.+)$',
    dotAll: true,
  );
  static final RegExp _thoughtChannelStartPattern = RegExp(
    r'<\|channel\|?>\s*thought\b',
    caseSensitive: false,
  );
  static final RegExp _analysisChannelStartPattern = RegExp(
    r'<\|channel\|?>\s*analysis\b',
    caseSensitive: false,
  );
  static final RegExp _channelEndPattern = RegExp(r'<channel\|>');
  static const bool _logToolSchemas = bool.fromEnvironment(
    'CAVERNO_LLM_LOG_TOOL_SCHEMAS',
  );
  static const int _maxLoggedToolNames = 12;

  static bool isNativeToolStreamFormatError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('peg-native') ||
        (message.contains('native tool') && message.contains('format'));
  }

  /// Last token usage captured from a streaming or non-streaming response.
  TokenUsage lastUsage = TokenUsage.zero;

  /// Last finish reason captured from a streaming or non-streaming response.
  @override
  String? lastFinishReason;

  void _resetResponseTelemetry() {
    lastUsage = TokenUsage.zero;
    lastFinishReason = null;
  }

  void _captureStreamingFinishReason(dynamic choice) {
    final Object? finishReason = choice?.finishReason?.value;
    if (finishReason is String && finishReason.isNotEmpty) {
      lastFinishReason = finishReason;
    }
  }

  static String? _normalizeReasoningEffort(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'low' || 'medium' || 'high' => normalized,
      _ => null,
    };
  }

  ReasoningEffort? _reasoningEffortForRequest(bool includeReasoning) {
    if (!includeReasoning) {
      return null;
    }
    return switch (_reasoningEffort) {
      'low' => ReasoningEffort.low,
      'medium' => ReasoningEffort.medium,
      'high' => ReasoningEffort.high,
      _ => null,
    };
  }

  bool _shouldRetryWithoutReasoning(ApiException error) {
    return _reasoningEffort != null && error.statusCode == 400;
  }

  void _logReasoningFallback(String operation) {
    appLog(
      '[LLM] $operation rejected reasoning_effort with HTTP 400; '
      'retrying without reasoning_effort',
    );
  }

  Future<T> _createWithReasoningFallback<T>({
    required String operation,
    required Future<T> Function(bool includeReasoning) send,
  }) async {
    if (_reasoningEffort == null) {
      return send(false);
    }

    try {
      return await send(true);
    } on ApiException catch (error, stackTrace) {
      if (!_shouldRetryWithoutReasoning(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      _logReasoningFallback(operation);
      return send(false);
    }
  }

  Stream<T> _streamWithReasoningFallback<T>({
    required String operation,
    required Stream<T> Function(bool includeReasoning) send,
  }) async* {
    if (_reasoningEffort == null) {
      yield* send(false);
      return;
    }

    try {
      yield* send(true);
    } on ApiException catch (error, stackTrace) {
      if (!_shouldRetryWithoutReasoning(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      _logReasoningFallback(operation);
      yield* send(false);
    }
  }

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
    appLog(_formatToolLogSummary(tools));
    if (!_logToolSchemas) {
      return;
    }

    appLog('[LLM] === Tool Schemas ===');
    for (final tool in tools) {
      final func = tool['function'] as Map<String, dynamic>;
      appLog('[LLM]   ${func['name']}: ${func['description']}');
      appLog(
        '[LLM]     params: ${dart_convert.jsonEncode(func['parameters'])}',
      );
    }
    appLog('[LLM] === End Tool Schemas ===');
  }

  String _formatToolLogSummary(List<Map<String, dynamic>> tools) {
    final names = _toolLogNames(tools);
    if (names.isEmpty) {
      return '[LLM] Tools available: ${tools.length}';
    }
    final visibleNames = names.take(_maxLoggedToolNames).join(', ');
    final omittedCount = names.length - _maxLoggedToolNames;
    final omittedSuffix = omittedCount > 0 ? ', +$omittedCount more' : '';
    return '[LLM] Tools available: ${tools.length} '
        '($visibleNames$omittedSuffix)';
  }

  List<String> _toolLogNames(List<Map<String, dynamic>> tools) {
    return tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .map((function) => function['name'])
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);
  }

  @visibleForTesting
  String formatToolLogSummaryForTest(List<Map<String, dynamic>> tools) {
    return _formatToolLogSummary(tools);
  }

  @visibleForTesting
  String buildPromptPrefixJsonForTest({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    required int stableMessageCount,
  }) {
    return ChatRequestPrefixStabilityService.buildPromptPrefixJson(
      messages: messages,
      tools: tools,
      stableMessageCount: stableMessageCount,
    );
  }

  @visibleForTesting
  int commonLeadingPromptMessageCountForTest(
    List<Message> first,
    List<Message> second,
  ) {
    return ChatRequestPrefixStabilityService.commonLeadingPromptMessageCount(
      first,
      second,
    );
  }

  /// Build a list of [Tool] objects from the tool definition maps.
  List<Tool>? _buildTools(List<Map<String, dynamic>>? tools) {
    if (tools == null) return null;
    return tools.map((t) {
      final function = t['function'] as Map<String, dynamic>;
      return Tool.function(
        name: function['name'] as String,
        description: function['description'] as String?,
        parameters: function['parameters'] as Map<String, dynamic>?,
      );
    }).toList();
  }

  /// Get chat completion via streaming (without tools)
  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    _resetResponseTelemetry();
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
      final stream = _streamWithReasoningFallback(
        operation: 'streamChatCompletion',
        send: (includeReasoning) => _client.chat.completions.createStream(
          ChatCompletionCreateRequest(
            model: modelId,
            messages: formattedMessages,
            temperature: temperature ?? ApiConstants.defaultTemperature,
            maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
            streamOptions: const StreamOptions(includeUsage: true),
            reasoningEffort: _reasoningEffortForRequest(includeReasoning),
          ),
        ),
      );

      final responseBuffer = StringBuffer();
      var isInReasoning = false;
      await for (final event in stream) {
        final choice = event.choices?.firstOrNull;
        _captureStreamingFinishReason(choice);

        // Capture usage from the final chunk (when stream_options is set)
        if (event.usage != null) {
          lastUsage = _extractUsage(event.usage);
        }

        final delta = choice?.delta;
        if (delta == null) continue;

        // Handle reasoning_content / reasoning fields (DeepSeek, vLLM, OpenRouter)
        // Tags are batched with adjacent content to avoid intermediate
        // states where only a bare `<think>` or `</think>` is in the
        // message, which could briefly render as literal text.
        final reasoning = delta.reasoningContent ?? delta.reasoning;
        final content = delta.content;

        if (reasoning != null && reasoning.isNotEmpty) {
          if (!isInReasoning) {
            isInReasoning = true;
            responseBuffer.write('<think>$reasoning');
            yield '<think>$reasoning';
          } else {
            responseBuffer.write(reasoning);
            yield reasoning;
          }
        }

        if (content != null && content.isNotEmpty) {
          if (isInReasoning) {
            isInReasoning = false;
            responseBuffer.write('</think>$content');
            yield '</think>$content';
          } else {
            responseBuffer.write(content);
            yield content;
          }
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
      final recoveredText = _tryRecoverRawAssistantTextFromError(e);
      if (recoveredText != null) {
        appLog('[LLM] Recovered raw text response after stream parse failure');
        yield recoveredText;
        return;
      }
      appLog('[LLM] streamChatCompletion error: ${e.runtimeType}: $e');
      appLog('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Streams a chat completion while also detecting tool calls.
  ///
  /// Content and reasoning tokens are yielded through the returned stream
  /// in real-time (same format as [streamChatCompletion]). Tool call deltas
  /// are accumulated internally.  Once the stream ends, the [completion]
  /// future on the returned [StreamWithToolsResult] resolves with the
  /// accumulated tool calls and finish reason.
  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    _resetResponseTelemetry();
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

    appLog('[LLM] ========== streamChatCompletionWithTools ==========');
    appLog(
      '[LLM] model: $modelId, temperature: $temperature, maxTokens: $maxTokens',
    );
    _logMessages(messages);
    _logTools(tools);

    final accumulator = ChatStreamAccumulator();
    final completer = Completer<ChatCompletionResult>();

    // Single-subscription stream that yields content/reasoning in real-time.
    // When the stream ends, the completer resolves with accumulated tool calls.
    Stream<String> contentStream() async* {
      try {
        final stream = _streamWithReasoningFallback(
          operation: 'streamChatCompletionWithTools',
          send: (includeReasoning) => _client.chat.completions.createStream(
            ChatCompletionCreateRequest(
              model: modelId,
              messages: formattedMessages,
              temperature: temperature ?? ApiConstants.defaultTemperature,
              maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
              tools: _buildTools(tools),
              streamOptions: const StreamOptions(includeUsage: true),
              reasoningEffort: _reasoningEffortForRequest(includeReasoning),
            ),
          ),
        );

        final responseBuffer = StringBuffer();
        var isInReasoning = false;
        await for (final event in stream) {
          accumulator.add(event);
          final choice = event.choices?.firstOrNull;
          _captureStreamingFinishReason(choice);

          if (event.usage != null) {
            lastUsage = _extractUsage(event.usage);
          }

          final delta = choice?.delta;
          if (delta == null) continue;

          // Yield reasoning tokens wrapped in <think> tags.
          // Tags are batched with adjacent content to avoid intermediate
          // states where only a bare `<think>` or `</think>` is in the
          // message, which could briefly render as literal text.
          final reasoning = delta.reasoningContent ?? delta.reasoning;
          final content = delta.content;

          if (reasoning != null && reasoning.isNotEmpty) {
            if (!isInReasoning) {
              isInReasoning = true;
              responseBuffer.write('<think>$reasoning');
              yield '<think>$reasoning';
            } else {
              responseBuffer.write(reasoning);
              yield reasoning;
            }
          }

          if (content != null && content.isNotEmpty) {
            if (isInReasoning) {
              isInReasoning = false;
              responseBuffer.write('</think>$content');
              yield '</think>$content';
            } else {
              responseBuffer.write(content);
              yield content;
            }
          }
        }

        if (isInReasoning) {
          responseBuffer.write('</think>');
          yield '</think>';
        }

        appLog('[LLM] === Response (streamWithTools) ===');
        final responseText = responseBuffer.toString();
        appLog(
          '[LLM] ${responseText.length > 500 ? '${responseText.substring(0, 500)}...' : responseText}',
        );
        appLog('[LLM] finishReason: ${accumulator.finishReason?.value}');
        appLog(
          '[LLM] toolCalls: ${accumulator.toolCalls.map((t) => t.function.name).toList()}',
        );
        appLog('[LLM] ==========================================');

        // Resolve the completer after the stream ends normally.
        final toolCalls = _parseToolCalls(accumulator.toolCalls);
        final finishReason = accumulator.finishReason?.value ?? 'stop';
        lastFinishReason = finishReason;
        completer.complete(
          ChatCompletionResult(
            content: accumulator.content,
            toolCalls: toolCalls,
            finishReason: finishReason,
            usage: lastUsage,
          ),
        );
      } catch (e, stackTrace) {
        final recoveredText = _tryRecoverRawAssistantTextFromError(e);
        if (recoveredText != null) {
          appLog(
            '[LLM] Recovered raw text response after tool stream parse failure',
          );
          yield recoveredText;
          final embeddedToolCalls = _parseEmbeddedToolCalls(recoveredText);
          lastFinishReason = embeddedToolCalls == null ? 'stop' : 'tool_calls';
          completer.complete(
            ChatCompletionResult(
              content: recoveredText,
              toolCalls: embeddedToolCalls,
              finishReason: embeddedToolCalls == null ? 'stop' : 'tool_calls',
              usage: lastUsage,
            ),
          );
          return;
        }
        appLog(
          '[LLM] streamChatCompletionWithTools error: ${e.runtimeType}: $e',
        );
        appLog('[LLM] stackTrace: $stackTrace');
        if (!completer.isCompleted) {
          completer.completeError(e, stackTrace);
        }
        rethrow;
      }
    }

    return StreamWithToolsResult(
      stream: contentStream(),
      completion: completer.future,
    );
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
    _resetResponseTelemetry();
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

    ChatCompletionCreateRequest buildRequest(bool includeReasoning) {
      return ChatCompletionCreateRequest(
        model: modelId,
        messages: formattedMessages,
        temperature: temperature ?? ApiConstants.defaultTemperature,
        maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
        tools: _buildTools(tools),
        reasoningEffort: _reasoningEffortForRequest(includeReasoning),
      );
    }

    appLog('[LLM] Sending request...');
    try {
      final response = await _createWithReasoningFallback(
        operation: 'createChatCompletion',
        send: (includeReasoning) =>
            _client.chat.completions.create(buildRequest(includeReasoning)),
      );
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
        appLog(
          '[LLM] reasoning: ${reasoning.length > 200 ? '${reasoning.substring(0, 200)}...' : reasoning}',
        );
        responseContent = '<think>$reasoning</think>$responseContent';
      }

      // Parse tool calls
      final toolCalls = _parseToolCalls(message.toolCalls);
      final finishReason = choice.finishReason?.value ?? 'stop';
      lastFinishReason = finishReason;

      appLog('[LLM] ==========================================');

      return ChatCompletionResult(
        content: responseContent,
        toolCalls: toolCalls,
        finishReason: finishReason,
        usage: lastUsage = _extractUsage(response.usage),
      );
    } catch (e, stackTrace) {
      final recoveredText = _tryRecoverRawAssistantTextFromError(e);
      if (recoveredText != null) {
        appLog('[LLM] Recovered raw text response after create parse failure');
        final embeddedToolCalls = _parseEmbeddedToolCalls(recoveredText);
        lastFinishReason = embeddedToolCalls == null ? 'stop' : 'tool_calls';
        return ChatCompletionResult(
          content: recoveredText,
          toolCalls: embeddedToolCalls,
          finishReason: embeddedToolCalls == null ? 'stop' : 'tool_calls',
          usage: lastUsage,
        );
      }
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
    _resetResponseTelemetry();
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
      AssistantMessage(
        content: assistantContent ?? '',
        toolCalls: [
          ToolCall(
            id: toolCallId,
            type: 'function',
            function: FunctionCall(name: toolName, arguments: toolArguments),
          ),
        ],
      ),
    );

    // Add tool result message
    formattedMessages.add(
      ChatMessage.tool(toolCallId: toolCallId, content: toolResult),
    );

    try {
      final stream = _streamWithReasoningFallback(
        operation: 'streamWithToolResult',
        send: (includeReasoning) => _client.chat.completions.createStream(
          ChatCompletionCreateRequest(
            model: modelId,
            messages: formattedMessages,
            temperature: temperature ?? ApiConstants.defaultTemperature,
            maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
            streamOptions: const StreamOptions(includeUsage: true),
            reasoningEffort: _reasoningEffortForRequest(includeReasoning),
          ),
        ),
      );

      final responseBuffer = StringBuffer();
      var isInReasoning = false;
      await for (final event in stream) {
        final choice = event.choices?.firstOrNull;
        _captureStreamingFinishReason(choice);

        // Capture usage from the final chunk
        if (event.usage != null) {
          lastUsage = _extractUsage(event.usage);
        }

        final delta = choice?.delta;
        if (delta == null) continue;

        // Handle reasoning_content / reasoning fields (DeepSeek, vLLM, OpenRouter)
        // Tags are batched with adjacent content to avoid intermediate
        // states where only a bare `<think>` or `</think>` is in the
        // message, which could briefly render as literal text.
        final reasoning = delta.reasoningContent ?? delta.reasoning;
        final content = delta.content;

        if (reasoning != null && reasoning.isNotEmpty) {
          if (!isInReasoning) {
            isInReasoning = true;
            responseBuffer.write('<think>$reasoning');
            yield '<think>$reasoning';
          } else {
            responseBuffer.write(reasoning);
            yield reasoning;
          }
        }

        if (content != null && content.isNotEmpty) {
          if (isInReasoning) {
            isInReasoning = false;
            responseBuffer.write('</think>$content');
            yield '</think>$content';
          } else {
            responseBuffer.write(content);
            yield content;
          }
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
    } catch (e, stackTrace) {
      final recoveredText = _tryRecoverRawAssistantTextFromError(e);
      if (recoveredText != null) {
        appLog(
          '[LLM] Recovered raw text response after tool-result stream parse failure',
        );
        yield recoveredText;
        return;
      }
      appLog('[LLM] streamWithToolResult error: ${e.runtimeType}: $e');
      appLog('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
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
    return createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: toolCallId,
          name: toolName,
          arguments: toolArguments.isEmpty
              ? const <String, dynamic>{}
              : ContentParser.sanitizeToolArguments(
                  Map<String, dynamic>.from(
                    dart_convert.jsonDecode(toolArguments) as Map,
                  ),
                ),
          result: toolResult,
        ),
      ],
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    _resetResponseTelemetry();
    final formattedMessages = _formatMessages(messages, stripImages: true);
    final modelId = model ?? ApiConstants.defaultModel;

    appLog('[LLM] ========== createChatCompletionWithToolResults ==========');
    appLog('[LLM] model: $modelId, toolResults: ${toolResults.length}');
    _logMessages(messages);
    _logTools(tools);
    appLog('[LLM] assistantContent: ${assistantContent ?? "(none)"}');
    for (final toolResult in toolResults) {
      final llmToolResultContent = _formatToolResultContentForLlm(toolResult);
      appLog('[LLM] === Tool Call Info ===');
      appLog('[LLM] toolCallId: ${toolResult.id}');
      appLog('[LLM] toolName: ${toolResult.name}');
      appLog(
        '[LLM] arguments: ${dart_convert.jsonEncode(toolResult.arguments)}',
      );
      appLog('[LLM] === Tool Result ===');
      appLog(
        '[LLM] ${llmToolResultContent.length > 500 ? '${llmToolResultContent.substring(0, 500)}...' : llmToolResultContent}',
      );
      appLog('[LLM] === End Tool Result ===');
    }

    // Add assistant tool_calls message.
    formattedMessages.add(
      AssistantMessage(
        content: assistantContent ?? '',
        toolCalls: toolResults
            .map(
              (toolResult) => ToolCall(
                id: toolResult.id,
                type: 'function',
                function: FunctionCall(
                  name: toolResult.name,
                  arguments: dart_convert.jsonEncode(toolResult.arguments),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );

    // Add tool result messages.
    formattedMessages.addAll(
      toolResults.map(
        (toolResult) => ChatMessage.tool(
          toolCallId: toolResult.id,
          content: _formatToolResultContentForLlm(toolResult),
        ),
      ),
    );
    formattedMessages.addAll(_buildToolImageObservationMessages(toolResults));

    ChatCompletionCreateRequest buildRequest(bool includeReasoning) {
      return ChatCompletionCreateRequest(
        model: modelId,
        messages: formattedMessages,
        temperature: temperature ?? ApiConstants.defaultTemperature,
        maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
        tools: _buildTools(tools),
        reasoningEffort: _reasoningEffortForRequest(includeReasoning),
      );
    }

    appLog('[LLM] Sending request...');
    try {
      final response = await _createWithReasoningFallback(
        operation: 'createChatCompletionWithToolResults',
        send: (includeReasoning) =>
            _client.chat.completions.create(buildRequest(includeReasoning)),
      );
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
        appLog(
          '[LLM] reasoning: ${reasoning.length > 200 ? '${reasoning.substring(0, 200)}...' : reasoning}',
        );
        responseContent = '<think>$reasoning</think>$responseContent';
      }

      final toolCallsResult = _parseToolCalls(message.toolCalls);
      final finishReason = choice.finishReason?.value ?? 'stop';
      lastFinishReason = finishReason;

      appLog('[LLM] ==========================================');

      return ChatCompletionResult(
        content: responseContent,
        toolCalls: toolCallsResult,
        finishReason: finishReason,
        usage: lastUsage = _extractUsage(response.usage),
      );
    } catch (e, stackTrace) {
      final recoveredText = _tryRecoverRawAssistantTextFromError(e);
      if (recoveredText != null) {
        appLog(
          '[LLM] Recovered raw text response after tool-result parse failure',
        );
        final embeddedToolCalls = _parseEmbeddedToolCalls(recoveredText);
        lastFinishReason = embeddedToolCalls == null ? 'stop' : 'tool_calls';
        return ChatCompletionResult(
          content: recoveredText,
          toolCalls: embeddedToolCalls,
          finishReason: embeddedToolCalls == null ? 'stop' : 'tool_calls',
          usage: lastUsage,
        );
      }
      appLog(
        '[LLM] createChatCompletionWithToolResults error: ${e.runtimeType}: $e',
      );
      appLog('[LLM] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Parse tool calls from an assistant message into [ToolCallInfo] records.
  List<ToolCallInfo>? _parseToolCalls(List<ToolCall>? toolCalls) {
    if (toolCalls == null || toolCalls.isEmpty) return null;
    appLog('[LLM] === Tool Calls ===');
    final result = toolCalls.map((tc) {
      appLog('[LLM]   id: ${tc.id}');
      appLog('[LLM]   name: ${tc.function.name}');
      appLog('[LLM]   arguments: ${tc.function.arguments}');
      Map<String, dynamic> args = {};
      try {
        final argsStr = tc.function.arguments;
        if (argsStr.isNotEmpty) {
          args = ContentParser.sanitizeToolArguments(
            Map<String, dynamic>.from(dart_convert.jsonDecode(argsStr) as Map),
          );
        }
      } catch (e) {
        appLog('[LLM]   Failed to parse arguments: $e');
      }
      return ToolCallInfo(id: tc.id, name: tc.function.name, arguments: args);
    }).toList();
    appLog('[LLM] === End Tool Calls ===');
    return result;
  }

  /// Extract token usage from a completion response.
  TokenUsage _extractUsage(Usage? usage) {
    if (usage == null) return TokenUsage.zero;
    return TokenUsage(
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens ?? 0,
      totalTokens: usage.totalTokens,
    );
  }

  List<ChatMessage> _formatMessages(
    List<Message> messages, {
    bool stripImages = false,
  }) {
    return messages.map<ChatMessage>((m) {
      switch (m.role) {
        case MessageRole.user:
          // Use parts format (multimodal) when image is present
          // Skip images if stripImages=true
          if (m.imageBase64 != null && !stripImages) {
            final parts = <ContentPart>[];
            if (m.content.isNotEmpty) {
              parts.add(ContentPart.text(m.content));
            }
            parts.add(
              ContentPart.imageBase64(
                data: m.imageBase64!,
                mediaType: m.imageMimeType ?? 'image/jpeg',
              ),
            );
            return ChatMessage.user(parts);
          }
          // Text only (or images stripped)
          final content = m.content.isNotEmpty
              ? m.content
              : (m.imageBase64 != null ? '[image]' : '');
          return ChatMessage.user(content);
        case MessageRole.assistant:
          return ChatMessage.assistant(content: m.content);
        case MessageRole.system:
          return ChatMessage.system(m.content);
      }
    }).toList();
  }

  @visibleForTesting
  String? tryRecoverRawAssistantTextFromError(Object error) {
    return _tryRecoverRawAssistantTextFromError(error);
  }

  @visibleForTesting
  List<ToolCallInfo>? parseEmbeddedToolCallsForTest(String content) {
    return _parseEmbeddedToolCalls(content);
  }

  String? _tryRecoverRawAssistantTextFromError(Object error) {
    final rawMessage = error.toString();
    final match = _rawParseFailurePattern.firstMatch(rawMessage);
    if (match == null) return null;

    final candidate = match.group(1)?.trim();
    if (candidate == null || candidate.isEmpty) return null;
    return _normalizeRecoveredAssistantText(candidate);
  }

  @visibleForTesting
  String formatToolResultContentForLlm(ToolResultInfo toolResult) {
    return _formatToolResultContentForLlm(toolResult);
  }

  @visibleForTesting
  int countToolImageObservationMessagesForTest(
    List<ToolResultInfo> toolResults,
  ) {
    return _buildToolImageObservationMessages(toolResults).length;
  }

  String _formatToolResultContentForLlm(ToolResultInfo toolResult) {
    final decoded = _tryDecodeToolResultJson(toolResult.result);
    if (decoded == null) {
      return toolResult.result;
    }

    if (decoded['imageBase64'] is String) {
      final redacted = Map<String, dynamic>.from(decoded)
        ..['imageBase64'] = '[attached as image content]';
      return dart_convert.jsonEncode(redacted);
    }

    final interpretationLines = <String>[];
    switch (toolResult.name) {
      case 'write_file':
        if (decoded.containsKey('bytes_written')) {
          if (decoded['created'] == true) {
            interpretationLines.add(
              'Interpretation: write_file succeeded and created the target file.',
            );
          } else {
            interpretationLines.add(
              'Interpretation: write_file succeeded and updated an existing file.',
            );
            interpretationLines.add(
              'A result with "created": false means the file already existed; it is not an error.',
            );
          }
        }
      case 'edit_file':
        if (decoded['already_applied'] == true) {
          interpretationLines.add(
            'Interpretation: edit_file detected that the requested replacement was already present and left the file unchanged.',
          );
        } else if (decoded.containsKey('replacements')) {
          interpretationLines.add(
            'Interpretation: edit_file succeeded and applied the requested replacement.',
          );
        }
    }
    interpretationLines.addAll(
      ToolResultPromptBuilder.buildToolDataInterpretationLines(toolResult),
    );

    if (interpretationLines.isEmpty) {
      return toolResult.result;
    }

    return '${interpretationLines.join('\n')}\nRaw result:\n${toolResult.result}';
  }

  List<ChatMessage> _buildToolImageObservationMessages(
    List<ToolResultInfo> toolResults,
  ) {
    final messages = <ChatMessage>[];
    for (final toolResult in toolResults) {
      final decoded = _tryDecodeToolResultJson(toolResult.result);
      if (decoded == null) continue;
      final imageBase64 = decoded['imageBase64'];
      if (imageBase64 is! String || imageBase64.isEmpty) continue;

      final mimeType = decoded['imageMimeType'] as String? ?? 'image/png';
      final metadata = Map<String, dynamic>.from(decoded)
        ..remove('imageBase64');
      final text =
          'Visual observation from ${toolResult.name}. '
          'Use this screenshot and any actionProposalPolicy metadata to decide '
          'the next computer-use action. Preserve required target metadata, '
          'exact text, and public action boundaries when proposing actions. '
          'Metadata: ${dart_convert.jsonEncode(metadata)}';
      messages.add(
        ChatMessage.user([
          ContentPart.text(text),
          ContentPart.imageBase64(data: imageBase64, mediaType: mimeType),
        ]),
      );
    }
    return messages;
  }

  Map<String, dynamic>? _tryDecodeToolResultJson(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }
    try {
      final decoded = dart_convert.jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _normalizeRecoveredAssistantText(String text) {
    return text
        .replaceAll(_thoughtChannelStartPattern, '<think>')
        .replaceAll(_analysisChannelStartPattern, '<think>')
        .replaceAll(_channelEndPattern, '</think>')
        .trim();
  }

  List<ToolCallInfo>? _parseEmbeddedToolCalls(String content) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);
    if (toolCalls.isEmpty) return null;

    return toolCalls
        .map(
          (toolCall) => ToolCallInfo(
            id: toolCall.occurrenceId ?? 'raw_${toolCall.name}',
            name: toolCall.name,
            arguments: toolCall.arguments,
          ),
        )
        .toList(growable: false);
  }
}
