import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';

import 'farm_completion_fixture.dart';

/// Model-free wiring check. It must never satisfy the live evidence gate.
final class FarmCompletionPreflight {
  FarmCompletionPreflight(this.fixture);
  final FarmCompletionFixture fixture;
  String stage = 'implementation';
  int index = 0;
  int reviews = 0;
  int serial = 0;
  void beginTurn(String value) {
    stage = value;
    index = 0;
    if (stage == 'review') {
      reviews++;
    }
  }

  String get report => switch (stage) {
    'review' =>
      fixture.scenario == FarmCompletionScenario.reviewRepair && reviews == 1
          ? '[P1] fixture.py fails for negative inputs. Clamp the lower bound to zero.\nPROJECT_TASK_REVIEW_FINDINGS'
          : 'No actionable findings.\nPROJECT_TASK_REVIEW_CLEAN',
    'commit' => 'The reviewed fixture changes were committed.',
    _ =>
      fixture.scenario == FarmCompletionScenario.failedVerification
          ? 'Blocked: required.flag is unavailable. Verification failed.'
          : 'Implemented and verified the fixture.\nPROJECT_TASK_READY_FOR_REVIEW',
  };
  ToolCallInfo call(String name, Map<String, dynamic> arguments) =>
      ToolCallInfo(id: 'fixture-${++serial}', name: name, arguments: arguments);
  ToolCallInfo write(String file, String content) => call('write_file', {
    'path': '${fixture.root.path}/$file',
    'content': content,
  });
  ToolCallInfo verify() => call('local_execute_command', {
    'command': farmCompletionVerify,
    'working_directory': fixture.root.path,
  });
  ChatCompletionResult calls(List<ToolCallInfo> calls) => ChatCompletionResult(
    content: '',
    finishReason: 'tool_calls',
    toolCalls: calls,
  );
  ChatCompletionResult next() {
    final current = index++;
    if (stage == 'review') {
      if (current == 0) {
        return calls([
          call('read_file', {'path': '${fixture.root.path}/fixture.py'}),
          call('read_file', {'path': '${fixture.root.path}/roadmap.md'}),
        ]);
      }
      return ChatCompletionResult(content: report, finishReason: 'stop');
    }
    if (stage == 'commit') {
      return switch (current) {
        0 => calls([
          write('roadmap.md', farmCompletionRoadmap.replaceFirst('[ ]', '[x]')),
        ]),
        1 => calls([
          call('git_execute_command', {
            'command': 'add -- fixture.py roadmap.md',
            'working_directory': fixture.root.path,
          }),
        ]),
        2 => calls([
          call('git_execute_command', {
            'command':
                'commit -m "fix: clamp fixture values" -m "Constrain values to the roadmap interval."',
            'working_directory': fixture.root.path,
          }),
        ]),
        _ => ChatCompletionResult(content: report, finishReason: 'stop'),
      };
    }
    if (current == 0) {
      return calls([
        call('read_file', {'path': '${fixture.root.path}/roadmap.md'}),
        write(
          'fixture.py',
          fixture.scenario == FarmCompletionScenario.reviewRepair &&
                  stage == 'implementation'
              ? farmCompletionBadCode
              : farmCompletionGoodCode,
        ),
        verify(),
      ]);
    }
    if (current == 1) {
      return calls([
        call(
          'update_goal',
          fixture.scenario == FarmCompletionScenario.failedVerification
              ? {
                  'completed': false,
                  'blocked_reason':
                      'External prerequisite required.flag is missing.',
                }
              : {'completed': true},
        ),
      ]);
    }
    return ChatCompletionResult(content: report, finishReason: 'stop');
  }

  ChatCompletionResult memory() => ChatCompletionResult(
    content: jsonEncode({
      'summary': 'Synthetic fixture turn processed.',
      'open_loops': [],
      'profile': {'persona': [], 'preferences': [], 'do_not': []},
      'memories': [],
    }),
    finishReason: 'stop',
  );
}
