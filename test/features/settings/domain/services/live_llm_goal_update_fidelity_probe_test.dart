import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_goal_update_fidelity_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts only the exact completion and retains evidence', () async {
    final h = _Harness(
      calls: [
        _call({'completed': true}),
      ],
    );
    final result = await h.run();
    expect(result.id, 'update_goal_fidelity');
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(
      result.summary,
      'The model emitted the exact goal-completion tool call.',
    );
    expect(
      result.details,
      'Observed update_goal with {"completed":true}; it was not executed.',
    );
    expect(result.toolCalls, ['update_goal']);
    expect(result.modelContent, 'model reply');
    expect(result.usage.toJson(), {
      'promptTokens': 11,
      'completionTokens': 3,
      'totalTokens': 14,
    });
    expect(result.metadata, {'toolName': 'update_goal', 'temperature': '0.0'});
    expect(h.events, ['completion', 'metadata']);
  });

  test('keeps prompt bytes', () {
    expect(
      LiveLlmGoalUpdateFidelityProbe.prompt,
      'The active goal is complete. Report that state by calling '
      'update_goal exactly once with completed set to the JSON boolean '
      'literal true, not the string "true" or "True". Do not add '
      'message or blocked_reason, and do not answer in text.',
    );
  });

  test('missing calls fail with explicit details', () async {
    final result = await _Harness(calls: []).run();
    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(
      result.summary,
      'The model did not emit the exact goal-completion tool call.',
    );
    expect(result.details, 'No tool calls were returned.');
    expect(result.toolCalls, isEmpty);
    expect(result.metadata.containsKey('argumentValidationError'), isFalse);
  });

  for (final args in <Map<String, dynamic>>[
    {},
    {'completed': 'true'},
    {'completed': 'True'},
    {'completed': 1},
    {'completed': null},
    {'completed': true, 'unknown': 'value'},
    {'completed': true, 'message': 3},
    {'completed': true, 'blocked_reason': false},
  ]) {
    test('rejects invalid arguments without coercion: $args', () async {
      final result = await _Harness(calls: [_call(args)]).run();
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      final error = result.metadata['argumentValidationError'];
      expect(error, startsWith('Invalid update_goal arguments:'));
      expect(result.details, '$error\nupdate_goal: ${jsonEncode(args)}');
    });
  }

  for (final args in <Map<String, dynamic>>[
    {'completed': false},
    {'completed': true, 'message': 'done'},
    {'completed': true, 'blocked_reason': 'blocked'},
  ]) {
    test('rejects schema-valid nonexact completion: $args', () async {
      final result = await _Harness(calls: [_call(args)]).run();
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.metadata.containsKey('argumentValidationError'), isFalse);
      expect(result.details, 'update_goal: ${jsonEncode(args)}');
    });
  }

  for (final calls in <List<ToolCallInfo>>[
    [
      _call({'completed': 'True'}, name: 'other_tool'),
    ],
    [
      _call({'completed': true}),
      _call({'completed': true}),
    ],
    [
      _call({'completed': 'True'}),
      _call({'completed': true}, name: 'other_tool'),
    ],
  ]) {
    test(
      'rejects wrong or multiple calls without single-call validation: ${calls.map((c) => c.name)}',
      () async {
        final result = await _Harness(calls: calls).run();
        expect(result.status, LiveLlmDiagnosticStatus.failed);
        expect(result.toolCalls, calls.map((c) => c.name).toList());
        expect(result.metadata.containsKey('argumentValidationError'), isFalse);
        expect(
          result.details,
          calls.map((c) => '${c.name}: ${jsonEncode(c.arguments)}').join('\n'),
        );
      },
    );
  }

  test('retains textual tool-call parsing without execution', () async {
    final h = _Harness(calls: [])
      ..content =
          '<tool_call>{"name":"update_goal","arguments":{"completed":true}}</tool_call>';
    expect((await h.run()).status, LiveLlmDiagnosticStatus.passed);
    expect(h.events, ['completion', 'metadata']);
  });

  test('bounds model previews using the shared evidence contract', () async {
    final h = _Harness(
      calls: [
        _call({'completed': true}),
      ],
    )..content = 'x' * 3000;
    final result = await h.run();
    expect(result.modelContent, '${'x' * 2000}...');
    expect(result.modelContent, startsWith('xxxx'));
  });

  test(
    'computed validation evidence overrides colliding request metadata',
    () async {
      final h = _Harness(
        calls: [
          _call({'completed': 'True'}),
        ],
      )..metadata['argumentValidationError'] = 'stale';
      final result = await h.run();
      expect(
        result.metadata['argumentValidationError'],
        contains('received String "True"'),
      );
      expect(h.metadata['argumentValidationError'], 'stale');
    },
  );

  for (final stage in ['completion', 'metadata']) {
    test('propagates $stage failures to service handling', () async {
      final h = _Harness(
        calls: [
          _call({'completed': true}),
        ],
      )..failure = stage;
      await expectLater(h.run(), throwsStateError);
      expect(
        h.events,
        stage == 'completion' ? ['completion'] : ['completion', 'metadata'],
      );
    });
  }
}

ToolCallInfo _call(Map<String, dynamic> args, {String name = 'update_goal'}) =>
    ToolCallInfo(id: 'call-id', name: name, arguments: args);

class _Harness {
  _Harness({required this.calls});
  final List<ToolCallInfo> calls;
  String content = 'model reply';
  String? failure;
  final events = <String>[];
  final metadata = <String, String>{
    'toolName': 'update_goal',
    'temperature': '0.0',
  };
  Future<LiveLlmDiagnosticProbeResult> run() => LiveLlmGoalUpdateFidelityProbe(
    complete: () async {
      events.add('completion');
      if (failure == 'completion') {
        throw StateError('completion');
      }
      return ChatCompletionResult(
        content: content,
        toolCalls: calls,
        finishReason: 'stop',
        usage: const TokenUsage(
          promptTokens: 11,
          completionTokens: 3,
          totalTokens: 14,
        ),
      );
    },
    requestMetadata: () {
      events.add('metadata');
      if (failure == 'metadata') {
        throw StateError('metadata');
      }
      return metadata;
    },
  ).run();
}
