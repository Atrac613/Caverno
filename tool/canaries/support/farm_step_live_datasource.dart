import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';

import 'farm_step_live_fixture.dart';
import 'farm_step_payload_guard.dart';

/// Script only the fault entry. All recovery, reporting and memory use HTTP.
final class FarmStepLiveDataSource extends ChatDataSource
    implements FinishReasonAware {
  FarmStepLiveDataSource(this.delegate, this.fixture);
  final ChatDataSource delegate;
  final FarmStepFixture fixture;
  bool preludeUsed = false;
  bool preludeFollowupUsed = false;
  bool faultAnswerUsed = false;
  int livePrimaryCalls = 0;
  int liveMemoryCalls = 0;
  int recoveryCalls = 0;
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
  }) {
    guardFarmStepPayload(
      messages,
      results: results,
      assistantContent: assistantContent,
      tools: tools,
    );
    outboundRequests.add({
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
    if (!preludeUsed) {
      preludeUsed = true;
      final scenario = fixture.scenario;
      return StreamWithToolsResult(
        stream: const Stream.empty(),
        completion: Future.value(
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'fixture-read',
                name: 'read_file',
                arguments: {'path': 'policy.md'},
              ),
              if (scenario != FarmStepScenario.missingExecution &&
                  scenario != FarmStepScenario.unissuedCommand)
                ToolCallInfo(
                  id: 'fixture-verify',
                  name: 'local_execute_command',
                  arguments: {
                    'command': farmStepVerify,
                    'working_directory': fixture.root.path,
                  },
                ),
              if (scenario == FarmStepScenario.environmentLookup)
                ToolCallInfo(
                  id: 'fixture-probe',
                  name: 'local_execute_command',
                  arguments: {
                    'command': farmStepProbe,
                    'working_directory': fixture.root.path,
                  },
                ),
            ],
          ),
        ),
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
    if (!faultAnswerUsed &&
        fixture.scenario != FarmStepScenario.environmentLookup) {
      faultAnswerUsed = true;
      final content = fixture.scenario == FarmStepScenario.missingExecution
          ? 'The local command completed.\nPROJECT_TASK_SUBTASK_DONE'
          : fixture.scenario == FarmStepScenario.unissuedCommand
          ? 'The local command completed.\n{"command":".venv/bin/python tool/unavailable.py"}\nPROJECT_TASK_SUBTASK_DONE'
          : 'Everything passed.\nPROJECT_TASK_SUBTASK_DONE';
      return StreamedChatCompletion.fromStream(
        Stream.value(content),
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
    beforeRequest(messages, tools: tools);
    final memory =
        messages.isNotEmpty && messages.first.id == 'memory_extractor_system';
    if (memory) {
      liveMemoryCalls++;
      memoryInputs.add(messages.last.content);
    } else {
      livePrimaryCalls++;
    }
    final result = await delegate.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    if (memory) memoryResponses.add(result.content);
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
    if (!preludeFollowupUsed) {
      preludeFollowupUsed = true;
      return ChatCompletionResult(content: '', finishReason: 'stop');
    }
    if (messages.any(
      (message) =>
          message.id.startsWith('structured_project_subtask_recovery_'),
    )) {
      recoveryCalls++;
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
    beforeRequest(messages, assistantContent: toolResult);
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
