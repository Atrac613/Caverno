import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';

import 'farm_completion_fixture.dart';
import 'farm_completion_preflight.dart';
import 'farm_step_payload_guard.dart';

/// Inject the defective first implementation only; review, repair, commit and memory use HTTP.
final class FarmCompletionSource extends ChatDataSource
    implements FinishReasonAware {
  FarmCompletionSource(this.delegate, this.fixture, {this.preflight = false});
  final ChatDataSource delegate;
  final FarmCompletionFixture fixture;
  final bool preflight;
  String stage = 'implementation';
  final callsByStage = <String, int>{};
  late final offline = FarmCompletionPreflight(fixture);
  void beginTurn(String value) {
    stage = value;
    offline.beginTurn(value);
  }

  bool get injectedImplementation =>
      fixture.scenario == FarmCompletionScenario.reviewRepair &&
      stage == 'implementation';
  bool preludeUsed = false;
  int livePrimaryCalls = 0;
  int liveMemoryCalls = 0;
  final results = <String, ToolResultInfo>{};
  final memoryInputs = <String>[];
  final memoryResponses = <String>[];
  final outboundRequests = <Map<String, dynamic>>[];
  final liveResponses = <String>[];
  @override
  String? get lastFinishReason => delegate is FinishReasonAware
      ? (delegate as FinishReasonAware).lastFinishReason
      : null;

  void beforeRequest(
    List<Message> messages, {
    List<ToolResultInfo> results = const [],
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    bool memory = false,
  }) {
    guardFarmStepPayload(
      messages,
      results: results,
      assistantContent: assistantContent,
      tools: tools,
    );
    if (!memory) {
      callsByStage.update(stage, (value) => value + 1, ifAbsent: () => 1);
    }
    if (outboundRequests.length >= 48) {
      throw StateError('Farm canary request budget exhausted');
    }
    outboundRequests.add({
      'stage': stage,
      'role': memory ? 'memory' : 'primary',
      'messages': messages
          .map(
            (message) => {
              'role': message.role.name,
              'content': message.content,
            },
          )
          .toList(),
      'results': results
          .map(
            (result) => {
              'name': result.name,
              'arguments': result.arguments,
              'result': result.result,
            },
          )
          .toList(),
      'assistantContent': assistantContent,
      'tools': tools,
    });
  }

  void observe(List<ToolResultInfo> batch) {
    for (final result in batch) {
      results[result.id] = result;
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
    if (preflight || injectedImplementation) {
      if (!preflight) {
        preludeUsed = true;
      }
      final result = offline.next();
      return StreamWithToolsResult(
        stream: result.hasToolCalls
            ? const Stream.empty()
            : Stream.value(result.content),
        completion: Future.value(result),
      );
    }
    beforeRequest(messages, tools: tools);
    livePrimaryCalls++;
    return delegate.streamChatCompletionWithTools(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if (preflight || injectedImplementation) {
      return StreamedChatCompletion.fromStream(
        Stream.value(offline.report),
        finishReason: 'stop',
      );
    }
    beforeRequest(messages);
    livePrimaryCalls++;
    return delegate.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final memory =
        messages.isNotEmpty && messages.first.id == 'memory_extractor_system';
    if (!preflight && (memory || !injectedImplementation)) {
      beforeRequest(messages, tools: tools, memory: memory);
    }
    if (memory) {
      if (!preflight) {
        liveMemoryCalls++;
      }
      memoryInputs.add(messages.last.content);
    } else {
      if (!preflight && !injectedImplementation) {
        livePrimaryCalls++;
      }
    }
    final result = preflight || (!memory && injectedImplementation)
        ? (memory ? offline.memory() : offline.next())
        : await delegate.createChatCompletion(
            messages: messages,
            tools: tools,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
          );
    if (memory) {
      memoryResponses.add(result.content);
    }
    liveResponses.add(result.content);
    return result;
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
    observe(toolResults);
    if (preflight || injectedImplementation) {
      return offline.next();
    }
    beforeRequest(
      messages,
      results: toolResults,
      tools: tools,
      assistantContent: assistantContent,
    );
    livePrimaryCalls++;
    final result = await delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    liveResponses.add(result.content);
    return result;
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
  }) => createChatCompletionWithToolResults(
    messages: messages,
    toolResults: [
      ToolResultInfo(
        id: toolCallId,
        name: toolName,
        arguments: Map<String, dynamic>.from(jsonDecode(toolArguments) as Map),
        result: toolResult,
      ),
    ],
    assistantContent: assistantContent,
    tools: tools,
    model: model,
    temperature: temperature,
    maxTokens: maxTokens,
  );

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
  }) {
    if (preflight || injectedImplementation) {
      return Stream.value(offline.report);
    }
    beforeRequest(
      messages,
      results: [
        ToolResultInfo(
          id: toolCallId,
          name: toolName,
          arguments: Map<String, dynamic>.from(
            jsonDecode(toolArguments) as Map,
          ),
          result: toolResult,
        ),
      ],
      assistantContent: assistantContent,
    );
    livePrimaryCalls++;
    return delegate.streamWithToolResult(
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
  }
}
