import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_tool_result_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves prompt, envelopes, allowlist and final-only usage', () async {
    final h = _Harness();
    final result = await h.run();
    expect(result.id, 'tool_result_integration');
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(
      result.summary,
      'The model integrated the tool result into its final answer.',
    );
    expect(
      result.details,
      'Expected today: 2026-10-08\nExpected timezone: Asia/Tokyo',
    );
    expect(result.modelContent, _answer);
    expect(result.toolCalls, ['get_current_datetime']);
    expect(result.usage.totalTokens, 7);
    expect(h.executions, ['get_current_datetime']);
    expect(
      h.prompt,
      'Call get_current_datetime. After the tool result arrives, return '
      'JSON with probe="datetime_tool_result", marker="CAVERNO_TOOL_RESULT_OK", '
      'today copied from relative_dates.today, and timezone copied from the tool result.',
    );
    expect(h.envelope!.id, 'call-id');
    expect(h.envelope!.arguments, {'format': 'json'});
    expect(h.envelope!.result, _toolJson);
  });

  test('uses fallback ID and accepts a plain-text marker', () async {
    final h = _Harness()..initial = _reply('', calls: [_call(id: '')]);
    await h.run();
    expect(h.envelope!.id, 'diagnostic-datetime-call');
  });

  test(
    'executes only the first datetime call among unsolicited calls',
    () async {
      final h = _Harness()
        ..initial = _reply(
          '',
          calls: [
            _call(name: 'write_file'),
            _call(),
            _call(id: 'second'),
          ],
        );
      expect((await h.run()).status, LiveLlmDiagnosticStatus.passed);
      expect(h.executions, ['get_current_datetime']);
      expect(h.envelope!.id, 'call-id');
    },
  );

  test('missing datetime fails without executing other tools', () async {
    final h = _Harness()
      ..initial = _reply(
        'No datetime',
        calls: [_call(name: 'write_file')],
        tokens: 99,
      );
    final result = await h.run();
    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.summary, 'The model did not request the datetime tool.');
    expect(result.toolCalls, ['write_file']);
    expect(result.modelContent, 'No datetime');
    expect(result.usage.totalTokens, 99);
    expect(h.executions, isEmpty);
    expect(h.envelope, isNull);
  });

  for (final error in [null, 'explicit failure']) {
    test('execution failure preserves error fallback $error', () async {
      final h = _Harness()
        ..execution = McpToolResult(
          toolName: 'get_current_datetime',
          result: 'raw failure',
          isSuccess: false,
          errorMessage: error,
        );
      final result = await h.run();
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, 'The built-in datetime tool failed.');
      expect(result.details, error ?? 'raw failure');
      expect(result.usage.totalTokens, 99);
      expect(h.envelope, isNull);
    });
  }

  for (final content in [
    'no marker 2026-10-08 Asia/Tokyo',
    'CAVERNO_TOOL_RESULT_OK Asia/Tokyo',
    'CAVERNO_TOOL_RESULT_OK 2026-10-08',
  ]) {
    test('warns when an expected field is missing: $content', () async {
      final h = _Harness()..finalReply = _reply(content);
      final result = await h.run();
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(
        result.summary,
        'The model did not clearly copy all tool-result fields.',
      );
    });
  }

  test('accepts JSON marker and trims only surrounding whitespace', () async {
    final h = _Harness()
      ..finalReply = _reply(
        '  {"marker":"CAVERNO_TOOL_RESULT_OK","today":"2026-10-08","timezone":"Asia/Tokyo"} \n',
      );
    final result = await h.run();
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.modelContent, h.finalReply.content.trim());
  });

  for (final payload in [
    '{}',
    'not JSON',
    '{"relative_dates":false}',
    '{"timezone":null}',
  ]) {
    test('retains optional-field scoring for $payload', () async {
      final h = _Harness()
        ..execution = McpToolResult(
          toolName: 'get_current_datetime',
          result: payload,
          isSuccess: true,
        )
        ..finalReply = _reply('CAVERNO_TOOL_RESULT_OK');
      final result = await h.run();
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.details, isEmpty);
    });
  }

  test('warns on another tool without executing it', () async {
    final h = _Harness()
      ..finalReply = _reply(_answer, calls: [_call(name: 'write_file')]);
    final result = await h.run();
    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(
      result.summary,
      'The model requested another tool instead of completing the answer.',
    );
    expect(
      result.details,
      contains('Unexpected follow-up tool calls: write_file'),
    );
    expect(result.toolCalls, ['get_current_datetime', 'write_file']);
    expect(h.executions, ['get_current_datetime']);
  });

  test('empty answer records finish reason', () async {
    final h = _Harness()
      ..finalReply = ChatCompletionResult(
        content: '  ',
        finishReason: 'length',
      );
    final result = await h.run();
    expect(
      result.summary,
      'The model returned no final answer after the tool result.',
    );
    expect(result.details, endsWith('Finish reason: length'));
  });

  for (final stage in ['initial', 'execution', 'follow-up']) {
    test('propagates $stage errors to service handling', () async {
      final h = _Harness()..failure = stage;
      await expectLater(h.run(), throwsStateError);
    });
  }
  for (final payload in ['{"relative_dates":{"today":3}}', '{"timezone":3}']) {
    test('preserves invalid field type failure for $payload', () async {
      final h = _Harness()
        ..execution = McpToolResult(
          toolName: 'get_current_datetime',
          result: payload,
          isSuccess: true,
        );
      await expectLater(h.run(), throwsA(isA<TypeError>()));
      expect(h.envelope, isNull);
    });
  }
}

const _toolJson =
    '{"relative_dates":{"today":"2026-10-08"},"timezone":"Asia/Tokyo"}';
const _answer = 'CAVERNO_TOOL_RESULT_OK 2026-10-08 Asia/Tokyo';
ToolCallInfo _call({
  String id = 'call-id',
  String name = 'get_current_datetime',
}) => ToolCallInfo(id: id, name: name, arguments: {'format': 'json'});
ChatCompletionResult _reply(
  String content, {
  List<ToolCallInfo>? calls,
  int tokens = 7,
}) => ChatCompletionResult(
  content: content,
  toolCalls: calls,
  finishReason: 'stop',
  usage: TokenUsage(
    promptTokens: tokens,
    completionTokens: 0,
    totalTokens: tokens,
  ),
);

class _Harness {
  ChatCompletionResult initial = _reply('', calls: [_call()], tokens: 99);
  ChatCompletionResult finalReply = _reply(_answer);
  McpToolResult execution = const McpToolResult(
    toolName: 'get_current_datetime',
    result: _toolJson,
    isSuccess: true,
  );
  String? failure;
  String? prompt;
  ToolResultInfo? envelope;
  List<Message>? initialMessages;
  final executions = <String>[];
  final dateTool = <String, dynamic>{
    'type': 'function',
    'function': {'name': 'get_current_datetime'},
  };

  Future<LiveLlmDiagnosticProbeResult> run() =>
      LiveLlmToolResultProbe(
        messages: (user) {
          prompt = user;
          return [
            Message(
              id: 'prompt',
              role: MessageRole.user,
              content: user,
              timestamp: DateTime(2026),
            ),
          ];
        },
        complete: ({required messages, required tools}) async {
          expect(tools, [dateTool]);
          initialMessages = messages;
          if (failure == 'initial') throw StateError('initial');
          return initial;
        },
        followUp:
            ({required messages, required toolResults, required tools}) async {
              expect(identical(messages, initialMessages), isTrue);
              expect(tools, isEmpty);
              envelope = toolResults.single;
              expect(envelope!.name, 'get_current_datetime');
              if (failure == 'follow-up') throw StateError('follow-up');
              return finalReply;
            },
      ).run(
        dateTool: dateTool,
        execute: ({required name, required arguments}) async {
          executions.add(name);
          expect(arguments, {'format': 'json'});
          if (failure == 'execution') throw StateError('execution');
          return execution;
        },
      );
}
