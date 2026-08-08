import 'dart:convert';

import '../entities/chat_turn_owner.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: blocked-production-release-retry-policy

/// The structured code the release guard writes when it blocks a production
/// release for missing user approval.
const String blockedProductionReleaseCode =
    'production_release_explicit_approval_required';

/// A release the guard blocked, carried forward across turns.
///
/// Approval almost never arrives in the turn that was blocked: the assistant
/// asks, the turn ends, and the user answers into the next one. A conversation
/// that only remembered the block for one turn would forget it exactly when the
/// approval landed.
final class PendingBlockedRelease {
  const PendingBlockedRelease({required this.toolName, required this.command});

  final String toolName;
  final String command;
}

/// Immutable evidence used to plan a blocked-release retry.
///
/// Every field is a recorded fact — a decoded tool-result payload, the block
/// the conversation carried forward, the ledger of commands this owner actually
/// executed, and the release guard's own approval evidence. Nothing here reads
/// the assistant's prose, so the policy cannot be talked into or out of a retry
/// by how an answer is worded.
final class BlockedProductionReleaseRetryInput {
  BlockedProductionReleaseRetryInput({
    required this.owner,
    required List<ToolResultInfo> ownerToolResults,
    required List<String> ownerExecutedCommands,
    required this.approvalGranted,
    required Set<String> attemptedSignatures,
    required this.feedbackId,
    this.pendingBlockedRelease,
  }) : ownerToolResults = List<ToolResultInfo>.unmodifiable(
         ownerToolResults.map(_freezeToolResult),
       ),
       ownerExecutedCommands = List<String>.unmodifiable(ownerExecutedCommands),
       attemptedSignatures = Set<String>.unmodifiable(attemptedSignatures);

  final ChatTurnOwner owner;
  final List<ToolResultInfo> ownerToolResults;
  final List<String> ownerExecutedCommands;

  /// The conversation's outstanding block, if the guard recorded one in this
  /// or an earlier turn. Takes precedence over [ownerToolResults].
  final PendingBlockedRelease? pendingBlockedRelease;

  /// The release guard's approval evidence for this exact owner. The policy
  /// never derives approval itself: a turn that was not approved must stay
  /// blocked, so this stays the single gate.
  final bool approvalGranted;
  final Set<String> attemptedSignatures;
  final String feedbackId;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) {
    return ToolResultInfo(
      id: result.id,
      name: result.name,
      arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
      result: result.result,
    );
  }
}

/// Why no retry was planned, for logging and tests.
enum BlockedProductionReleaseRetryNoPlanReason {
  noBlockedRelease,
  approvalMissing,
  alreadyExecuted,
  repeatedSignature,
}

/// A deterministic request to re-issue one previously blocked release command.
final class BlockedProductionReleaseRetryPlan {
  const BlockedProductionReleaseRetryPlan._({
    required this.owner,
    required this.toolName,
    required this.command,
    required this.signature,
    required this.feedback,
  });

  final ChatTurnOwner owner;
  final String toolName;
  final String command;
  final String signature;
  final ToolResultInfo feedback;
}

/// The outcome of evaluating one turn.
final class BlockedProductionReleaseRetryDisposition {
  const BlockedProductionReleaseRetryDisposition.plan(this.plan)
    : noPlanReason = null;

  const BlockedProductionReleaseRetryDisposition.noPlan(this.noPlanReason)
    : plan = null;

  final BlockedProductionReleaseRetryPlan? plan;
  final BlockedProductionReleaseRetryNoPlanReason? noPlanReason;
}

/// Revives the tool loop when a production release was blocked for missing
/// approval, the user then approved it, and the turn ended without the command
/// ever being re-issued.
///
/// The session log this was built from (2026-08-07, gen-7) shows the shape:
/// `process_start` is blocked, the assistant asks for approval, the user grants
/// it, and the next turn answers "本番実行を開始しました" with zero tool calls. The
/// existing notice marks that answer unverified but lets the turn end, so the
/// user is left watching a release that never started.
///
/// The retry asks the model to issue the call itself rather than executing on
/// its behalf: approval is a decision the guard already made, and a recovery
/// path that ran the release directly would be pushing past a safety pause
/// instead of repairing a dropped one.
final class BlockedProductionReleaseRetryPolicy {
  const BlockedProductionReleaseRetryPolicy();

  BlockedProductionReleaseRetryDisposition evaluate(
    BlockedProductionReleaseRetryInput input,
  ) {
    final blocked =
        input.pendingBlockedRelease ??
        _latestBlockedRelease(input.ownerToolResults);
    if (blocked == null) {
      return const BlockedProductionReleaseRetryDisposition.noPlan(
        BlockedProductionReleaseRetryNoPlanReason.noBlockedRelease,
      );
    }
    if (!input.approvalGranted) {
      return const BlockedProductionReleaseRetryDisposition.noPlan(
        BlockedProductionReleaseRetryNoPlanReason.approvalMissing,
      );
    }
    if (_hasExecuted(input.ownerExecutedCommands, blocked.command)) {
      return const BlockedProductionReleaseRetryDisposition.noPlan(
        BlockedProductionReleaseRetryNoPlanReason.alreadyExecuted,
      );
    }

    final signature = retrySignature(
      owner: input.owner,
      toolName: blocked.toolName,
      command: blocked.command,
    );
    if (input.attemptedSignatures.contains(signature)) {
      return const BlockedProductionReleaseRetryDisposition.noPlan(
        BlockedProductionReleaseRetryNoPlanReason.repeatedSignature,
      );
    }

    return BlockedProductionReleaseRetryDisposition.plan(
      BlockedProductionReleaseRetryPlan._(
        owner: input.owner,
        toolName: blocked.toolName,
        command: blocked.command,
        signature: signature,
        feedback: _buildFeedback(
          feedbackId: input.feedbackId,
          toolName: blocked.toolName,
          command: blocked.command,
        ),
      ),
    );
  }

  /// One retry per owner and command. Re-prompting the same blocked release
  /// twice would turn a dropped call into a loop.
  String retrySignature({
    required ChatTurnOwner owner,
    required String toolName,
    required String command,
  }) {
    return 'blocked_release_retry:${owner.conversationId}:'
        '${owner.interactionGeneration}:$toolName:${normalizeCommand(command)}';
  }

  /// Commands are compared on collapsed whitespace only. Anything smarter
  /// (argument reordering, shell parsing) would start guessing whether two
  /// spellings mean the same release, and a wrong guess here either skips a
  /// real retry or re-runs a publish.
  String normalizeCommand(String command) {
    return command.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Reads a block out of a guard payload, for the case where the assistant
  /// was blocked and approval was already on record in the same turn.
  PendingBlockedRelease? blockedReleaseFromToolResults(
    List<ToolResultInfo> toolResults,
  ) => _latestBlockedRelease(toolResults);

  PendingBlockedRelease? _latestBlockedRelease(
    List<ToolResultInfo> toolResults,
  ) {
    for (final toolResult in toolResults.reversed) {
      final decoded = _decodeJsonObject(toolResult.result);
      if (decoded == null) continue;
      if (decoded['code'] != blockedProductionReleaseCode) continue;
      final command = decoded['command'];
      if (command is! String || command.trim().isEmpty) continue;
      final toolName = toolResult.name.trim();
      if (toolName.isEmpty) continue;
      return PendingBlockedRelease(toolName: toolName, command: command.trim());
    }
    return null;
  }

  bool _hasExecuted(List<String> executedCommands, String command) {
    final target = normalizeCommand(command);
    return executedCommands.any(
      (executed) => normalizeCommand(executed) == target,
    );
  }

  ToolResultInfo _buildFeedback({
    required String feedbackId,
    required String toolName,
    required String command,
  }) {
    return ToolResultInfo(
      id: feedbackId,
      name: toolName,
      arguments: {
        'reason':
            'A production release command was blocked for missing approval, '
            'the user then approved it, and the turn ended without the command '
            'being re-issued.',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'blocked_production_release_retry_required',
        'error':
            'The approved production release command has not been executed. '
            'No successful $toolName result is recorded for it in this turn.',
        'command': command,
        'required_action':
            'Issue exactly one $toolName call with command="$command" now. '
            'Do not describe the run, do not report it as started, and do not '
            'ask for approval again — the user already approved this command.',
      }),
    );
  }

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
