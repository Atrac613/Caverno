import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stalled-diagnostic runner selects the constrained repair scenario', () {
    final runner = File(
      'tool/run_coding_stalled_diagnostic_repair_live_canary.sh',
    ).readAsStringSync();
    final canary = File(
      'tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart',
    ).readAsStringSync();
    final notifier = File(
      'lib/features/chat/presentation/providers/chat_notifier.dart',
    ).readAsStringSync();

    expect(
      runner,
      contains('CAVERNO_CODING_STALLED_DIAGNOSTIC_REPAIR_LIVE_CANARY=1'),
    );
    expect(
      runner,
      contains(
        '--plain-name "live LLM repairs a stable diagnostic plateau with constrained tools"',
      ),
    );
    expect(
      runner,
      contains('--canary-name coding_stalled_diagnostic_repair_live_canary'),
    );
    expect(runner, contains('--surface coding_mvp'));
    expect(canary, contains('todo_cli_stable_repair_probe'));
    expect(canary, contains('<repair_contract>'));
    expect(canary, contains('_containsRepairContractRequest'));
    expect(canary, contains('for (final message in messages.reversed)'));
    expect(canary, contains("message['role'] != 'user'"));
    expect(canary, contains('repairToolRequests.every(_usesOnlyRepairTools)'));
    expect(canary, contains('.where(_advertisesTools)'));
    expect(canary, contains("!names.contains('local_execute_command')"));
    expect(canary, contains('.where(_isTodoVerifierCall)'));
    expect(canary, contains('bool _isTodoVerifierCall(_TodoToolCall call)'));
    expect(canary, contains('return command == _verifyCommand;'));
    expect(canary, contains('stableDiagnosticFailureTurns'));
    expect(canary, contains('disableCodingDiagnosticFeedback: true'));
    expect(canary, contains('_NoopCodingDiagnosticFeedbackProvider'));
    expect(canary, contains('orderedEquals(const [1, 1])'));
    expect(canary, contains('_requestContainsToolResult'));
    expect(canary, contains('ConversationGoalStatus.completed'));
    expect(canary, contains('completedGoal?.completionSummary'));
    expect(canary, contains('_todoTerminalMessage'));
    expect(
      notifier,
      contains('prefixStableToolLoop || allowedToolNames != null'),
    );
    expect(
      notifier,
      contains('stableToolDefinitions: stableLoopToolDefinitions'),
    );
  });
}
