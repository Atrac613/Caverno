import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/turn_finalization_delegation_recovery.dart';
import 'package:test/test.dart';

void main() {
  const policy = TurnFinalizationDelegationRecovery();
  const response = 'タスク6を委任します。';
  final spawned = ToolResultInfo(
    id: 'spawn',
    name: 'spawn_subagent',
    arguments: const {},
    result: '{"task_id":"child-1"}',
  );

  test('only an unexecuted parent delegation enters recovery', () {
    expect(
      policy.pending(
        isParentTurn: true,
        response: response,
        completedResults: const [],
      ),
      isTrue,
    );
    for (final input in [
      (isParent: false, results: <ToolResultInfo>[]),
      (isParent: true, results: <ToolResultInfo>[spawned]),
    ]) {
      expect(
        policy.pending(
          isParentTurn: input.isParent,
          response: response,
          completedResults: input.results,
        ),
        isFalse,
      );
    }
  });

  test('recovery offers only spawn_subagent', () {
    final selected = policy.selectTools(
      allTools: const [
        {
          'type': 'function',
          'function': {'name': 'read_file'},
        },
        {
          'type': 'function',
          'function': {'name': 'spawn_subagent'},
        },
      ],
      prefixStable: false,
      pendingDelegation: true,
    );
    expect(selected.forcedCode, 'unexecuted_delegation');
    expect(selected.selectedNames, {'spawn_subagent'});
    expect(selected.tools, hasLength(1));
  });
}
