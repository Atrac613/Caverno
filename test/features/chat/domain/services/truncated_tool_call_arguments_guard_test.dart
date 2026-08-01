import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/truncated_tool_call_arguments_guard.dart';

const _guard = TruncatedToolCallArgumentsGuard();

ToolCallInfo _call(String id, {Map<String, dynamic> arguments = const {}}) =>
    ToolCallInfo(id: id, name: 'run_tests', arguments: arguments);

ChatCompletionResult _result(List<ToolCallInfo> toolCalls, String finish) =>
    ChatCompletionResult(
      content: '',
      finishReason: finish,
      toolCalls: toolCalls.isEmpty ? null : toolCalls,
    );

void main() {
  group('casualtyToolCallIds', () {
    test('collects only the calls whose arguments the truncation ate', () {
      final ids = _guard.casualtyToolCallIds(
        _result([
          _call('lost'),
          _call('kept', arguments: {'runner': 'dart'}),
        ], 'length'),
        truncated: true,
      );

      expect(ids, {'lost'});
    });

    test('stays empty when the completion finished normally', () {
      // Empty arguments on a completed generation are a model error, not a lost
      // one, and must reach the ordinary missing-argument path.
      final ids = _guard.casualtyToolCallIds(
        _result([_call('empty')], 'stop'),
        truncated: false,
      );

      expect(ids, isEmpty);
    });

    test('stays empty when a truncated completion carried no tool calls', () {
      expect(
        _guard.casualtyToolCallIds(_result([], 'length'), truncated: true),
        isEmpty,
      );
    });
  });

  group('isCasualty', () {
    test('answers only a listed call that is still argument-less', () {
      const casualties = {'lost'};

      expect(_guard.isCasualty(_call('lost'), casualties), isTrue);
      expect(_guard.isCasualty(_call('other'), casualties), isFalse);
      expect(
        _guard.isCasualty(
          _call('lost', arguments: {'runner': 'dart'}),
          casualties,
        ),
        isFalse,
        reason:
            'a retry that arrived with arguments must execute rather than be '
            'answered with the diagnostic again',
      );
    });
  });

  group('diagnosticFor', () {
    test('names the truncation as the cause and asks for smaller calls', () {
      final result = _guard.diagnosticFor(_call('lost'));
      final payload = jsonDecode(result.result) as Map<String, dynamic>;

      expect(result.isSuccess, isFalse);
      expect(result.toolName, 'run_tests');
      expect(payload['code'], 'tool_call_arguments_truncated');
      expect(payload['error'], contains('finish_reason=length'));
      expect(
        payload['required_action'],
        contains('smaller tool'),
        reason:
            'the model abandons the work unless it is told to re-issue the '
            'call in pieces',
      );
    });
  });
}
