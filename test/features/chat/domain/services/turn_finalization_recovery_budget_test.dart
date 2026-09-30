import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/turn_finalization_recovery_budget.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolResultInfo verified(
    String id, {
    String command = 'python -m pytest test.py',
    int failed = 0,
  }) => ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: {'command': command, 'working_directory': '/project'},
    result: '{}',
    outcome: ToolOutcome(
      exitCode: 0,
      testOutcome: ToolTestOutcome(
        passedCount: 6,
        failedCount: failed,
        skippedCount: 0,
        command: command,
      ),
    ),
  );
  test('requests another status only after new mechanical progress', () {
    final budget = TurnFinalizationRecoveryBudget();
    expect(budget.claim(1, structuredTask: true, results: []), isTrue);
    expect(
      budget.claim(
        1,
        structuredTask: true,
        results: [
          ToolResultInfo(
            id: 'read',
            name: 'read_file',
            arguments: {},
            result: 'content',
          ),
        ],
      ),
      isFalse,
    );
    expect(
      budget.claim(1, structuredTask: true, results: [verified('first')]),
      isTrue,
    );
    expect(
      budget.claim(
        1,
        structuredTask: true,
        results: [
          verified('repeat'),
          verified(
            'wrapper',
            command:
                'cd /project && .venv/bin/python -m pytest test.py 2>&1 | tail -30',
          ),
        ],
      ),
      isFalse,
    );
    expect(
      budget.claim(
        1,
        structuredTask: true,
        results: [
          verified('first'),
          verified('other', command: 'python -m pytest other.py'),
        ],
      ),
      isTrue,
    );
    expect(
      budget.claim(
        1,
        structuredTask: true,
        results: [verified('last', command: 'python -m pytest third.py')],
      ),
      isFalse,
    );
  });
  test('failed tests are not mechanical progress', () {
    final budget = TurnFinalizationRecoveryBudget();
    expect(budget.claim(1, structuredTask: true, results: []), isTrue);
    expect(
      budget.claim(
        1,
        structuredTask: true,
        results: [verified('failed', failed: 1)],
      ),
      isFalse,
    );
  });
  test(
    'mutation hashes permit recovery and owner disposal resets its budget',
    () {
      final budget = TurnFinalizationRecoveryBudget();
      expect(budget.claim(1, structuredTask: true, results: []), isTrue);
      final changed = ToolResultInfo(
        id: 'write',
        name: 'write_file',
        arguments: {},
        result: '{}',
        outcome: const ToolOutcome(
          fileMutations: [
            ToolFileMutation(
              path: '/project/src.py',
              changed: true,
              contentHash: 'new',
            ),
          ],
        ),
      );
      expect(budget.claim(1, structuredTask: true, results: [changed]), isTrue);
      expect(
        budget.claim(1, structuredTask: true, results: [changed]),
        isFalse,
      );
      budget.remove(1);
      expect(budget.claim(1, structuredTask: true, results: [changed]), isTrue);
    },
  );
  test('legacy turns retain one recovery per generation', () {
    final budget = TurnFinalizationRecoveryBudget();
    expect(budget.claim(1, structuredTask: false, results: []), isTrue);
    expect(
      budget.claim(1, structuredTask: false, results: [verified('new')]),
      isFalse,
    );
    budget.clear();
    expect(budget.claim(1, structuredTask: false, results: []), isTrue);
  });
}
