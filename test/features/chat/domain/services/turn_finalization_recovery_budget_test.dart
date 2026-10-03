import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/duplicate_tool_result_reuse_payload.dart';
import 'package:caverno/features/chat/domain/services/turn_finalization_recovery_budget.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolResultInfo verified(
    String id, {
    String command = 'python -m pytest test.py',
    int failed = 0,
    bool directoryInResult = false,
  }) => ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: {
      'command': command,
      if (!directoryInResult) 'working_directory': '/project',
    },
    result: jsonEncode({
      if (directoryInResult) 'working_directory': '/project',
    }),
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
  for (final directoryInResult in [false, true]) {
    test(
      'reporting changes do not renew implementation recovery: $directoryInResult',
      () {
        final budget = TurnFinalizationRecoveryBudget();
        final verbose = verified(
          'verbose',
          command: 'python -m pytest test.py -v',
          directoryInResult: directoryInResult,
        );
        final quiet = verified(
          'quiet',
          command: '.venv/bin/python -m pytest test.py -q',
          directoryInResult: directoryInResult,
        );
        expect(
          budget.claim(1, structuredTask: true, results: [verbose]),
          isTrue,
        );
        expect(
          budget.claim(1, structuredTask: true, results: [verbose, quiet]),
          isFalse,
        );
      },
    );
  }
  test('a failed recovery verification permits only one status report', () {
    final budget = TurnFinalizationRecoveryBudget();
    ToolResultInfo failed(String id) => ToolResultInfo(
      id: id,
      name: 'local_execute_command',
      arguments: const {'command': 'python watcher.py --dry-run'},
      result: '{}',
      outcome: const ToolOutcome(exitCode: 120),
    );
    final first = failed('first');
    final results = [first, failed('retry')];
    expect(budget.needsVerificationStatus(1, results), isFalse);
    expect(budget.claim(1, structuredTask: true, results: [first]), isTrue);
    expect(budget.needsVerificationStatus(1, results), isTrue);
    expect(budget.claim(1, structuredTask: true, results: results), isFalse);
    expect(
      budget.claim(1, structuredTask: true, results: results, statusOnly: true),
      isTrue,
    );
    expect(budget.needsVerificationStatus(1, results), isFalse);
    expect(
      budget.claim(1, structuredTask: true, results: results, statusOnly: true),
      isFalse,
    );
    expect(budget.claim(1, structuredTask: true, results: results), isFalse);
    final another = [...results, failed('another')];
    expect(
      budget.claim(1, structuredTask: true, results: another, statusOnly: true),
      isTrue,
    );
    expect(
      budget.claim(
        1,
        structuredTask: true,
        results: [...another, failed('over-cap')],
        statusOnly: true,
      ),
      isFalse,
    );
    budget.remove(1);
    expect(budget.needsVerificationStatus(1, another), isFalse);
    expect(budget.claim(1, structuredTask: true, results: another), isTrue);
    budget.clear();
    expect(budget.needsVerificationStatus(1, [...another, first]), isFalse);
  });
  test(
    'a passing recovery closes status without renewing the same evidence',
    () {
      final budget = TurnFinalizationRecoveryBudget();
      expect(budget.claim(1, structuredTask: true, results: []), isTrue);
      final results = [verified('passed')];
      expect(budget.needsVerificationStatus(1, results), isTrue);
      expect(
        budget.claim(
          1,
          structuredTask: true,
          results: results,
          statusOnly: true,
        ),
        isTrue,
      );
      expect(budget.claim(1, structuredTask: true, results: results), isFalse);
    },
  );
  for (final variant in [
    'inspection',
    'unknown outcome',
    'running',
    'reused',
    'replayed result',
  ]) {
    test('does not renew terminal status for $variant', () {
      final budget = TurnFinalizationRecoveryBudget();
      final first = verified('first');
      expect(budget.claim(1, structuredTask: true, results: [first]), isTrue);
      final candidate = ToolResultInfo(
        id: variant == 'reused' ? first.id : variant,
        name: 'local_execute_command',
        arguments: {
          'command': variant == 'inspection'
              ? 'python3 -m pip show pytest'
              : 'python3 -m pytest test.py',
          'working_directory': '/project',
        },
        result: variant == 'replayed result'
            ? DuplicateToolResultReusePayload().build(
                first,
                currentToolCallId: variant,
              )
            : '{}',
        outcome: variant == 'replayed result'
            ? first.outcome
            : variant == 'unknown outcome'
            ? null
            : ToolOutcome(
                exitCode: variant == 'running' ? 0 : 120,
                processState: variant == 'running'
                    ? ToolProcessState.running
                    : null,
              ),
      );
      final results = [first, candidate];
      expect(budget.needsVerificationStatus(1, results), isFalse);
      expect(budget.needsVerificationStatus(2, results), isFalse);
      expect(
        budget.claim(
          1,
          structuredTask: true,
          results: results,
          statusOnly: true,
        ),
        isFalse,
      );
      if (variant == 'replayed result') {
        expect(
          budget.claim(1, structuredTask: true, results: results),
          isFalse,
        );
      }
    });
  }
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
