import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_completion_terminal_metadata.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('caverno_usage_log_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Map<String, dynamic>> recordAndRead(TokenUsage usage) async {
    final store = LlmSessionLogStore(
      rootDirectoryProvider: () async => tempDir,
    );
    final context = LlmSessionLogContext(
      workspaceMode: WorkspaceMode.coding,
      sessionId: 'conversation/1',
      conversationId: 'conversation/1',
    );
    final startedAt = DateTime(2026, 8, 8, 12);

    await store.record(
      context: context,
      request: LlmSessionLogRequest(
        operation: 'createChatCompletion',
        messages: [
          Message(
            id: 'user-1',
            content: 'Hi',
            role: MessageRole.user,
            timestamp: startedAt,
          ),
        ],
        model: 'model-a',
        temperature: 0.2,
        maxTokens: 1000,
      ),
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(milliseconds: 42)),
      response: LlmSessionLogResponse(
        content: 'Done',
        finishReason: 'stop',
        usage: usage,
      ),
    );

    final file = await store.fileForContext(context);
    final entry = jsonDecode(file.readAsLinesSync().single);
    return (entry as Map<String, dynamic>)['response']['usage']
        as Map<String, dynamic>;
  }

  test('emits the full breakdown the provider reported', () async {
    final usage = await recordAndRead(
      const TokenUsage(
        promptTokens: 1000,
        completionTokens: 200,
        totalTokens: 1200,
        cachedPromptTokens: 900,
        reasoningTokens: 60,
        acceptedPredictionTokens: 5,
      ),
    );

    expect(usage['promptTokens'], 1000);
    expect(usage['completionTokens'], 200);
    expect(usage['totalTokens'], 1200);
    expect(usage['cachedPromptTokens'], 900);
    expect(usage['reasoningTokens'], 60);
    expect(usage['acceptedPredictionTokens'], 5);
  });

  test('omits detail keys the provider never reported', () async {
    // 0 would be indistinguishable from a measured zero; absence is honest.
    final usage = await recordAndRead(
      const TokenUsage(promptTokens: 10, completionTokens: 2, totalTokens: 12),
    );

    expect(usage.keys, containsAll(<String>['promptTokens', 'totalTokens']));
    expect(usage.containsKey('cachedPromptTokens'), isFalse);
    expect(usage.containsKey('reasoningTokens'), isFalse);
  });

  test('a reader that only knows the original keys still parses', () async {
    // The new fields are additive within `response.usage`, so the schema
    // version stays at 3 and tool/triage_session_logs.py keeps working.
    final usage = await recordAndRead(
      const TokenUsage(
        promptTokens: 10,
        completionTokens: 2,
        totalTokens: 12,
        cachedPromptTokens: 8,
      ),
    );

    expect(usage['promptTokens'], 10);
    expect(usage['completionTokens'], 2);
    expect(usage['totalTokens'], 12);
  });
}
