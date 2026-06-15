import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_chat_replay_turn_driver.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
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
