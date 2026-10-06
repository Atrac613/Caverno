import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/post_saved_validation_tool_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('advertises only parent acceptance after validation', () {
    const policy = PostSavedValidationToolPolicy();
    final definitions = <Map<String, dynamic>>[
      {
        'function': {'name': 'read_file'},
      },
      {
        'function': {'name': 'accept_task'},
      },
      {
        'function': {'name': 'write_file'},
      },
    ];

    expect(policy.followUpDefinitions(definitions, isParentTurn: true), [
      {
        'function': {'name': 'accept_task'},
      },
    ]);
    expect(
      policy.followUpDefinitions(definitions, isParentTurn: false),
      isEmpty,
    );
  });

  test('only the parent may attempt acceptance after validation', () {
    const policy = PostSavedValidationToolPolicy();
    final acceptance = ToolCallInfo(
      id: 'accept',
      name: 'accept_task',
      arguments: {
        'workflow_task_id': 'task-cli',
        'rationale': 'Validation passed.',
      },
    );
    final rewrite = ToolCallInfo(
      id: 'rewrite',
      name: 'write_file',
      arguments: {'path': 'bin/todo_cli.dart', 'content': 'rewrite'},
    );

    expect(policy.allows(acceptance, isParentTurn: true), isTrue);
    expect(policy.allows(acceptance, isParentTurn: false), isFalse);
    expect(policy.allows(rewrite, isParentTurn: true), isFalse);
  });

  test('parent may delegate only after acceptance reports no child result', () {
    const policy = PostSavedValidationToolPolicy();
    final delegation = ToolCallInfo(
      id: 'delegate',
      name: 'spawn_subagent',
      arguments: {'workflow_task_id': 'task-cli'},
    );
    final missingChild = ToolResultInfo(
      id: 'accept',
      name: 'accept_task',
      arguments: const {},
      result: '{"ok":false,"code":"acceptance_no_delegated_result"}',
    );
    final otherRefusal = ToolResultInfo(
      id: 'accept-other',
      name: 'accept_task',
      arguments: const {},
      result: '{"ok":false,"code":"acceptance_levels_outstanding"}',
    );

    expect(policy.allows(delegation, isParentTurn: true), isFalse);
    expect(
      policy.allows(
        delegation,
        isParentTurn: false,
        latestResults: [missingChild],
      ),
      isFalse,
    );
    expect(
      policy.allows(
        delegation,
        isParentTurn: true,
        latestResults: [otherRefusal],
      ),
      isFalse,
    );
    expect(
      policy.allows(
        delegation,
        isParentTurn: true,
        latestResults: [missingChild],
      ),
      isTrue,
    );
  });
}
