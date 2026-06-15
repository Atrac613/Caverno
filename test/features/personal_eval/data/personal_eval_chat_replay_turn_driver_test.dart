import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_chat_replay_turn_driver.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/routines/data/routine_tool_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the [createChatCompletion] call and returns a canned result (or
/// throws) so the driver's drive + log-readback behavior is deterministic.
class _FakeChatDataSource extends ChatDataSource {
  _FakeChatDataSource({this.error});

  final Object? error;
  List<Message>? lastMessages;
  String? lastModel;
  double? lastTemperature;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    lastMessages = messages;
    lastModel = model;
    lastTemperature = temperature;
    if (error != null) {
      throw error!;
    }
    return ChatCompletionResult(content: 'done', finishReason: 'stop');
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();
}

/// Captures how the driver invoked the agent loop and lets the test exercise
/// the dispatch callback the driver wired in.
class _FakeToolRunner extends RoutineToolRunner {
  _FakeToolRunner(ChatDataSource dataSource) : super(dataSource: dataSource);

  List<Map<String, dynamic>>? capturedTools;
  String? capturedModel;
  Future<McpToolResult> Function(ToolCallInfo)? capturedDispatch;

  @override
  Future<RoutineToolExecutionResult> execute({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    required Future<McpToolResult> Function(ToolCallInfo toolCall)
    dispatchToolCall,
    required String model,
    required double temperature,
    required int maxTokens,
  }) async {
    capturedTools = tools;
    capturedModel = model;
    capturedDispatch = dispatchToolCall;
    return const RoutineToolExecutionResult(output: 'done');
  }
}

void main() {
  late Directory tempDir;
  late LlmSessionLogStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('personal_eval_replay_');
    store = LlmSessionLogStore(rootDirectoryProvider: () async => tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  PersonalEvalCase evalCase({String? verificationCommand}) {
    return PersonalEvalCase(
      caseId: 'c1',
      title: 'Login crash',
      prompt: 'Fix the crash',
      repoStateRef: 'abc',
      consentGranted: true,
      verificationCommand: verificationCommand,
    );
  }

  test(
    'drives the candidate model and reads back the scoped session log',
    () async {
      final dataSource = _FakeChatDataSource();
      // Pre-write the log at the path the driver will resolve (coding workspace,
      // personal-eval-replay-<caseId> session id) to stand in for the logging
      // datasource.
      const context = LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'personal-eval-replay-c1',
      );
      final logFile = await store.fileForContext(context);
      await logFile.writeAsString('{"operation":"chat"}');

      final driver = PersonalEvalChatReplayTurnDriver(
        dataSource: dataSource,
        sessionLogStore: store,
        model: 'candidate-model',
        workingDirectory: '/tmp/project',
      );

      final result = await driver.drive(evalCase());

      expect(result.logPath, logFile.path);
      expect(result.logContents, '{"operation":"chat"}');
      expect(result.workingDirectory, '/tmp/project');
      expect(result.error, isNull);
      // The candidate model and the case prompt drove the turn.
      expect(dataSource.lastModel, 'candidate-model');
      expect(dataSource.lastMessages?.last.content, 'Fix the crash');
      expect(dataSource.lastMessages?.first.role, MessageRole.system);
    },
  );

  test('runs the agent loop when tool capabilities are provided', () async {
    final dataSource = _FakeChatDataSource();
    final toolRunner = _FakeToolRunner(dataSource);
    final dispatched = <String>[];

    final driver = PersonalEvalChatReplayTurnDriver(
      dataSource: dataSource,
      sessionLogStore: store,
      model: 'candidate-model',
      workingDirectory: '/tmp/project',
      toolRunner: toolRunner,
      toolDefinitions: () => [
        {
          'type': 'function',
          'function': {'name': 'read_file'},
        },
      ],
      dispatchToolCall: (toolCall) async {
        dispatched.add(toolCall.name);
        return McpToolResult(
          toolName: toolCall.name,
          result: 'ok',
          isSuccess: true,
        );
      },
    );

    final result = await driver.drive(evalCase());

    // The agent loop ran with the candidate model and tools, not the
    // single-completion fallback.
    expect(toolRunner.capturedModel, 'candidate-model');
    expect(toolRunner.capturedTools, isNotEmpty);
    expect(dataSource.lastModel, isNull);
    expect(result.workingDirectory, '/tmp/project');

    // The wired dispatch routes tool calls to the injected executor.
    await toolRunner.capturedDispatch!(
      ToolCallInfo(id: 't1', name: 'read_file', arguments: const {}),
    );
    expect(dispatched, ['read_file']);
  });

  test('a failed turn surfaces the error without aborting', () async {
    final dataSource = _FakeChatDataSource(error: StateError('endpoint down'));
    final driver = PersonalEvalChatReplayTurnDriver(
      dataSource: dataSource,
      sessionLogStore: store,
      model: 'candidate-model',
      workingDirectory: '/tmp/project',
    );

    final result = await driver.drive(evalCase());

    expect(result.error, contains('endpoint down'));
    expect(result.workingDirectory, '/tmp/project');
    // No log was written, so contents are empty rather than throwing.
    expect(result.logContents, isEmpty);
  });
}
