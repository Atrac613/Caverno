import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';

import 'farm_step_live_fixture.dart';

/// Deterministic offline preflight; never qualifies as live model evidence.
final class FarmStepPreflightDataSource extends ChatDataSource {
  FarmStepPreflightDataSource(this.fixture);
  final FarmStepFixture fixture;
  String get report => fixture.scenario.accepted
      ? 'Verified policy.\nPROJECT_TASK_SUBTASK_DONE'
      : 'Blocked: the recorded requirement remains unresolved.';
  ChatCompletionResult answer() =>
      ChatCompletionResult(content: report, finishReason: 'stop');
  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(
    Stream.value(report),
    finishReason: 'stop',
  );
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => ChatCompletionResult(
    content: jsonEncode({
      'summary': 'Everything completed.',
      'open_loops': [],
      'profile': {'persona': [], 'preferences': [], 'do_not': []},
      'memories': [],
    }),
    finishReason: 'stop',
  );
  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamWithToolsResult(
    stream: const Stream.empty(),
    completion: Future.value(
      ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'second-verify',
            name: 'local_execute_command',
            arguments: {
              'command': fixture.verificationCommand,
              'working_directory': fixture.root.path,
            },
          ),
        ],
      ),
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
  }) async {
    if ((fixture.scenario == FarmStepScenario.missingExecution ||
            fixture.scenario == FarmStepScenario.unissuedCommand ||
            fixture.scenario == FarmStepScenario.stdinVerification) &&
        !toolResults.any(
          (result) =>
              result.name == 'local_execute_command' &&
              result.arguments['command'] == fixture.verificationCommand,
        )) {
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'recovery-verify',
            name: 'local_execute_command',
            arguments: {
              'command': fixture.verificationCommand,
              'working_directory': fixture.root.path,
            },
          ),
        ],
      );
    }
    return answer();
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
  }) async => answer();
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
  }) => Stream.value(report);
}
