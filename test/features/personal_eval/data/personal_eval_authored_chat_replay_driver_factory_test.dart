import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_authored_chat_replay_driver_factory.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory workspace;
  late Directory logs;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('authored_driver_');
    logs = Directory.systemTemp.createTempSync('authored_driver_logs_');
    Directory('${workspace.path}/src').createSync();
    File('${workspace.path}/src/value.dart').writeAsStringSync('value = 1\n');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    if (logs.existsSync()) logs.deleteSync(recursive: true);
  });

  test(
    'connects the live agent loop to the authored workspace tools',
    () async {
      final dataSource = _EditingChatDataSource();
      final factory = PersonalEvalAuthoredChatReplayDriverFactory(
        dataSource: dataSource,
        sessionLogStore: LlmSessionLogStore(
          rootDirectoryProvider: () async => logs,
        ),
        model: 'candidate-model',
        verificationRunner: _UnusedVerificationRunner(),
        maxTurns: 24,
        maxToolCalls: 100,
      );
      const evalCase = PersonalEvalCase(
        caseId: 'authored-one',
        prompt: 'Fix src/value.dart',
        repoStateRef: 'authored_fixture',
        origin: PersonalEvalCaseOrigin.authored,
        fixtureDirectory: 'fixture',
        verificationCommand: 'dart run bin/verify.dart',
      );

      final outcome = await factory(workspace.path, evalCase).drive(evalCase);

      expect(outcome.error, isNull);
      expect(dataSource.toolNames, containsAll(['read_file', 'edit_file']));
      expect(
        File('${workspace.path}/src/value.dart').readAsStringSync(),
        'value = 2\n',
      );
    },
  );

  test('propagates the authored tool-call budget to the runner', () async {
    final dataSource = _TwoEditChatDataSource();
    final factory = PersonalEvalAuthoredChatReplayDriverFactory(
      dataSource: dataSource,
      sessionLogStore: LlmSessionLogStore(
        rootDirectoryProvider: () async => logs,
      ),
      model: 'candidate-model',
      verificationRunner: _UnusedVerificationRunner(),
      maxTurns: 24,
      maxToolCalls: 1,
    );
    const evalCase = PersonalEvalCase(
      caseId: 'authored-budget',
      prompt: 'Fix src/value.dart',
      repoStateRef: 'authored_fixture',
      origin: PersonalEvalCaseOrigin.authored,
      fixtureDirectory: 'fixture',
      verificationCommand: 'dart run bin/verify.dart',
    );

    final outcome = await factory(workspace.path, evalCase).drive(evalCase);

    expect(outcome.error, isNull);
    expect(
      File('${workspace.path}/src/value.dart').readAsStringSync(),
      'value = 2\n',
    );
  });
}

class _EditingChatDataSource extends ChatDataSource {
  List<String> toolNames = [];
  var _initialRequest = true;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    toolNames = (tools ?? const [])
        .map(
          (tool) =>
              (tool['function'] as Map<String, dynamic>)['name'] as String,
        )
        .toList(growable: false);
    if (_initialRequest) {
      _initialRequest = false;
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'edit-1',
            name: 'edit_file',
            arguments: const {
              'path': 'src/value.dart',
              'old_text': 'value = 1',
              'new_text': 'value = 2',
            },
          ),
        ],
      );
    }
    return ChatCompletionResult(content: 'done', finishReason: 'stop');
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
  }) async => ChatCompletionResult(content: 'edited', finishReason: 'stop');

  @override
  StreamedChatCompletion streamChatCompletion({
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
}

class _UnusedVerificationRunner implements PersonalEvalVerificationRunner {
  @override
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  }) => throw UnimplementedError();
}

class _TwoEditChatDataSource extends ChatDataSource {
  var _requestCount = 0;

  ChatCompletionResult _next() {
    _requestCount += 1;
    if (_requestCount > 2) {
      return ChatCompletionResult(content: 'done', finishReason: 'stop');
    }
    final oldValue = _requestCount == 1 ? 'value = 1' : 'value = 2';
    final newValue = _requestCount == 1 ? 'value = 2' : 'value = 3';
    return ChatCompletionResult(
      content: '',
      finishReason: 'tool_calls',
      toolCalls: [
        ToolCallInfo(
          id: 'edit-$_requestCount',
          name: 'edit_file',
          arguments: {
            'path': 'src/value.dart',
            'old_text': oldValue,
            'new_text': newValue,
          },
        ),
      ],
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _next();

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
  }) async => _next();

  @override
  StreamedChatCompletion streamChatCompletion({
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
}
