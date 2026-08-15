import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/blocked_production_release_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = BlockedProductionReleaseRetryPolicy();
  final owner = ChatTurnOwner(
    conversationId: 'conv-1',
    interactionGeneration: 7,
  );
  const releaseCommand = 'bash tool/release_ios_macos.sh';

  ToolResultInfo blockedRelease({
    String toolName = 'process_start',
    String command = releaseCommand,
  }) {
    return ToolResultInfo(
      id: 'blocked-1',
      name: toolName,
      arguments: const {},
      result: jsonEncode({
        'ok': false,
        'code': blockedProductionReleaseCode,
        'command': command,
        'assistant_intent': '結合実行を開始します。',
      }),
    );
  }

  BlockedProductionReleaseRetryInput inputWith({
    List<ToolResultInfo>? toolResults,
    List<String> executedCommands = const [],
    bool approvalGranted = true,
    Set<String> attemptedSignatures = const {},
  }) {
    return BlockedProductionReleaseRetryInput(
      owner: owner,
      ownerToolResults: toolResults ?? [blockedRelease()],
      ownerExecutedCommands: executedCommands,
      approvalGranted: approvalGranted,
      attemptedSignatures: attemptedSignatures,
      feedbackId: 'feedback-1',
    );
  }

  test('plans a retry for an approved release that was never issued', () {
    final disposition = policy.evaluate(inputWith());

    final plan = disposition.plan;
    expect(plan, isNotNull);
    expect(plan!.toolName, 'process_start');
    expect(plan.command, releaseCommand);

    final feedback = jsonDecode(plan.feedback.result) as Map<String, dynamic>;
    expect(feedback['code'], 'blocked_production_release_retry_required');
    expect(feedback['command'], releaseCommand);
    expect(feedback['required_action'], contains('process_start'));
    expect(feedback['required_action'], contains(releaseCommand));
  });

  test('keeps the pause when the turn holds no approval evidence', () {
    final disposition = policy.evaluate(inputWith(approvalGranted: false));

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      BlockedProductionReleaseRetryNoPlanReason.approvalMissing,
    );
  });

  test('does not retry once the command actually ran', () {
    final disposition = policy.evaluate(
      inputWith(executedCommands: const [releaseCommand]),
    );

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      BlockedProductionReleaseRetryNoPlanReason.alreadyExecuted,
    );
  });

  test('matches an executed command across whitespace differences', () {
    final disposition = policy.evaluate(
      inputWith(executedCommands: const ['bash   tool/release_ios_macos.sh ']),
    );

    expect(
      disposition.noPlanReason,
      BlockedProductionReleaseRetryNoPlanReason.alreadyExecuted,
    );
  });

  test('treats a different release invocation as still unissued', () {
    final disposition = policy.evaluate(
      inputWith(
        executedCommands: const ['bash tool/release_ios_macos.sh --only ios'],
      ),
    );

    expect(disposition.plan, isNotNull);
  });

  test('retries only once per owner and command', () {
    final signature = policy.retrySignature(
      owner: owner,
      toolName: 'process_start',
      command: releaseCommand,
    );
    final disposition = policy.evaluate(
      inputWith(attemptedSignatures: {signature}),
    );

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      BlockedProductionReleaseRetryNoPlanReason.repeatedSignature,
    );
  });

  test('retries a block carried in from the turn that was blocked', () {
    // The logged failure: gen-6 was blocked, the user approved into gen-7, and
    // gen-7 holds no tool results of its own.
    final laterOwner = ChatTurnOwner(
      conversationId: 'conv-1',
      interactionGeneration: 8,
    );
    final disposition = policy.evaluate(
      BlockedProductionReleaseRetryInput(
        owner: laterOwner,
        ownerToolResults: const [],
        ownerExecutedCommands: const [],
        approvalGranted: true,
        attemptedSignatures: const {},
        feedbackId: 'feedback-2',
        pendingBlockedRelease: const PendingBlockedRelease(
          toolName: 'process_start',
          command: releaseCommand,
        ),
      ),
    );

    expect(disposition.plan?.command, releaseCommand);
    expect(disposition.plan?.owner, laterOwner);
  });

  test('a carried block still needs approval in the retrying turn', () {
    final disposition = policy.evaluate(
      BlockedProductionReleaseRetryInput(
        owner: owner,
        ownerToolResults: const [],
        ownerExecutedCommands: const [],
        approvalGranted: false,
        attemptedSignatures: const {},
        feedbackId: 'feedback-3',
        pendingBlockedRelease: const PendingBlockedRelease(
          toolName: 'process_start',
          command: releaseCommand,
        ),
      ),
    );

    expect(
      disposition.noPlanReason,
      BlockedProductionReleaseRetryNoPlanReason.approvalMissing,
    );
  });

  test('a carried block outranks an older payload in this turn', () {
    final disposition = policy.evaluate(
      BlockedProductionReleaseRetryInput(
        owner: owner,
        ownerToolResults: [
          blockedRelease(command: 'bash tool/release_ios_macos.sh --only ios'),
        ],
        ownerExecutedCommands: const [],
        approvalGranted: true,
        attemptedSignatures: const {},
        feedbackId: 'feedback-4',
        pendingBlockedRelease: const PendingBlockedRelease(
          toolName: 'process_start',
          command: releaseCommand,
        ),
      ),
    );

    expect(disposition.plan?.command, releaseCommand);
  });

  test('ignores turns that never blocked a release', () {
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
      BlockedProductionReleaseRetryNoPlanReason.noBlockedRelease,
    );
  });

  test('ignores a block payload that carries no command', () {
    final disposition = policy.evaluate(
      toolResultsInput(owner, {
        'ok': false,
        'code': blockedProductionReleaseCode,
      }),
    );

    expect(
      disposition.noPlanReason,
      BlockedProductionReleaseRetryNoPlanReason.noBlockedRelease,
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
            result: 'not json at all',
          ),
        ],
      ),
    );

    expect(
      disposition.noPlanReason,
      BlockedProductionReleaseRetryNoPlanReason.noBlockedRelease,
    );
  });

  test('uses the most recent block when a turn blocked twice', () {
    final disposition = policy.evaluate(
      inputWith(
        toolResults: [
          blockedRelease(command: 'bash tool/release_ios_macos.sh --only ios'),
          blockedRelease(command: 'bash tool/release_ios_macos.sh'),
        ],
      ),
    );

    expect(disposition.plan?.command, 'bash tool/release_ios_macos.sh');
  });

  test('does not read the assistant answer for its decision', () {
    // The log this came from ended with "本番リリース実行を開始しました" and no tool
    // call. The policy sees only recorded facts, so a turn that says nothing
    // at all must plan the same retry.
    final silentTurn = policy.evaluate(inputWith());
    final boastfulTurn = policy.evaluate(
      inputWith(
        toolResults: [
          blockedRelease(),
          ToolResultInfo(
            id: 'noise-1',
            name: 'local_execute_command',
            arguments: const {},
            result: jsonEncode({
              'ok': false,
              'code': 'unexecuted_command_action',
              'claimedResponse': '本番リリース実行を開始しました',
            }),
          ),
        ],
      ),
    );

    expect(silentTurn.plan?.command, boastfulTurn.plan?.command);
  });
}

BlockedProductionReleaseRetryInput toolResultsInput(
  ChatTurnOwner owner,
  Map<String, dynamic> payload,
) {
  return BlockedProductionReleaseRetryInput(
    owner: owner,
    ownerToolResults: [
      ToolResultInfo(
        id: 'blocked-partial',
        name: 'process_start',
        arguments: const {},
        result: jsonEncode(payload),
      ),
    ],
    ownerExecutedCommands: const [],
    approvalGranted: true,
    attemptedSignatures: const {},
    feedbackId: 'feedback-1',
  );
}
