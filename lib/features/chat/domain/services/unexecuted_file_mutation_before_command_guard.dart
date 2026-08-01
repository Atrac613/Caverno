// ChatNotifier decomposition collaborator: unexecuted-file-mutation-before-command-guard

import 'dart:convert';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'final_answer_claim_detector.dart';
import 'immutable_json_snapshot.dart';
import 'tool_call_execution_policy.dart';

/// Immutable owner-turn evidence used before executing one command.
final class UnexecutedFileMutationGuardInput {
  UnexecutedFileMutationGuardInput({
    required this.owner,
    required ToolCallInfo toolCall,
    required this.currentAssistantContent,
    required List<ToolCallInfo> pendingToolCalls,
    required List<ToolResultInfo> executedToolResults,
  }) : toolCall = _freezeToolCall(toolCall),
       pendingToolCalls = List<ToolCallInfo>.unmodifiable(
         pendingToolCalls.map(_freezeToolCall),
       ),
       executedToolResults = List<ToolResultInfo>.unmodifiable(
         executedToolResults.map(_freezeToolResult),
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

  McpToolResult? evaluate(UnexecutedFileMutationGuardInput input) {
    final toolCall = input.toolCall;
    if (!_executionPolicy.isCommandExecutionTool(toolCall.name) ||
        _executionPolicy.isReadOnlyCommandExecutionToolCall(toolCall)) {
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

    final candidate = input.currentAssistantContent?.trim() ?? '';
    if (!_claimDetector.looksLikeFutureFileSideEffectAction(candidate)) {
      return null;
    }

    final blockedCommand = _executionPolicy.toolCommandArgument(
      toolCall.arguments,
    );
    final payloadMap = <String, Object?>{
      'ok': false,
      'code': 'unexecuted_file_save',
      'error':
          'A command was blocked because the assistant claimed a local file '
          'would be changed, but no successful write_file, edit_file, or '
          'rollback_last_file_change result is available for that claimed '
          'mutation.',
      'missing_tool': 'edit_file',
      'blocked_tool': toolCall.name,
      'claimedResponse': _claimDetector.clipForDiagnostic(candidate),
      'required_action':
          'Use write_file or edit_file to perform the claimed file mutation '
          'before running the command, or explain that the command remains '
          'blocked because the file change was not executed.',
    };
    if (blockedCommand != null) {
      payloadMap['blocked_command'] = blockedCommand;
    }
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode(payloadMap),
      isSuccess: true,
    );
  }
}

ToolCallInfo _freezeToolCall(ToolCallInfo toolCall) {
  return ToolCallInfo(
    id: toolCall.id,
    name: toolCall.name,
    arguments: ImmutableJsonSnapshot.freezeMap(toolCall.arguments),
  );
}

ToolResultInfo _freezeToolResult(ToolResultInfo toolResult) {
  return ToolResultInfo(
    id: toolResult.id,
    name: toolResult.name,
    arguments: ImmutableJsonSnapshot.freezeMap(toolResult.arguments),
    result: toolResult.result,
  );
}
