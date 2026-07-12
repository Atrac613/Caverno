import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Expense tracker runner selects the short-prompt live scenario', () {
    final runner = File(
      'tool/run_coding_expense_tracker_live_canary.sh',
    ).readAsStringSync();
    final canary = File(
      'tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart',
    ).readAsStringSync();

    expect(runner, contains('CAVERNO_CODING_EXPENSE_TRACKER_LIVE_CANARY=1'));
    expect(runner, contains('expense_tracker.md'));
    expect(
      runner,
      contains('--canary-name coding_expense_tracker_live_canary'),
    );
    expect(runner, contains('--surface coding_mvp'));
    expect(
      runner,
      contains(
        '--plain-name "live LLM assembles the expense_tracker.md MVP from a short prompt"',
      ),
    );
    expect(canary, contains('dart run tool/verify_expense_tracker.dart'));
    expect(canary, contains('expense_tracker_baseline_summary_failed'));
    expect(canary, contains('expense_tracker_empty_list_failed'));
    expect(canary, contains('expense_tracker_empty_summary_failed'));
    expect(canary, contains('expense_tracker_invalid_amount_mutated_state'));
    expect(canary, contains('expense_tracker_decimal_or_total_failed'));
    expect(canary, contains('expense_tracker_csv_quoting_failed'));
    expect(canary, contains('expense_tracker_persistence_failed'));
  });
}
