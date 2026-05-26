import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmSessionLogStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('llm_session_log_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes JSONL entries and redacts image payloads', () async {
      final store = LlmSessionLogStore(
        rootDirectoryProvider: () async => tempDir,
      );
      final context = LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'conversation/1',
        sessionTitle: 'Investigate logs',
        conversationId: 'conversation/1',
      );
      final startedAt = DateTime(2026, 5, 26, 12);

      await store.record(
        context: context,
        request: LlmSessionLogRequest(
          operation: 'createChatCompletion',
          messages: [
            Message(
              id: 'user-1',
              content: 'Inspect screenshot',
              role: MessageRole.user,
              timestamp: startedAt,
              imageBase64: 'large-image-payload',
              imageMimeType: 'image/png',
            ),
          ],
          toolResults: [
            ToolResultInfo(
              id: 'tool-1',
              name: 'computer_screenshot',
              arguments: {},
              result:
                  '{"imageBase64":"tool-image-payload","imageMimeType":"image/png"}',
            ),
          ],
          model: 'model-a',
          temperature: 0.2,
          maxTokens: 1000,
        ),
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(milliseconds: 42)),
        response: const LlmSessionLogResponse(
          content: 'Done',
          finishReason: 'stop',
          usage: TokenUsage(
            promptTokens: 1,
            completionTokens: 2,
            totalTokens: 3,
          ),
        ),
      );

      final file = await store.fileForContext(context);
      final lines = await file.readAsLines();
      expect(lines, hasLength(1));
      expect(lines.single, isNot(contains('large-image-payload')));
      expect(lines.single, isNot(contains('tool-image-payload')));

      final decoded = jsonDecode(lines.single) as Map<String, dynamic>;
      expect(decoded['schemaName'], LlmSessionLogStore.schemaName);
      expect(decoded['context']['workspaceMode'], 'coding');
      expect(decoded['context']['sessionId'], 'conversation/1');
      expect(
        decoded['request']['messages'][0]['image']['base64'],
        '[redacted]',
      );
      expect(
        decoded['request']['toolResults'][0]['result']['imageBase64'],
        '[redacted]',
      );
      expect(decoded['response']['content'], 'Done');
    });

    test('redacts common secret patterns embedded in text', () async {
      final store = LlmSessionLogStore(
        rootDirectoryProvider: () async => tempDir,
        retentionPolicy: const LlmSessionLogRetentionPolicy(maxAge: null),
      );
      final context = const LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'secret-check',
      );
      final startedAt = DateTime(2026, 5, 26, 12);

      await store.record(
        context: context,
        request: LlmSessionLogRequest(
          operation: 'createChatCompletion',
          messages: [
            _message(
              'user-1',
              MessageRole.user,
              [
                'Authorization: Bearer abcdefghijklmnopqrstuvwxyz',
                'OPENAI_API_KEY=sk-1234567890abcdefghijklmnop',
                'https://user:pass@example.com/path?token=secret-token',
                '-----BEGIN PRIVATE KEY-----',
                'secret-private-key-material',
                '-----END PRIVATE KEY-----',
              ].join('\n'),
            ),
          ],
          toolArguments: jsonEncode({
            'headers': {'Authorization': 'Bearer nested-secret-token'},
            'env': 'GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz123456',
          }),
          toolResult: jsonEncode({
            'access_token': 'json-access-token',
            'output':
                'Bearer plain-secret-token and sk-abcdefghijklmnopqrstuvwxyz',
          }),
        ),
        startedAt: startedAt,
        finishedAt: startedAt,
        response: const LlmSessionLogResponse(
          content:
              'Use github_pat_abcdefghijklmnopqrstuvwxyz1234567890 carefully',
        ),
      );

      final line = (await (await store.fileForContext(
        context,
      )).readAsLines()).single;
      expect(line, isNot(contains('abcdefghijklmnopqrstuvwxyz')));
      expect(line, isNot(contains('secret-token')));
      expect(line, isNot(contains('secret-private-key-material')));
      expect(line, isNot(contains('json-access-token')));
      expect(line, contains('[redacted]'));
      expect(line, contains('[redacted-private-key]'));
      expect(line, contains('[redacted-github-token]'));
    });

    test(
      'rotates session log files when the active file exceeds limit',
      () async {
        final store = LlmSessionLogStore(
          rootDirectoryProvider: () async => tempDir,
          retentionPolicy: const LlmSessionLogRetentionPolicy(
            maxFileBytes: 1,
            maxAge: null,
            maxRotatedFiles: 2,
          ),
        );
        final context = const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.chat,
          sessionId: 'rotation-check',
        );
        final startedAt = DateTime(2026, 5, 26, 12);

        for (var index = 0; index < 3; index++) {
          await store.record(
            context: context,
            request: LlmSessionLogRequest(
              operation: 'createChatCompletion',
              messages: [
                _message('user-$index', MessageRole.user, 'message $index'),
              ],
            ),
            startedAt: startedAt.add(Duration(seconds: index)),
            finishedAt: startedAt.add(Duration(seconds: index)),
          );
        }

        final file = await store.fileForContext(context);
        expect(await file.exists(), isTrue);
        expect(await File('${file.path}.1').exists(), isTrue);
        expect(await File('${file.path}.2').exists(), isTrue);
        expect((await file.readAsLines()).single, contains('message 2'));
        expect(
          (await File('${file.path}.1').readAsLines()).single,
          contains('message 1'),
        );
        expect(
          (await File('${file.path}.2').readAsLines()).single,
          contains('message 0'),
        );
      },
    );

    test(
      'removes expired session log files in the workspace directory',
      () async {
        final store = LlmSessionLogStore(
          rootDirectoryProvider: () async => tempDir,
          retentionPolicy: const LlmSessionLogRetentionPolicy(
            maxFileBytes: null,
            maxAge: Duration(days: 7),
          ),
        );
        final workspaceDir = Directory('${tempDir.path}/coding');
        await workspaceDir.create(recursive: true);
        final expired = File('${workspaceDir.path}/expired.jsonl');
        final expiredRotated = File('${workspaceDir.path}/expired.jsonl.1');
        final recent = File('${workspaceDir.path}/recent.jsonl');
        await expired.writeAsString('old\n');
        await expiredRotated.writeAsString('old rotated\n');
        await recent.writeAsString('recent\n');
        await expired.setLastModified(DateTime(2026, 5, 1));
        await expiredRotated.setLastModified(DateTime(2026, 5, 1));
        await recent.setLastModified(DateTime(2026, 5, 25));

        await store.record(
          context: const LlmSessionLogContext(
            workspaceMode: WorkspaceMode.coding,
            sessionId: 'current',
          ),
          request: LlmSessionLogRequest(
            operation: 'createChatCompletion',
            messages: [_message('user-1', MessageRole.user, 'current')],
          ),
          startedAt: DateTime(2026, 5, 26),
          finishedAt: DateTime(2026, 5, 26),
        );

        expect(await expired.exists(), isFalse);
        expect(await expiredRotated.exists(), isFalse);
        expect(await recent.exists(), isTrue);
      },
    );

    test('uses explicit setting unless environment overrides enablement', () {
      expect(
        LlmSessionLogStore.isEnabled(
          settingsEnabled: false,
          environment: const {},
        ),
        isFalse,
      );
      expect(
        LlmSessionLogStore.isEnabled(
          settingsEnabled: true,
          environment: const {},
        ),
        isTrue,
      );
      expect(
        LlmSessionLogStore.isEnabled(
          settingsEnabled: false,
          environment: const {'CAVERNO_SESSION_LOG_ENABLED': '1'},
        ),
        isTrue,
      );
      expect(
        LlmSessionLogStore.isEnabled(
          settingsEnabled: true,
          environment: const {'CAVERNO_SESSION_LOG_ENABLED': 'false'},
        ),
        isFalse,
      );
    });
  });

  group('SessionLoggingChatDataSource', () {
    late Directory tempDir;
    late LlmSessionLogStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('session_logging_ds_');
      store = LlmSessionLogStore(rootDirectoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('records non-streaming completions', () async {
      final context = const LlmSessionLogContext(
        workspaceMode: WorkspaceMode.chat,
        sessionId: 'chat-1',
        conversationId: 'chat-1',
      );
      final dataSource = SessionLoggingChatDataSource(
        delegate: _FakeChatDataSource(
          completionResult: ChatCompletionResult(
            content: 'Hello',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'call-1',
                name: 'read_file',
                arguments: {'path': 'README.md'},
              ),
            ],
            usage: const TokenUsage(
              promptTokens: 10,
              completionTokens: 5,
              totalTokens: 15,
            ),
          ),
        ),
        logStore: store,
      );

      await LlmSessionLogContext.run(context, () {
        return dataSource.createChatCompletion(
          messages: [_message('user-1', MessageRole.user, 'Hi')],
          tools: const [
            {
              'type': 'function',
              'function': {'name': 'read_file', 'description': 'Read a file'},
            },
          ],
          model: 'model-a',
          temperature: 0.3,
          maxTokens: 900,
        );
      });

      final line = (await (await store.fileForContext(
        context,
      )).readAsLines()).single;
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded['operation'], 'createChatCompletion');
      expect(decoded['request']['model'], 'model-a');
      expect(decoded['request']['tools'][0]['function']['name'], 'read_file');
      expect(decoded['response']['content'], 'Hello');
      expect(decoded['response']['toolCalls'][0]['name'], 'read_file');
      expect(decoded['response']['usage']['totalTokens'], 15);
    });

    test(
      'records streamed tool completions after the stream is consumed',
      () async {
        final context = const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.routines,
          sessionId: 'routine-run-1',
          routineId: 'routine-1',
          routineRunId: 'run-1',
        );
        final dataSource = SessionLoggingChatDataSource(
          delegate: _FakeChatDataSource(
            streamWithToolsResult: ChatCompletionResult(
              content: 'ignored structured content',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(id: 'call-1', name: 'ping', arguments: {}),
              ],
              usage: const TokenUsage(totalTokens: 7),
            ),
            streamChunks: const ['hel', 'lo'],
          ),
          logStore: store,
        );

        final result = LlmSessionLogContext.run(context, () {
          return dataSource.streamChatCompletionWithTools(
            messages: [_message('user-1', MessageRole.user, 'Run routine')],
            tools: const [
              {
                'type': 'function',
                'function': {'name': 'ping'},
              },
            ],
          );
        });
        expect(await result.stream.join(), 'hello');
        await result.completion;

        final line = (await (await store.fileForContext(
          context,
        )).readAsLines()).single;
        final decoded = jsonDecode(line) as Map<String, dynamic>;
        expect(decoded['operation'], 'streamChatCompletionWithTools');
        expect(decoded['context']['workspaceMode'], 'routines');
        expect(decoded['response']['content'], 'hello');
        expect(decoded['response']['toolCalls'][0]['name'], 'ping');
      },
    );
  });
}

Message _message(String id, MessageRole role, String content) {
  return Message(
    id: id,
    content: content,
    role: role,
    timestamp: DateTime(2026, 5, 26, 12),
  );
}

class _FakeChatDataSource implements ChatDataSource {
  _FakeChatDataSource({
    ChatCompletionResult? completionResult,
    ChatCompletionResult? streamWithToolsResult,
    this.streamChunks = const ['streamed'],
  }) : completionResult =
           completionResult ??
           ChatCompletionResult(content: 'ok', finishReason: 'stop'),
       streamWithToolsResult =
           streamWithToolsResult ??
           ChatCompletionResult(content: 'ok', finishReason: 'stop');

  final ChatCompletionResult completionResult;
  final ChatCompletionResult streamWithToolsResult;
  final List<String> streamChunks;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return Stream.fromIterable(streamChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    return completionResult;
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final completer = Completer<ChatCompletionResult>();
    Stream<String> stream() async* {
      for (final chunk in streamChunks) {
        yield chunk;
      }
      completer.complete(streamWithToolsResult);
    }

    return StreamWithToolsResult(
      stream: stream(),
      completion: completer.future,
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
  }) {
    return Stream.fromIterable(streamChunks);
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
    return completionResult;
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
    return completionResult;
  }
}
