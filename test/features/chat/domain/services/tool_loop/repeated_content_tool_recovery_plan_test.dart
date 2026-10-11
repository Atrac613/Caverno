import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/repeated_content_tool_recovery_plan.dart';
import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallData call(String name) =>
    ToolCallData(name: name, arguments: const {'path': 'README.md'});
ToolResultInfo result(String name) => ToolResultInfo(
  id: 'fixture',
  name: name,
  arguments: const {},
  result: 'ok',
);

void main() {
  test('empty repeats never look up evidence', () {
    expect(
      RepeatedContentToolRecoveryPlan.assess(
        [],
        previousSuccessfulResult: (_) => throw StateError('no lookup'),
      ),
      isNull,
    );
  });
  test('selects first reusable repeat and stops looking up later calls', () {
    final lookedUp = <String>[];
    final plan = RepeatedContentToolRecoveryPlan.assess(
      [call('first'), call('second'), call('third')],
      previousSuccessfulResult: (call) {
        lookedUp.add(call.name);
        return call.name == 'second' ? result('previous_tool') : null;
      },
    )!;
    expect(lookedUp, ['first', 'second']);
    expect(
      plan.logMessage,
      '[ContentTool] Repeated successful tool call suppressed for second: {path: README.md}',
    );
    expect(
      plan.replacementContent,
      'The previous_tool tool already ran with the same arguments. I will use the previous tool result instead of repeating the call.',
    );
  });
  test(
    'first successful lookup wins even when later calls could be reused',
    () {
      final lookedUp = <String>[];
      final plan = RepeatedContentToolRecoveryPlan.assess(
        [call('first'), call('second')],
        previousSuccessfulResult: (call) {
          lookedUp.add(call.name);
          return result(call.name);
        },
      )!;
      expect(lookedUp, ['first']);
      expect(plan.replacementContent, startsWith('The first tool already ran'));
    },
  );
  test(
    'absent evidence leaves message unchanged and preserves lookup order',
    () {
      final lookedUp = <String>[];
      expect(
        RepeatedContentToolRecoveryPlan.assess(
          [call('first'), call('second')],
          previousSuccessfulResult: (call) {
            lookedUp.add(call.name);
            return null;
          },
        ),
        isNull,
      );
      expect(lookedUp, ['first', 'second']);
    },
  );
  test('lookup failure retains propagation', () {
    final failure = StateError('evidence lookup');
    expect(
      () => RepeatedContentToolRecoveryPlan.assess([
        call('first'),
      ], previousSuccessfulResult: (_) => throw failure),
      throwsA(same(failure)),
    );
  });
}
