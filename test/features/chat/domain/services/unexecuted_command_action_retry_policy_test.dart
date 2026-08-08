import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/unexecuted_command_action_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = UnexecutedCommandActionRetryPolicy();
  final owner = ChatTurnOwner(
    conversationId: 'conv-1',
    interactionGeneration: 7,
  );

  ToolResultInfo unexecutedClaim({String claimed = 'dry-run が成功しました'}) {
    return ToolResultInfo(
      id: 'unexecuted-1',
      name: 'local_execute_command',
      arguments: const {},
      result: jsonEncode({
        'ok': false,
        'code': unexecutedCommandActionCode,
        'claimedResponse': claimed,
      }),
    );
  }

  UnexecutedCommandActionRetryInput inputWith({
    List<ToolResultInfo>? toolResults,
    bool offersCommandExecution = true,
    bool hasSuccessfulCommandExecution = false,
    Set<String> attemptedOwners = const {},
  }) {
    return UnexecutedCommandActionRetryInput(
      owner: owner,
      ownerToolResults: toolResults ?? [unexecutedClaim()],
      offersCommandExecution: offersCommandExecution,
      hasSuccessfulCommandExecution: hasSuccessfulCommandExecution,
      attemptedOwners: attemptedOwners,
      feedbackId: 'feedback-1',
    );
  }

  test('plans a retry for a described run with no command evidence', () {
    final disposition = policy.evaluate(inputWith());

    final plan = disposition.plan;
    expect(plan, isNotNull);
    final feedback = jsonDecode(plan!.feedback.result) as Map<String, dynamic>;
    expect(feedback['code'], 'unexecuted_command_action_retry_required');
    // The retry must leave a way out that is not another fabricated run.
    expect(feedback['required_action'], contains('issue the tool call'));
    expect(feedback['required_action'], contains('cannot be issued'));
    expect(feedback['required_action'], contains('Do not describe a run'));
  });

  test('does nothing when the turn offers no command tools', () {
    final disposition = policy.evaluate(
      inputWith(offersCommandExecution: false),
    );

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      UnexecutedCommandActionRetryNoPlanReason.noCommandTools,
    );
  });

  test('leaves a turn alone once a command actually ran', () {
    final disposition = policy.evaluate(
      inputWith(hasSuccessfulCommandExecution: true),
    );

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      UnexecutedCommandActionRetryNoPlanReason.commandAlreadyExecuted,
    );
  });

  test('retries at most once per turn', () {
    final disposition = policy.evaluate(
      inputWith(attemptedOwners: {policy.ownerKey(owner)}),
    );

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      UnexecutedCommandActionRetryNoPlanReason.alreadyAttempted,
    );
  });

  test('a later turn in the same conversation gets its own attempt', () {
    final laterOwner = ChatTurnOwner(
      conversationId: 'conv-1',
      interactionGeneration: 8,
    );

    expect(policy.ownerKey(laterOwner), isNot(policy.ownerKey(owner)));
  });

  test('ignores turns with no unexecuted claim recorded', () {
    final disposition = policy.evaluate(
      inputWith(
        toolResults: [
          ToolResultInfo(
            id: 'ok-1',
            name: 'local_execute_command',
            arguments: const {},
            result: jsonEncode({'exit_code': 0, 'stdout': 'done'}),
          ),
        ],
      ),
    );

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      UnexecutedCommandActionRetryNoPlanReason.noUnexecutedClaim,
    );
  });

  test('ignores non-JSON tool results without throwing', () {
    final disposition = policy.evaluate(
      inputWith(
        toolResults: [
          ToolResultInfo(
            id: 'raw-1',
            name: 'local_execute_command',
            arguments: const {},
            result: 'not json',
          ),
        ],
      ),
    );

    expect(
      disposition.noPlanReason,
      UnexecutedCommandActionRetryNoPlanReason.noUnexecutedClaim,
    );
  });

  test('does not read the claim text when deciding', () {
    // The corpus shape: one answer invents a results table, another simply
    // says it started. Both are the same fact — no command ran — so both must
    // plan the same retry.
    final tablePlan = policy
        .evaluate(
          inputWith(
            toolResults: [
              unexecutedClaim(claimed: '| Status | success | 17.1 MB |'),
            ],
          ),
        )
        .plan;
    final terserPlan = policy
        .evaluate(
          inputWith(toolResults: [unexecutedClaim(claimed: '開始しました')]),
        )
        .plan;

    expect(tablePlan, isNotNull);
    expect(terserPlan, isNotNull);
    expect(tablePlan!.feedback.result, terserPlan!.feedback.result);
  });
}
