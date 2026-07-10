import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/message.dart';
import 'chat_datasource.dart';
import 'chat_remote_datasource.dart';
import 'llm_session_log_store.dart';

final llmSessionLogStoreProvider = Provider<LlmSessionLogStore>((ref) {
  return LlmSessionLogStore();
});

class SessionLoggingChatDataSource
    implements ChatDataSource, FinishReasonAware {
  SessionLoggingChatDataSource({
    required ChatDataSource delegate,
    required LlmSessionLogStore logStore,
    LlmSessionLogContext? Function()? contextProvider,
  }) : _delegate = delegate,
       _logStore = logStore,
       _contextProvider =
           contextProvider ?? (() => LlmSessionLogContext.current);

  final ChatDataSource _delegate;
  final LlmSessionLogStore _logStore;
  final LlmSessionLogContext? Function() _contextProvider;

  LlmSessionLogContext? _resolveContext() {
    return LlmSessionLogContext.current ?? _contextProvider();
  }

  TokenUsage get lastUsage {
    final delegate = _delegate;
    if (delegate is ChatRemoteDataSource) {
      return delegate.lastUsage;
    }
    if (delegate is SessionLoggingChatDataSource) {
      return delegate.lastUsage;
    }
    return TokenUsage.zero;
  }

  @override
  String? get lastFinishReason {
    final delegate = _delegate;
    if (delegate is FinishReasonAware) {
      return (delegate as FinishReasonAware).lastFinishReason;
    }
    return null;
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return _streamChatCompletionAndLog(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  Stream<String> streamChatCompletionWithStructuredToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return _streamChatCompletionAndLog(
      messages: messages,
      toolResults: toolResults,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  Stream<String> _streamChatCompletionAndLog({
    required List<Message> messages,
    List<ToolResultInfo>? toolResults,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final context = _resolveContext();
    final startedAt = DateTime.now();
    final response = StringBuffer();
    try {
      final stream = _delegate.streamChatCompletion(
        messages: messages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      await for (final chunk in stream) {
        response.write(chunk);
        yield chunk;
      }
      await _record(
        context: context,
        request: LlmSessionLogRequest(
          operation: 'streamChatCompletion',
          messages: messages,
          toolResults: toolResults,
          model: model ?? ApiConstants.defaultModel,
          temperature: temperature ?? ApiConstants.defaultTemperature,
          maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
        ),
        startedAt: startedAt,
        response: LlmSessionLogResponse(
          content: response.toString(),
          finishReason: lastFinishReason ?? 'stream_end',
          usage: lastUsage,
        ),
      );
    } catch (error) {
      await _record(
        context: context,
        request: LlmSessionLogRequest(
          operation: 'streamChatCompletion',
          messages: messages,
          toolResults: toolResults,
          model: model ?? ApiConstants.defaultModel,
          temperature: temperature ?? ApiConstants.defaultTemperature,
          maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
        ),
        startedAt: startedAt,
        error: error,
      );
      rethrow;
    }
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final context = _resolveContext();
    final startedAt = DateTime.now();
    final request = LlmSessionLogRequest(
      operation: 'createChatCompletion',
      messages: messages,
      tools: tools,
      model: model ?? ApiConstants.defaultModel,
      temperature: temperature ?? ApiConstants.defaultTemperature,
      maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
    );
    try {
      final result = await _delegate.createChatCompletion(
        messages: messages,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        response: _responseFromResult(result),
      );
      return result;
    } catch (error) {
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        error: error,
      );
      rethrow;
    }
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final context = _resolveContext();
    final startedAt = DateTime.now();
    final request = LlmSessionLogRequest(
      operation: 'streamChatCompletionWithTools',
      messages: messages,
      tools: tools,
      model: model ?? ApiConstants.defaultModel,
      temperature: temperature ?? ApiConstants.defaultTemperature,
      maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
    );
    final response = StringBuffer();
    final result = _delegate.streamChatCompletionWithTools(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    final wrappedStream = result.stream.transform<String>(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          response.write(chunk);
          sink.add(chunk);
        },
      ),
    );
    final wrappedCompletion = result.completion.then(
      (completion) async {
        await _record(
          context: context,
          request: request,
          startedAt: startedAt,
          response: LlmSessionLogResponse(
            content: response.isEmpty
                ? completion.content
                : response.toString(),
            finishReason: completion.finishReason,
            toolCalls: completion.toolCalls,
            usage: completion.usage,
          ),
        );
        return completion;
      },
      onError: (Object error) async {
        await _record(
          context: context,
          request: request,
          startedAt: startedAt,
          error: error,
        );
        throw error;
      },
    );

    return StreamWithToolsResult(
      stream: wrappedStream,
      completion: wrappedCompletion,
    );
  }

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
    final context = _resolveContext();
    final startedAt = DateTime.now();
    final request = LlmSessionLogRequest(
      operation: 'streamWithToolResult',
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model ?? ApiConstants.defaultModel,
      temperature: temperature ?? ApiConstants.defaultTemperature,
      maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
    );
    final response = StringBuffer();
    try {
      final stream = _delegate.streamWithToolResult(
        messages: messages,
        toolCallId: toolCallId,
        toolName: toolName,
        toolArguments: toolArguments,
        toolResult: toolResult,
        assistantContent: assistantContent,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      await for (final chunk in stream) {
        response.write(chunk);
        yield chunk;
      }
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        response: LlmSessionLogResponse(
          content: response.toString(),
          finishReason: lastFinishReason ?? 'stream_end',
          usage: lastUsage,
        ),
      );
    } catch (error) {
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        error: error,
      );
      rethrow;
    }
  }

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
    final context = _resolveContext();
    final startedAt = DateTime.now();
    final request = LlmSessionLogRequest(
      operation: 'createChatCompletionWithToolResult',
      messages: messages,
      tools: tools,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model ?? ApiConstants.defaultModel,
      temperature: temperature ?? ApiConstants.defaultTemperature,
      maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
    );
    try {
      final result = await _delegate.createChatCompletionWithToolResult(
        messages: messages,
        toolCallId: toolCallId,
        toolName: toolName,
        toolArguments: toolArguments,
        toolResult: toolResult,
        assistantContent: assistantContent,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        response: _responseFromResult(result),
      );
      return result;
    } catch (error) {
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        error: error,
      );
      rethrow;
    }
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
    final context = _resolveContext();
    final startedAt = DateTime.now();
    final request = LlmSessionLogRequest(
      operation: 'createChatCompletionWithToolResults',
      messages: messages,
      tools: tools,
      toolResults: toolResults,
      assistantContent: assistantContent,
      model: model ?? ApiConstants.defaultModel,
      temperature: temperature ?? ApiConstants.defaultTemperature,
      maxTokens: maxTokens ?? ApiConstants.defaultMaxTokens,
    );
    try {
      final result = await _delegate.createChatCompletionWithToolResults(
        messages: messages,
        toolResults: toolResults,
        assistantContent: assistantContent,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        response: _responseFromResult(result),
      );
      return result;
    } catch (error) {
      await _record(
        context: context,
        request: request,
        startedAt: startedAt,
        error: error,
      );
      rethrow;
    }
  }

  LlmSessionLogResponse _responseFromResult(ChatCompletionResult result) {
    return LlmSessionLogResponse(
      content: result.content,
      finishReason: result.finishReason,
      toolCalls: result.toolCalls,
      usage: result.usage,
    );
  }

  Future<void> _record({
    required LlmSessionLogContext? context,
    required LlmSessionLogRequest request,
    required DateTime startedAt,
    LlmSessionLogResponse? response,
    Object? error,
  }) {
    return _logStore.record(
      context: context,
      request: request,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      response: response,
      error: error,
    );
  }
}
