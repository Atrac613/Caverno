import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/strict_tool_choice_policy.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/presentation/providers/coding_continuation_recovery_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tools = [
    {
      'type': 'function',
      'function': {'name': 'update_goal'},
    },
  ];
  ChatCompletionResult response(String name, {dynamic completed = false}) =>
      ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: name,
            name: name,
            arguments: {'completed': completed},
          ),
        ],
      );
  for (final variant in [
    'unoffered',
    'missing',
    'invalid argument',
    'mixed',
    'duplicate',
    'valid',
  ]) {
    test(
      'recovers $variant status response using only the control protocol',
      () async {
        final feedbacks = <List<ToolResultInfo>>[];
        final prompts = <List<Message>>[];
        final result = await CodingContinuationRecoveryRequest.run(
          candidateResponse: 'Status',
          recoveryCode: 'structured_coding_task_status',
          forcedPrompt: 'Call update_goal.',
          generation: 1,
          tools: tools,
          executedResults: [],
          buildBaseMessages: (_) => [],
          carryResults: (feedback) => [feedback],
          isCurrent: () => true,
          create:
              ({
                required logLabel,
                required interactionGeneration,
                required buildMessages,
                required toolResults,
                required assistantContent,
                required tools,
              }) async {
                feedbacks.add(toolResults);
                prompts.add(buildMessages(false));
                expect(
                  StrictToolChoicePolicy.openAiToolChoice(
                    tools,
                    toolResults: toolResults,
                  ),
                  {
                    'type': 'function',
                    'function': {'name': 'update_goal'},
                  },
                );
                if (feedbacks.length > 1 || variant == 'valid') {
                  return response('update_goal');
                }
                return switch (variant) {
                  'unoffered' => response('read_file'),
                  'invalid argument' => response(
                    'update_goal',
                    completed: 'false',
                  ),
                  'mixed' || 'duplicate' => ChatCompletionResult(
                    content: '',
                    finishReason: 'tool_calls',
                    toolCalls: [
                      ...response('update_goal').toolCalls!,
                      ...response(
                        variant == 'mixed' ? 'write_file' : 'update_goal',
                      ).toolCalls!,
                    ],
                  ),
                  _ => ChatCompletionResult(
                    content: 'Done',
                    finishReason: 'stop',
                  ),
                };
              },
        );
        expect(result?.toolCalls?.single.name, 'update_goal');
        expect(feedbacks, hasLength(variant == 'valid' ? 1 : 2));
        if (variant != 'valid') {
          final payload =
              jsonDecode(feedbacks.last.single.result) as Map<String, dynamic>;
          expect(payload['protocol_violation']['executed'], isFalse);
          expect(payload['protocol_violation']['allowed_tools'], [
            'update_goal',
          ]);
          expect(
            prompts.last.last.content,
            contains('structured_task_status_protocol_violation'),
          );
        }
      },
    );
  }
  test(
    'bounds repeated unoffered calls and never returns them for dispatch',
    () async {
      var requests = 0;
      final result = await CodingContinuationRecoveryRequest.run(
        candidateResponse: 'Status',
        recoveryCode: 'structured_coding_task_status',
        forcedPrompt: 'Call update_goal.',
        generation: 1,
        tools: tools,
        executedResults: [],
        buildBaseMessages: (_) => [],
        carryResults: (feedback) => [feedback],
        isCurrent: () => true,
        create:
            ({
              required logLabel,
              required interactionGeneration,
              required buildMessages,
              required toolResults,
              required assistantContent,
              required tools,
            }) async {
              requests++;
              return response('write_file');
            },
      );
      expect(result, isNotNull);
      expect(result!.hasToolCalls, isFalse);
      expect(requests, 2);
    },
  );
  test('does not retry a cancelled owner or a legacy recovery', () async {
    for (final cancelled in [true, false]) {
      var current = true;
      var requests = 0;
      final result = await CodingContinuationRecoveryRequest.run(
        candidateResponse: 'Status',
        recoveryCode: cancelled
            ? 'structured_coding_task_status'
            : 'coding_future_action',
        forcedPrompt: null,
        generation: 1,
        tools: tools,
        executedResults: [],
        buildBaseMessages: (_) => [],
        carryResults: (feedback) => [feedback],
        isCurrent: () => current,
        create:
            ({
              required logLabel,
              required interactionGeneration,
              required buildMessages,
              required toolResults,
              required assistantContent,
              required tools,
            }) async {
              requests++;
              current = !cancelled;
              return response('read_file');
            },
      );
      expect(requests, 1);
      expect(result?.toolCalls?.single.name, cancelled ? isNull : 'read_file');
    }
  });

  test(
    'states captured writes and verification in the status request',
    () async {
      // Session 1d76c878: the carried tail held four reads, so the model set
      // out to verify instead of reporting and the turn recorded no status.
      List<ToolResultInfo>? sent;
      await CodingContinuationRecoveryRequest.run(
        candidateResponse: 'Done',
        recoveryCode: 'structured_coding_task_status',
        forcedPrompt: 'Call update_goal.',
        generation: 1,
        tools: tools,
        executedResults: [
          ToolResultInfo(
            id: 'w',
            name: 'write_file',
            arguments: {'path': '/p/test_state.py'},
            result: '{"path":"/p/test_state.py","created":true}',
          ),
          ToolResultInfo(
            id: 'c',
            name: 'local_execute_command',
            arguments: {'command': 'pytest -q'},
            result: '{"exit_code":0,"stdout":"53 passed"}',
          ),
        ],
        buildBaseMessages: (_) => [],
        carryResults: (feedback) => [feedback],
        isCurrent: () => true,
        create:
            ({
              required logLabel,
              required interactionGeneration,
              required buildMessages,
              required toolResults,
              required assistantContent,
              required tools,
            }) async {
              sent = toolResults;
              return response('update_goal', completed: true);
            },
      );

      final payload = jsonDecode(sent!.single.result) as Map<String, dynamic>;
      final captured = payload['capturedEvidence'] as Map<String, dynamic>;
      expect(captured['fileChanges'], ['/p/test_state.py']);
      expect((captured['latestExecution'] as Map)['succeeded'], isTrue);
      expect(captured['latestExecutionFollowsLatestChange'], isTrue);
    },
  );

  test('passes one verification call through while the gap is open', () async {
    // Session 02fec5c8: the model answered both status requests with the
    // verification its last edit still needed, and both were refused.
    var requests = 0;
    final result = await CodingContinuationRecoveryRequest.run(
      candidateResponse: 'Status',
      recoveryCode: 'structured_coding_task_status',
      forcedPrompt: 'Verify, then call update_goal.',
      generation: 1,
      tools: const [
        ...tools,
        {
          'type': 'function',
          'function': {'name': 'local_execute_command'},
        },
      ],
      executedResults: [],
      buildBaseMessages: (_) => [],
      carryResults: (feedback) => [feedback],
      isCurrent: () => true,
      create:
          ({
            required logLabel,
            required interactionGeneration,
            required buildMessages,
            required toolResults,
            required assistantContent,
            required tools,
          }) async {
            requests++;
            return ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'verify',
                  name: 'local_execute_command',
                  arguments: const {'command': '.venv/bin/python -m pytest -q'},
                ),
              ],
            );
          },
    );
    expect(requests, 1);
    expect(result?.toolCalls?.single.name, 'local_execute_command');
  });
}
