import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/fenced_tool_arguments_detector.dart';
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

  test('a fenced command fires even when other commands ran this turn', () {
    // Session 6035277f gen-6: several commands ran, then the turn ended on a
    // fenced grep that never issued. The recorded-claim gate would skip that
    // turn; the fence is evidence about one specific unissued call.
    final disposition = policy.evaluate(
      UnexecutedCommandActionRetryInput(
        owner: owner,
        ownerToolResults: const [],
        offersCommandExecution: true,
        hasSuccessfulCommandExecution: true,
        attemptedOwners: const {},
        feedbackId: 'feedback-2',
        fencedToolArguments: const FencedToolArguments(
          command: "grep '^version:' pubspec.yaml",
          rawJson: '{"command":"grep \'^version:\' pubspec.yaml"}',
        ),
      ),
    );

    final plan = disposition.plan;
    expect(plan, isNotNull);
    final feedback = jsonDecode(plan!.feedback.result) as Map<String, dynamic>;
    expect(feedback['code'], 'fenced_tool_arguments_not_a_call');
    expect(feedback['command'], "grep '^version:' pubspec.yaml");
    expect(feedback['required_action'], contains('tool-calling API'));
    expect(feedback['required_action'], contains('code fence'));
  });

  test('a fenced command still needs command tools in the turn', () {
    final disposition = policy.evaluate(
      UnexecutedCommandActionRetryInput(
        owner: owner,
        ownerToolResults: const [],
        offersCommandExecution: false,
        hasSuccessfulCommandExecution: false,
        attemptedOwners: const {},
        feedbackId: 'feedback-3',
        fencedToolArguments: const FencedToolArguments(
          command: 'ls',
          rawJson: '{"command":"ls"}',
        ),
      ),
    );

    expect(
      disposition.noPlanReason,
      UnexecutedCommandActionRetryNoPlanReason.noCommandTools,
    );
  });

  test('a fenced command respects the one-retry-per-turn cap', () {
    final disposition = policy.evaluate(
      UnexecutedCommandActionRetryInput(
        owner: owner,
        ownerToolResults: const [],
        offersCommandExecution: true,
        hasSuccessfulCommandExecution: false,
        attemptedOwners: {policy.ownerKey(owner)},
        feedbackId: 'feedback-4',
        fencedToolArguments: const FencedToolArguments(
          command: 'ls',
          rawJson: '{"command":"ls"}',
        ),
      ),
    );

    expect(
      disposition.noPlanReason,
      UnexecutedCommandActionRetryNoPlanReason.alreadyAttempted,
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
