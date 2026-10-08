import 'dart:convert';

import '../../entities/chat_turn_owner.dart';
import '../../entities/tool_call_info.dart';
import 'blocked_production_release_retry_contract.dart';
import 'production_release_execution_identity.dart';

export 'blocked_production_release_retry_contract.dart';
export 'production_release_execution_identity.dart';

// ChatNotifier decomposition collaborator: blocked-production-release-retry-policy

/// The structured code the release guard writes when it blocks a production
/// release for missing user approval.
const String blockedProductionReleaseCode =
    'production_release_explicit_approval_required';

/// Retries an approved production release when a completed turn never
/// re-issued the blocked command.
final class BlockedProductionReleaseRetryPolicy {
  const BlockedProductionReleaseRetryPolicy();

  static const _executionIdentity = ProductionReleaseExecutionIdentity();
  bool matchesToolCall(
    BlockedProductionReleaseRetryPlan release,
    ToolCallInfo toolCall, {
    Map<String, dynamic>? resolvedArguments,
  }) {
    final expected = release.executionIdentity;
    return expected != null &&
        _executionIdentity.forToolCall(
              toolCall,
              resolvedArguments: resolvedArguments,
            ) ==
            expected;
  }

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
    final executionIdentity = blocked.executionIdentity;
    final alreadyExecuted = executionIdentity != null
        ? input.ownerExecutedReleaseIdentities.contains(executionIdentity)
        : _hasExecuted(input.ownerExecutedCommands, blocked.command);
    if (alreadyExecuted) {
      return const BlockedProductionReleaseRetryDisposition.noPlan(
        BlockedProductionReleaseRetryNoPlanReason.alreadyExecuted,
      );
    }

    final signature = retrySignature(
      owner: input.owner,
      toolName: blocked.toolName,
      command: blocked.command,
      executionIdentity: blocked.executionIdentity,
    );
    if (input.attemptedSignatures.contains(signature)) {
      return const BlockedProductionReleaseRetryDisposition.noPlan(
        BlockedProductionReleaseRetryNoPlanReason.repeatedSignature,
      );
    }

    return BlockedProductionReleaseRetryDisposition.plan(
      BlockedProductionReleaseRetryPlan(
        owner: input.owner,
        toolName: blocked.toolName,
        command: blocked.command,
        executionIdentity: blocked.executionIdentity,
        workingDirectory: blocked.workingDirectory,
        background: blocked.background,
        signature: signature,
        feedback: _buildFeedback(
          feedbackId: input.feedbackId,
          toolName: blocked.toolName,
          command: blocked.command,
          workingDirectory: blocked.workingDirectory,
          background: blocked.background,
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
    String? executionIdentity,
  }) {
    final exactIdentity = executionIdentity?.trim();
    final releaseKey = exactIdentity == null || exactIdentity.isEmpty
        ? normalizeCommand(command)
        : exactIdentity;
    return 'blocked_release_retry:${owner.conversationId}:'
        '${owner.interactionGeneration}:$toolName:$releaseKey';
  }

  /// Commands are compared on collapsed whitespace only. Anything smarter
  /// (argument reordering, shell parsing) would start guessing whether two
  /// spellings mean the same release, and a wrong guess here either skips a
  /// real retry or re-runs a publish.
  String normalizeCommand(String command) {
    return _executionIdentity.normalizeCommand(command);
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
    required String? workingDirectory,
    required bool background,
  }) {
    final normalizedWorkingDirectory = workingDirectory?.trim();
    final exactArguments = [
      'command=${jsonEncode(command)}',
      if (normalizedWorkingDirectory != null &&
          normalizedWorkingDirectory.isNotEmpty)
        'working_directory=${jsonEncode(normalizedWorkingDirectory)}',
      if (background) 'background=true',
    ].join(', ');
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
        if (normalizedWorkingDirectory != null &&
            normalizedWorkingDirectory.isNotEmpty)
          'working_directory': normalizedWorkingDirectory,
        'background': background,
        'required_action':
            'Issue exactly one $toolName call with $exactArguments now. '
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
