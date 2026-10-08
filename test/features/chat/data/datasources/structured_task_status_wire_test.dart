import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/mcp_goal_routine_tool_definitions.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/coding/coding_continuation_recovery_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      'forces status elicitation once and logs the wire choice (stream=$streaming)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'task_status_wire_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final bodies = <Map<String, dynamic>>[];
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          final response = {
            'id': 'completion',
            'created': 0,
            'model': 'qwen3.8-27b-exl3',
            'object': streaming ? 'chat.completion.chunk' : 'chat.completion',
            'choices': [
              {
                'index': 0,
                'finish_reason': 'stop',
                streaming ? 'delta' : 'message': {
                  'role': 'assistant',
                  'content': 'done',
                },
              },
            ],
          };
          return http.Response(
            streaming
                ? 'data: ${jsonEncode(response)}\n\ndata: [DONE]\n\n'
                : jsonEncode(response),
            200,
            headers: {
              'content-type': streaming
                  ? 'text/event-stream'
                  : 'application/json',
            },
          );
        });
        final remote = ChatRemoteDataSource(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: 'no-key',
          httpClient: client,
          streamClientFactory: () => client,
        );
        final store = LlmSessionLogStore(
          rootDirectoryProvider: () async => directory,
        );
        final source = SessionLoggingChatDataSource(
          delegate: remote,
          logStore: store,
        );
        const context = LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: 'task-status',
          conversationId: 'task-status',
        );
        final recovery = const CodingContinuationRecoveryPolicy()
            .buildCodingContinuationRecoveryToolResult(
              id: 'status',
              candidateResponse: 'Listo.',
              recoveryCode: 'structured_coding_task_status',
            );
        final acknowledgement = ToolResultInfo(
          id: 'ack',
          name: 'update_goal',
          arguments: const {'completed': false, 'message': 'Continue'},
          result: 'Progress logged.',
        );
        for (final results in [
          [recovery],
          [recovery, acknowledgement],
        ]) {
          await LlmSessionLogContext.run(context, () async {
            final messages = [
              Message(
                id: 'request',
                content: 'Report task state',
                role: MessageRole.user,
                timestamp: DateTime(2026),
              ),
            ];
            if (streaming) {
              final result = source.streamChatCompletionWithToolResults(
                messages: messages,
                toolResults: results,
                tools: [McpGoalRoutineToolDefinitions.updateGoalTool],
                model: 'qwen3.8-27b-exl3',
              );
              await result.stream.drain<void>();
              await result.completion;
            } else {
              await source.createChatCompletionWithToolResults(
                messages: messages,
                toolResults: results,
                tools: [McpGoalRoutineToolDefinitions.updateGoalTool],
                model: 'qwen3.8-27b-exl3',
              );
            }
          });
        }
        final logged =
            (await (await store.fileForContext(context)).readAsLines())
                .map((line) => (jsonDecode(line) as Map)['request'] as Map)
                .toList();
        const choice = {
          'type': 'function',
          'function': {'name': 'update_goal'},
        };
        expect(bodies.first['tool_choice'], choice);
        expect(logged.first['tool_choice'], choice);
        expect(bodies.last.containsKey('tool_choice'), isFalse);
        expect(logged.last.containsKey('tool_choice'), isFalse);
        final feedback = jsonDecode(recovery.result) as Map;
        expect(feedback['requiredAction'], contains('Call update_goal'));
        expect(feedback['requiredAction'], isNot(contains('file, command')));
      },
    );
  }
}
