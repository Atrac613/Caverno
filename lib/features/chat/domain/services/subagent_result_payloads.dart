import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/subagent_task.dart';
import '../entities/worktree_agent_task.dart';
import 'subagent_tool_contract.dart';

/// What `get_subagent_result` answers with, in every case it can answer.
///
/// Extracted from the notifier because none of it needs a turn: the shapes are a
/// function of the child, or of the ids that exist. What stays behind is the
/// registry read, which is the only part that does.
class SubagentResultPayloads {
  const SubagentResultPayloads();

  McpToolResult missingTaskId(String toolName) => McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: 'task_id is required',
  );

  /// An id that names no child, answered with the ids that do.
  ///
  /// Measured live: the parent passed a *workflow* task id -- the plan's -- to a
  /// tool whose parameter is `task_id`, twice, and the second failure ended the
  /// whole turn as if the tool were unreachable. A refusal that names nothing
  /// correctable is what made that possible.
  McpToolResult unknownTask({
    required String toolName,
    required String taskId,
    required List<String> knownTaskIds,
  }) => McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': subagentTaskUnknownCode,
      ...ToolResultOrigin.refusal.marker,
      'status': 'not_found',
      'task_id': taskId,
      'known_task_ids': knownTaskIds,
      'required_action':
          'Pass a task_id from known_task_ids. A workflow_task_id names a '
          'task in the plan, not a child that ran.',
    }),
    isSuccess: false,
    errorMessage: 'No subagent task with id $taskId',
  );

  /// A worktree child was enqueued: a branch, a checkout, and an id to poll.
  ///
  /// Enqueued rather than completed, on purpose. A worktree child is the
  /// evidenced kind -- it reports changed files and the result of the saved
  /// validation command -- and none of that exists yet at the moment the parent
  /// asks for it.
  McpToolResult worktreeEnqueued({
    required String toolName,
    required String taskId,
    required String workflowTaskId,
    required String branchName,
    required String worktreePath,
    required String verificationCommand,
  }) => McpToolResult(
    toolName: toolName,
    isSuccess: true,
    result: jsonEncode({
      'ok': true,
      'runner': 'worktree',
      'status': 'enqueued',
      'task_id': taskId,
      'workflow_task_id': workflowTaskId,
      'branch_name': branchName,
      'worktree_path': worktreePath,
      'verification_command': verificationCommand,
      'started': true,
      'required_action':
          'The child is running on its own branch. Poll get_subagent_result '
          'with task_id, and accept only once it reports changed files and a '
          'green verification.',
    }),
  );

  /// A worktree child's state, with the two things only it can report.
  ///
  /// The changed-file count rather than the files: this answer is read on every
  /// poll, and the list belongs to the acceptance that rests on it. `verified` is
  /// stated even when false, because "not yet" and "failed" are both answers the
  /// parent has to be able to act on.
  McpToolResult forWorktreeTask({
    required String toolName,
    required WorktreeAgentTask task,
  }) => McpToolResult(
    toolName: toolName,
    isSuccess: task.status != WorktreeAgentTaskStatus.failed,
    result: jsonEncode({
      'runner': 'worktree',
      'task_id': task.id,
      'description': task.title,
      'status': task.status.name,
      'workflow_task_id': task.workflowTaskId,
      'branch_name': task.branchName,
      'verification_command': task.verificationCommand,
      'verified': task.verifiedGreen,
      'changed_file_count': task.changedFiles.length,
      if (task.changedFileEvidenceTruncated) 'changed_files_truncated': true,
      if (task.resultSummary.trim().isNotEmpty) 'summary': task.resultSummary,
      if (task.verificationSummary.trim().isNotEmpty)
        'verification_summary': task.verificationSummary,
      if (task.error.trim().isNotEmpty) 'error': task.error,
      if (task.isRecoverable && task.recoveryNote.trim().isNotEmpty)
        'recovery_note': task.recoveryNote,
      if (!task.isTerminal) 'note': 'Still running. Check again shortly.',
    }),
  );

  /// The worktree route was asked for and cannot be taken.
  McpToolResult worktreeUnavailable({
    required String toolName,
    required String reason,
    required String requiredAction,
  }) => McpToolResult(
    toolName: toolName,
    isSuccess: false,
    result: jsonEncode({
      'ok': false,
      'code': 'worktree_delegation_unavailable',
      ...ToolResultOrigin.refusal.marker,
      'reason': reason,
      'required_action': requiredAction,
    }),
  );

  /// The child's own state, and only the field its state earns: a summary for a
  /// completed child, an error for a failed one, and a note for one still going.
  McpToolResult forTask({
    required String toolName,
    required SubagentTask task,
  }) {
    final payload = <String, dynamic>{
      'task_id': task.id,
      'description': task.description,
      'status': task.status.name,
    };
    if (task.status == SubagentTaskStatus.completed) {
      payload['summary'] = task.resultSummary;
    } else if (task.status == SubagentTaskStatus.failed) {
      payload['error'] = task.error ?? 'Subagent failed';
    } else if (task.isActive) {
      payload['note'] = 'Still running. Check again shortly.';
    }
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode(payload),
      isSuccess: task.status != SubagentTaskStatus.failed,
    );
  }
}
