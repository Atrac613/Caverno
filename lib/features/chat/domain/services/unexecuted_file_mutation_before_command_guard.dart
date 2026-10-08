// ChatNotifier decomposition collaborator: unexecuted-file-mutation-before-command-guard

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'final_answer_claim_detector.dart';
import 'git/git_working_tree_change_evidence.dart';
import 'tool_call_execution_policy.dart';
import 'tool_evidence_snapshot.dart';
import 'unexecuted_file_mutation_block_payload.dart';

/// Immutable owner-turn evidence used before executing one command.
final class UnexecutedFileMutationGuardInput {
  UnexecutedFileMutationGuardInput({
    required this.owner,
    required ToolCallInfo toolCall,
    required this.currentAssistantContent,
    required List<ToolCallInfo> pendingToolCalls,
    required List<ToolResultInfo> executedToolResults,
  }) : toolCall = freezeToolCall(toolCall),
       pendingToolCalls = List<ToolCallInfo>.unmodifiable(
         pendingToolCalls.map(freezeToolCall),
       ),
       executedToolResults = List<ToolResultInfo>.unmodifiable(
         executedToolResults.map(freezeToolResult),
       );

  final ChatTurnOwner owner;
  final ToolCallInfo toolCall;
  final String? currentAssistantContent;
  final List<ToolCallInfo> pendingToolCalls;
  final List<ToolResultInfo> executedToolResults;
}

/// Blocks commands that would follow a claimed but unexecuted file mutation.
final class UnexecutedFileMutationBeforeCommandGuard {
  const UnexecutedFileMutationBeforeCommandGuard();

  static const ToolCallExecutionPolicy _executionPolicy =
      ToolCallExecutionPolicy();
  static const FileMutationEvidencePolicy _mutationPolicy =
      FileMutationEvidencePolicy();
  static const FinalAnswerClaimDetector _claimDetector =
      FinalAnswerClaimDetector();
  static const GitWorkingTreeChangeEvidence _gitChangeEvidence =
      GitWorkingTreeChangeEvidence();
  static final RegExp _standalonePackageInstall = RegExp(
    r'^(?:python(?:3(?:\.[0-9]+)?)\s+-m\s+)?pip(?:3)?\s+install\s+'
    r'(?:--quiet\s+)?[A-Za-z0-9][A-Za-z0-9_.-]*'
    r'(?:==[A-Za-z0-9_.+-]+)?(?:\s+--quiet)?$',
  );

  McpToolResult? evaluate(UnexecutedFileMutationGuardInput input) {
    final toolCall = input.toolCall;
    if (!_executionPolicy.isCommandExecutionTool(toolCall.name) ||
        _executionPolicy.isReadOnlyCommandExecutionToolCall(toolCall)) {
      return null;
    }
    final command = _executionPolicy.toolCommandArgument(toolCall.arguments);
    if (command != null && _standalonePackageInstall.hasMatch(command.trim())) {
      return null;
    }
    if (input.pendingToolCalls.any((pendingToolCall) {
      return pendingToolCall.id != toolCall.id &&
          _mutationPolicy.isMutationToolName(pendingToolCall.name);
    })) {
      return null;
    }
    if (_claimDetector.hasSuccessfulFileSideEffectResult(
      input.executedToolResults,
    )) {
      return null;
    }
    if (_gitChangeEvidence.covers(toolCall, input.executedToolResults)) {
      return null;
    }

    final candidate = input.currentAssistantContent?.trim() ?? '';
    if (!_claimDetector.looksLikeFutureFileSideEffectAction(candidate)) {
      return null;
    }

    return McpToolResult(
      toolName: toolCall.name,
      result: const UnexecutedFileMutationBlockPayload().encode(
        blockedTool: toolCall.name,
        claimedResponse: _claimDetector.clipForDiagnostic(candidate),
        blockedCommand: _executionPolicy.toolCommandArgument(
          toolCall.arguments,
        ),
      ),
      isSuccess: true,
    );
  }
}
