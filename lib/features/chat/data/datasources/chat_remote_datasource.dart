import 'dart:async';
import 'dart:convert' as dart_convert;

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' hide MessageRole;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/model_usage_sink.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/chat_request_prefix_stability_service.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import 'chat_completion_request_fallback.dart';
import 'chat_completion_response_normalizer.dart';
import 'chat_datasource.dart';
import 'chat_request_logger.dart';
import 'chat_response_telemetry.dart';

export '../../domain/entities/chat_completion_terminal_metadata.dart';
export '../../domain/entities/tool_call_info.dart'
    show ToolCallInfo, ToolResultInfo;
export 'chat_datasource.dart'
    show
        ChatCompletionResult,
        ChatCompletionStreamCancelledException,
        StreamWithToolsResult,
        StreamedChatCompletion;

class ChatRemoteDataSource
    implements
        ChatDataSource,
        FinishReasonAware,
        StructuredOutputChatDataSource {
  ChatRemoteDataSource({
    String? baseUrl,
    String? apiKey,
    String? reasoningEffort,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
    ModelUsageSink? usageSink,
    String endpointId = '',
    String? Function()? usageLabelResolver,
    this.defaultTopP,
  }) : _requestFallback = ChatCompletionRequestFallback(reasoningEffort),
       _telemetry = ChatResponseTelemetry(
         usageSink: usageSink,
         endpointId: endpointId,
         labelResolver: usageLabelResolver,
       ),
       _client = OpenAIClient.withApiKey(
         apiKey ?? ApiConstants.defaultApiKey,
         baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
         defaultHeaders: ApiConstants.userAgentHeaders,
         httpClient: httpClient,
         streamClientFactory: streamClientFactory,
       );

  final OpenAIClient _client;
  final ChatCompletionRequestFallback _requestFallback;
  final ChatResponseTelemetry _telemetry;
  final double? defaultTopP;

  static const _responseNormalizer = ChatCompletionResponseNormalizer();
  static const _logger = ChatRequestLogger();

  static bool isNativeToolStreamFormatError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('peg-native') ||
        (message.contains('native tool') && message.contains('format'));
  }

  TokenUsage get lastUsage => _telemetry.lastUsage;
  set lastUsage(TokenUsage usage) => _telemetry.lastUsage = usage;

  @override
  String? get lastFinishReason => _telemetry.lastFinishReason;
  set lastFinishReason(String? reason) => _telemetry.lastFinishReason = reason;

  void _resetResponseTelemetry() => _telemetry.reset();

  String? _streamingFinishReason(dynamic choice) =>
      _telemetry.streamingFinishReason(choice);

  Future<T> _createWithReasoningFallback<T>({
    required String operation,
    required Future<T> Function(bool includeReasoning) send,
  }) => _requestFallback.create(operation: operation, send: send);

  /// Streaming counterpart of [_createWithReasoningFallback].
  ///
  /// Events are re-emitted with `await for` rather than `yield*` because errors
  /// from a `yield*`-ed stream are forwarded straight to the consumer and never
  /// enter this function's `try`, which would leave the retry unreachable.
  ///
  /// A retry only happens while the attempt has emitted nothing, so a rejected
  /// request (which fails before the first event) is recovered without any risk
  /// of replaying content the caller already received.
  Stream<T> _streamWithReasoningFallback<T>({
    required String operation,
    required Stream<T> Function(bool includeReasoning) send,
  }) => _requestFallback.stream(operation: operation, send: send);

  @visibleForTesting
  String formatToolLogSummaryForTest(List<Map<String, dynamic>> tools) {
    return _logger.formatToolLogSummary(tools);
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
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    var usage = TokenUsage.zero;
    String? finishReason;
    final modelId = model ?? ApiConstants.defaultModel;
    final timer = Stopwatch();
    // Captured here, not at the terminal: the stream body below runs on first
    // listen, by which point the caller's zone is gone.
    final attribution = _telemetry.captureAttribution();

    Stream<String> contentStream() async* {
      timer.start();
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

      appLog('[LLM] ========== streamChatCompletion ==========');
      appLog(
        '[LLM] model: $modelId, temperature: $temperature, maxTokens: $maxTokens',
      );
      _logger.logMessages(messages);

      try {
        final stream = _streamWithReasoningFallback(
          operation: 'streamChatCompletion',
          send: (includeReasoning) => _client.chat.completions.createStream(
            ChatCompletionCreateRequest(
              model: modelId,
              messages: formattedMessages,
              temperature: _requestFallback.temperatureForRequest(temperature),
              topP: defaultTopP,
              maxTokens: _requestFallback.maxTokensForRequest(maxTokens),
              maxCompletionTokens: _requestFallback
                  .maxCompletionTokensForRequest(maxTokens),
              streamOptions: const StreamOptions(includeUsage: true),
              reasoningEffort: _requestFallback.reasoningEffortForRequest(
                includeReasoning,
              ),
            ),
          ),
        );

        final responseBuffer = StringBuffer();
        var isInReasoning = false;
        await for (final event in stream) {
          final choice = event.choices?.firstOrNull;
          finishReason = _streamingFinishReason(choice) ?? finishReason;

          // Capture usage from the final chunk (when stream_options is set)
          if (event.usage != null) {
            usage = ChatResponseTelemetry.extractUsage(event.usage);
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
        final recoveredText = _responseNormalizer.recoverRawAssistantText(e);
        if (recoveredText != null) {
          appLog(
            '[LLM] Recovered raw text response after stream parse failure',
          );
          yield recoveredText;
          return;
        }
        appLog('[LLM] streamChatCompletion error: ${e.runtimeType}: $e');
        appLog('[LLM] stackTrace: $stackTrace');
        _telemetry.publishFailure(
          modelId: modelId,
          timer: timer,
          attribution: attribution,
        );
        rethrow;
      }
    }

    return StreamedChatCompletion.capture(
      stream: contentStream(),
      terminalMetadata: () => ChatCompletionTerminalMetadata(
        finishReason: finishReason,
        usage: usage,
      ),
      onTerminal: (metadata) => _telemetry.publishRequest(
        modelId: modelId,
        attribution: attribution,
        metadata: metadata,
        timer: timer,
      ),
    );
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
    var usage = TokenUsage.zero;
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
    _logger.logMessages(messages);
    _logger.logTools(tools);

    final accumulator = ChatStreamAccumulator();
    final completer = Completer<ChatCompletionResult>();
    final timer = Stopwatch();
    final attribution = _telemetry.captureAttribution();

    // Single-subscription stream that yields content/reasoning in real-time.
    // When the stream ends, the completer resolves with accumulated tool calls.
    Stream<String> contentStream() async* {
      timer.start();
      try {
        final stream = _streamWithReasoningFallback(
          operation: 'streamChatCompletionWithTools',
          send: (includeReasoning) => _client.chat.completions.createStream(
            ChatCompletionCreateRequest(
              model: modelId,
              messages: formattedMessages,
              temperature: _requestFallback.temperatureForRequest(temperature),
              topP: defaultTopP,
              maxTokens: _requestFallback.maxTokensForRequest(maxTokens),
              maxCompletionTokens: _requestFallback
                  .maxCompletionTokensForRequest(maxTokens),
              tools: _buildTools(tools),
              streamOptions: const StreamOptions(includeUsage: true),
              reasoningEffort: _requestFallback.reasoningEffortForRequest(
                includeReasoning,
              ),
            ),
          ),
        );

        final responseBuffer = StringBuffer();
        var isInReasoning = false;
        await for (final event in stream) {
          accumulator.add(event);
          final choice = event.choices?.firstOrNull;

          if (event.usage != null) {
            usage = ChatResponseTelemetry.extractUsage(event.usage);
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
        _logger.logNativeToolCalls(accumulator.toolCalls);
        final toolCalls = _responseNormalizer.parseNativeToolCalls(
          accumulator.toolCalls,
          onArgumentError: _logger.logNativeToolArgumentError,
        );
        final finishReason = accumulator.finishReason?.value ?? 'stop';
        final completion = ChatCompletionResult(
          content: accumulator.content,
          toolCalls: toolCalls,
          finishReason: finishReason,
          usage: usage,
        );
        completer.complete(completion);
        _telemetry.publishRequest(
          modelId: modelId,
          attribution: attribution,
          metadata: ChatCompletionTerminalMetadata(
            finishReason: finishReason,
            usage: usage,
          ),
          timer: timer,
        );
      } catch (e, stackTrace) {
        final recovered = _responseNormalizer.recoverFromParseFailure(e);
        if (recovered != null) {
          appLog(
            '[LLM] Recovered raw text response after tool stream parse failure',
          );
          yield recovered.content;
          final completion = ChatCompletionResult(
            content: recovered.content,
            toolCalls: recovered.toolCalls,
            finishReason: recovered.finishReason,
            usage: usage,
          );
          completer.complete(completion);
          _telemetry.publishRequest(
            modelId: modelId,
            attribution: attribution,
            metadata: ChatCompletionTerminalMetadata(
              finishReason: recovered.finishReason,
              usage: usage,
            ),
            timer: timer,
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
        _telemetry.publishFailure(
          modelId: modelId,
          timer: timer,
          attribution: attribution,
        );
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
  }) => _createChatCompletion(
    messages: messages,
    tools: tools,
    model: model,
    temperature: temperature,
    maxTokens: maxTokens,
  );

  @override
  Future<ChatCompletionResult> createStructuredChatCompletion({
    required List<Message> messages,
    required StructuredOutputRequest responseFormat,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => _createChatCompletion(
    messages: messages,
    model: model,
    temperature: temperature,
    maxTokens: maxTokens,
    responseFormat: switch (responseFormat.format) {
      StructuredOutputFormat.jsonSchema => ResponseFormat.jsonSchema(
        name: responseFormat.name,
        schema: responseFormat.schema,
      ),
      StructuredOutputFormat.jsonObject => ResponseFormat.jsonObject(),
    },
  );

  Future<ChatCompletionResult> _createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
    ResponseFormat? responseFormat,
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

    final timer = Stopwatch()..start();
    final attribution = _telemetry.captureAttribution();

    appLog('[LLM] ========== createChatCompletion ==========');
    appLog(
      '[LLM] model: $modelId, temperature: $temperature, maxTokens: $maxTokens',
    );
    _logger.logMessages(messages);
    _logger.logTools(tools);

    ChatCompletionCreateRequest buildRequest(bool includeReasoning) {
      return ChatCompletionCreateRequest(
        model: modelId,
        messages: formattedMessages,
        temperature: _requestFallback.temperatureForRequest(temperature),
        topP: defaultTopP,
        maxTokens: _requestFallback.maxTokensForRequest(maxTokens),
        maxCompletionTokens: _requestFallback.maxCompletionTokensForRequest(
          maxTokens,
        ),
        tools: _buildTools(tools),
        responseFormat: responseFormat,
        reasoningEffort: _requestFallback.reasoningEffortForRequest(
          includeReasoning,
        ),
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

      final reasoning = message.reasoningContent ?? message.reasoning;
      if (reasoning != null && reasoning.isNotEmpty) {
        appLog(
          '[LLM] reasoning: ${reasoning.length > 200 ? '${reasoning.substring(0, 200)}...' : reasoning}',
        );
      }
      _logger.logNativeToolCalls(message.toolCalls);
      final normalized = _responseNormalizer.normalize(
        content: message.content,
        reasoning: reasoning,
        nativeToolCalls: message.toolCalls,
        finishReason: choice.finishReason?.value,
        advertisedTools: tools,
        onNativeArgumentError: _logger.logNativeToolArgumentError,
      );
      appLog('[LLM] ==========================================');

      final usage = ChatResponseTelemetry.extractUsage(response.usage);
      _telemetry.publishRequest(
        modelId: modelId,
        attribution: attribution,
        metadata: ChatCompletionTerminalMetadata(
          finishReason: normalized.finishReason,
          usage: usage,
        ),
        timer: timer,
      );
      return ChatCompletionResult(
        content: normalized.content,
        toolCalls: normalized.toolCalls,
        finishReason: normalized.finishReason,
        usage: usage,
      );
    } catch (e, stackTrace) {
      final recovered = _responseNormalizer.recoverFromParseFailure(e);
      if (recovered != null) {
        appLog('[LLM] Recovered raw text response after create parse failure');
        _telemetry.publishRequest(
          modelId: modelId,
          attribution: attribution,
          metadata: ChatCompletionTerminalMetadata(
            finishReason: recovered.finishReason,
            usage: lastUsage,
          ),
          timer: timer,
        );
        return ChatCompletionResult(
          content: recovered.content,
          toolCalls: recovered.toolCalls,
          finishReason: recovered.finishReason,
          usage: lastUsage,
        );
      }
      appLog('[LLM] createChatCompletion error: ${e.runtimeType}: $e');
      appLog('[LLM] stackTrace: $stackTrace');
      _telemetry.publishFailure(
        modelId: modelId,
        timer: timer,
        attribution: attribution,
      );
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
    _logger.logMessages(messages);
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

    final timer = Stopwatch()..start();
    final attribution = _telemetry.captureAttribution();
    try {
      final stream = _streamWithReasoningFallback(
        operation: 'streamWithToolResult',
        send: (includeReasoning) => _client.chat.completions.createStream(
          ChatCompletionCreateRequest(
            model: modelId,
            messages: formattedMessages,
            temperature: _requestFallback.temperatureForRequest(temperature),
            topP: defaultTopP,
            maxTokens: _requestFallback.maxTokensForRequest(maxTokens),
            maxCompletionTokens: _requestFallback.maxCompletionTokensForRequest(
              maxTokens,
            ),
            streamOptions: const StreamOptions(includeUsage: true),
            reasoningEffort: _requestFallback.reasoningEffortForRequest(
              includeReasoning,
            ),
          ),
        ),
      );

      final responseBuffer = StringBuffer();
      var isInReasoning = false;
      await for (final event in stream) {
        final choice = event.choices?.firstOrNull;
        lastFinishReason = _streamingFinishReason(choice) ?? lastFinishReason;

        // Capture usage from the final chunk
        if (event.usage != null) {
          lastUsage = ChatResponseTelemetry.extractUsage(event.usage);
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
      _telemetry.publishRequest(
        modelId: modelId,
        attribution: attribution,
        metadata: ChatCompletionTerminalMetadata(
          finishReason: lastFinishReason,
          usage: lastUsage,
        ),
        timer: timer,
      );
    } catch (e, stackTrace) {
      final recoveredText = _responseNormalizer.recoverRawAssistantText(e);
      if (recoveredText != null) {
        appLog(
          '[LLM] Recovered raw text response after tool-result stream parse failure',
        );
        yield recoveredText;
        _telemetry.publishRequest(
          modelId: modelId,
          attribution: attribution,
          metadata: ChatCompletionTerminalMetadata(
            finishReason: lastFinishReason,
            usage: lastUsage,
          ),
          timer: timer,
        );
        return;
      }
      appLog('[LLM] streamWithToolResult error: ${e.runtimeType}: $e');
      appLog('[LLM] stackTrace: $stackTrace');
      _telemetry.publishFailure(
        modelId: modelId,
        timer: timer,
        attribution: attribution,
      );
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
    _logger.logMessages(messages);
    _logger.logTools(tools);
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
        temperature: _requestFallback.temperatureForRequest(temperature),
        topP: defaultTopP,
        maxTokens: _requestFallback.maxTokensForRequest(maxTokens),
        maxCompletionTokens: _requestFallback.maxCompletionTokensForRequest(
          maxTokens,
        ),
        tools: _buildTools(tools),
        reasoningEffort: _requestFallback.reasoningEffortForRequest(
          includeReasoning,
        ),
      );
    }

    appLog('[LLM] Sending request...');
    final timer = Stopwatch()..start();
    final attribution = _telemetry.captureAttribution();
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

      final reasoning = message.reasoningContent ?? message.reasoning;
      if (reasoning != null && reasoning.isNotEmpty) {
        appLog(
          '[LLM] reasoning: ${reasoning.length > 200 ? '${reasoning.substring(0, 200)}...' : reasoning}',
        );
      }
      _logger.logNativeToolCalls(message.toolCalls);
      final normalized = _responseNormalizer.normalize(
        content: message.content,
        reasoning: reasoning,
        nativeToolCalls: message.toolCalls,
        finishReason: choice.finishReason?.value,
        advertisedTools: tools,
        onNativeArgumentError: _logger.logNativeToolArgumentError,
      );
      appLog('[LLM] ==========================================');

      final usage = ChatResponseTelemetry.extractUsage(response.usage);
      _telemetry.publishRequest(
        modelId: modelId,
        attribution: attribution,
        metadata: ChatCompletionTerminalMetadata(
          finishReason: normalized.finishReason,
          usage: usage,
        ),
        timer: timer,
      );
      return ChatCompletionResult(
        content: normalized.content,
        toolCalls: normalized.toolCalls,
        finishReason: normalized.finishReason,
        usage: usage,
      );
    } catch (e, stackTrace) {
      final recovered = _responseNormalizer.recoverFromParseFailure(e);
      if (recovered != null) {
        appLog(
          '[LLM] Recovered raw text response after tool-result parse failure',
        );
        _telemetry.publishRequest(
          modelId: modelId,
          attribution: attribution,
          metadata: ChatCompletionTerminalMetadata(
            finishReason: recovered.finishReason,
            usage: lastUsage,
          ),
          timer: timer,
        );
        return ChatCompletionResult(
          content: recovered.content,
          toolCalls: recovered.toolCalls,
          finishReason: recovered.finishReason,
          usage: lastUsage,
        );
      }
      appLog(
        '[LLM] createChatCompletionWithToolResults error: ${e.runtimeType}: $e',
      );
      appLog('[LLM] stackTrace: $stackTrace');
      _telemetry.publishFailure(
        modelId: modelId,
        timer: timer,
        attribution: attribution,
      );
      rethrow;
    }
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
    return _responseNormalizer.recoverRawAssistantText(error);
  }

  @visibleForTesting
  List<ToolCallInfo>? parseEmbeddedToolCallsForTest(String content) {
    return _responseNormalizer.parseEmbeddedToolCalls(content);
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
      case 'delete_file':
        if (decoded['deleted'] == true) {
          interpretationLines.add(
            'Interpretation: delete_file succeeded and removed the target file.',
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
    try {
      final decoded = dart_convert.jsonDecode(value.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
