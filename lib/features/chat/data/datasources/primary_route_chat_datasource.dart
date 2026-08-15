import 'dart:async';

import '../../../settings/domain/services/mesh_endpoint_router.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import 'chat_datasource.dart';

/// Routes every request in one LL24 turn to an assigned endpoint and retries
/// on the primary endpoint when the assigned attempt fails before emitting
/// visible content.
///
/// The wrapper is created from an immutable turn route. It never reads live
/// settings, so queued turns and mid-turn settings changes cannot split a turn
/// across models. A streaming failure after the first chunk is propagated
/// instead of replayed, preventing duplicated visible content.
final class PrimaryRouteChatDataSource
    implements ChatDataSource, FinishReasonAware, RequestParameterFallbackAware {
  PrimaryRouteChatDataSource({
    required ChatDataSource assigned,
    required ChatDataSource primary,
    required this.assignedEndpointId,
    required this.assignedModel,
    required this.primaryModel,
    required EndpointHealthTracker health,
  }) : _assigned = assigned,
       _primary = primary,
       _health = health;

  final ChatDataSource _assigned;
  final ChatDataSource _primary;
  final EndpointHealthTracker _health;
  final String assignedEndpointId;
  final String assignedModel;
  final String primaryModel;

  String? _lastFinishReason;

  @override
  String? get lastFinishReason => _lastFinishReason;

  /// True when either leg drops the requested temperature: a request can land on
  /// the assigned endpoint or fall back to the primary, so a measurement is only
  /// trustworthy when both honour it.
  @override
  bool get endpointIgnoresRequestedTemperature =>
      RequestParameterFallbackAware.ignoresTemperature(_assigned) ||
      RequestParameterFallbackAware.ignoresTemperature(_primary);

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    ChatCompletionTerminalMetadata? terminalMetadata;

    Stream<String> routedStream() async* {
      var emitted = false;
      try {
        final completion = _assigned.streamChatCompletion(
          messages: messages,
          model: assignedModel,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        await for (final chunk in completion) {
          emitted = true;
          yield chunk;
        }
        terminalMetadata = await completion.terminal;
        _lastFinishReason = terminalMetadata?.finishReason;
        _health.recordSuccess(assignedEndpointId);
      } catch (error) {
        _recordFailure(error);
        if (emitted) rethrow;
        final completion = _primary.streamChatCompletion(
          messages: messages,
          model: primaryModel,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        await for (final chunk in completion) {
          yield chunk;
        }
        terminalMetadata = await completion.terminal;
        _lastFinishReason = terminalMetadata?.finishReason;
      }
    }

    return StreamedChatCompletion.capture(
      stream: routedStream(),
      terminalMetadata: () =>
          terminalMetadata ?? const ChatCompletionTerminalMetadata(),
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => _run(
    assignedCall: () => _assigned.createChatCompletion(
      messages: messages,
      tools: tools,
      model: assignedModel,
      temperature: temperature,
      maxTokens: maxTokens,
    ),
    primaryCall: () => _primary.createChatCompletion(
      messages: messages,
      tools: tools,
      model: primaryModel,
      temperature: temperature,
      maxTokens: maxTokens,
    ),
  );

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final controller = StreamController<String>();
    final completion = Completer<ChatCompletionResult>();

    unawaited(() async {
      var emitted = false;
      try {
        final result = _assigned.streamChatCompletionWithTools(
          messages: messages,
          tools: tools,
          model: assignedModel,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        await for (final chunk in result.stream) {
          emitted = true;
          controller.add(chunk);
        }
        final value = await result.completion;
        _lastFinishReason = value.finishReason;
        _health.recordSuccess(assignedEndpointId);
        completion.complete(value);
        await controller.close();
      } catch (error, stackTrace) {
        _recordFailure(error);
        if (emitted) {
          controller.addError(error, stackTrace);
          completion.completeError(error, stackTrace);
          await controller.close();
          return;
        }
        try {
          final result = _primary.streamChatCompletionWithTools(
            messages: messages,
            tools: tools,
            model: primaryModel,
            temperature: temperature,
            maxTokens: maxTokens,
          );
          await for (final chunk in result.stream) {
            controller.add(chunk);
          }
          final value = await result.completion;
          _lastFinishReason = value.finishReason;
          completion.complete(value);
          await controller.close();
        } catch (fallbackError, fallbackStackTrace) {
          controller.addError(fallbackError, fallbackStackTrace);
          completion.completeError(fallbackError, fallbackStackTrace);
          await controller.close();
        }
      }
    }());

    return StreamWithToolsResult(
      stream: controller.stream,
      completion: completion.future,
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
    var emitted = false;
    try {
      final stream = _assigned.streamWithToolResult(
        messages: messages,
        toolCallId: toolCallId,
        toolName: toolName,
        toolArguments: toolArguments,
        toolResult: toolResult,
        assistantContent: assistantContent,
        model: assignedModel,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      await for (final chunk in stream) {
        emitted = true;
        yield chunk;
      }
      _captureFinishReason(_assigned);
      _health.recordSuccess(assignedEndpointId);
    } catch (error) {
      _recordFailure(error);
      if (emitted) rethrow;
      final stream = _primary.streamWithToolResult(
        messages: messages,
        toolCallId: toolCallId,
        toolName: toolName,
        toolArguments: toolArguments,
        toolResult: toolResult,
        assistantContent: assistantContent,
        model: primaryModel,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      await for (final chunk in stream) {
        yield chunk;
      }
      _captureFinishReason(_primary);
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
  }) => _run(
    assignedCall: () => _assigned.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: assignedModel,
      temperature: temperature,
      maxTokens: maxTokens,
    ),
    primaryCall: () => _primary.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: primaryModel,
      temperature: temperature,
      maxTokens: maxTokens,
    ),
  );

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => _run(
    assignedCall: () => _assigned.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: assignedModel,
      temperature: temperature,
      maxTokens: maxTokens,
    ),
    primaryCall: () => _primary.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: primaryModel,
      temperature: temperature,
      maxTokens: maxTokens,
    ),
  );

  Future<ChatCompletionResult> _run({
    required Future<ChatCompletionResult> Function() assignedCall,
    required Future<ChatCompletionResult> Function() primaryCall,
  }) async {
    try {
      final result = await assignedCall();
      _lastFinishReason = result.finishReason;
      _health.recordSuccess(assignedEndpointId);
      return result;
    } catch (error) {
      _recordFailure(error);
      final result = await primaryCall();
      _lastFinishReason = result.finishReason;
      return result;
    }
  }

  void _captureFinishReason(ChatDataSource dataSource) {
    if (dataSource is FinishReasonAware) {
      _lastFinishReason = (dataSource as FinishReasonAware).lastFinishReason;
    }
  }

  void _recordFailure(Object error) {
    _health.recordFailure(
      assignedEndpointId,
      hard: _isHardEndpointFailure(error),
    );
  }

  bool _isHardEndpointFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('connection refused') ||
        text.contains('connection failed') ||
        text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('connection terminated') ||
        text.contains('no route to host') ||
        text.contains('network is unreachable') ||
        text.contains('host is unreachable') ||
        text.contains('failed host lookup') ||
        text.contains('errno = 61') ||
        text.contains('errno = 111');
  }
}
