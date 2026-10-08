import 'dart:convert';

import '../../entities/subagent_task.dart';
import '../../entities/tool_call_info.dart';
import '../final_answer_claim_detector.dart';
import '../plan/proposal_parsing_text_utils.dart';
import '../tool_call_execution_policy.dart';
import 'local_command_tool_contract.dart';

/// Interprets captured process and owner-bound child completion evidence.
final class BackgroundCompletionEvidence {
  const BackgroundCompletionEvidence();
  static const _toolCallExecutionPolicy = ToolCallExecutionPolicy();
  static const _claims = FinalAnswerClaimDetector();
  bool _containsAny(String text, List<String> markers) =>
      markers.any(text.contains);
  ToolResultInfo? partialFailure({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final failedResults = toolResults
        .where(_toolResultContainsReleaseFailureMarker)
        .toList(growable: false);
    if (failedResults.isEmpty) {
      return null;
    }
    final failedJobIds = jobIds(failedResults);
    return ToolResultInfo(
      id: 'background_process_partial_failure_${DateTime.now().microsecondsSinceEpoch}',
      name: 'background_process_monitor',
      arguments: {
        if (failedJobIds.isNotEmpty) 'job_ids': failedJobIds,
        'source': 'tool_result_output',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'background_process_partial_failure',
        'error':
            'A background process output contains a release failure marker, '
            'so an exit code 0 is not enough to verify full completion.',
        if (failedJobIds.isNotEmpty) 'job_ids': failedJobIds,
        'failed_tool_results': failedResults
            .map(
              (result) => {
                'tool_name': result.name,
                'arguments': result.arguments,
                'result_excerpt': _claims.clipForDiagnostic(result.result),
              },
            )
            .toList(growable: false),
        'claimedResponse': _claims.clipForDiagnostic(candidateResponse),
        'required_action':
            'Report the partial failure explicitly. Do not claim the release, '
            'upload, or export completed successfully until a later command '
            'result proves the failed lane was retried and succeeded.',
      }),
    );
  }

  bool hasSuccessfulCompletion(List<ToolResultInfo> toolResults) {
    final relevantJobIds = jobIds(toolResults);
    if (relevantJobIds.isEmpty) {
      return false;
    }
    final successfulJobIds = <String>{};
    for (final result in toolResults) {
      final name = result.name.trim().toLowerCase();
      if (name != 'process_status' &&
          name != 'process_wait' &&
          name != 'process_start') {
        continue;
      }
      if (!_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
        continue;
      }
      final decoded = ProposalParsingTextUtils.tryDecodeMap(result.result);
      final jobId = decoded?['job_id']?.toString().trim();
      if (jobId != null && jobId.isNotEmpty) {
        successfulJobIds.add(jobId);
      }
    }
    return relevantJobIds.every(successfulJobIds.contains);
  }

  bool _toolResultContainsReleaseFailureMarker(ToolResultInfo result) {
    if (!_toolCallExecutionPolicy.isCommandExecutionTool(result.name)) {
      return false;
    }
    final normalized = result.result.toLowerCase();
    return _containsAny(normalized, const [
          'overall: partial_failure',
          'encountered error while creating the ipa',
          'error: exportarchive',
          'the bundle version must be higher',
          'upload failed',
          'ipatool failed',
        ]) ||
        RegExp(r'itms-\d+').hasMatch(normalized);
  }

  ToolResultInfo? subagentFeedback({
    required SubagentTask? Function(String) taskById,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final runningTaskIds = <String>[];
    final failedTaskIds = <String>[];
    final blockedTasks = <Map<String, dynamic>>[];

    for (final result in toolResults) {
      final name = result.name.trim().toLowerCase();
      if (name != 'spawn_subagent' && name != 'get_subagent_result') {
        continue;
      }
      final decoded = ProposalParsingTextUtils.tryDecodeMap(result.result);
      final taskId = decoded?['task_id']?.toString().trim();
      if (taskId == null || taskId.isEmpty) {
        continue;
      }
      if (runningTaskIds.contains(taskId) || failedTaskIds.contains(taskId)) {
        continue;
      }

      final rawStatus = decoded?['status']?.toString().toLowerCase() ?? '';
      final task = taskById(taskId);
      final status = task?.status ?? _statusFromSubagentTaskResult(rawStatus);
      final description =
          decoded?['description']?.toString() ??
          task?.description ??
          'background subagent task';

      if (status == SubagentTaskStatus.completed) {
        continue;
      }
      if (status == SubagentTaskStatus.failed ||
          status == SubagentTaskStatus.cancelled) {
        failedTaskIds.add(taskId);
        blockedTasks.add({
          'task_id': taskId,
          'status': status == SubagentTaskStatus.failed
              ? 'failed'
              : 'cancelled',
          'description': description,
          'error': decoded?['error']?.toString() ?? task?.error,
        });
        continue;
      }
      if (status == SubagentTaskStatus.pending ||
          status == SubagentTaskStatus.running) {
        runningTaskIds.add(taskId);
        blockedTasks.add({
          'task_id': taskId,
          'status': status == SubagentTaskStatus.pending
              ? 'pending'
              : 'running',
          'description': description,
        });
        continue;
      }
      if (status == null) {
        if (rawStatus == 'running' ||
            rawStatus == 'pending' ||
            rawStatus == 'started') {
          runningTaskIds.add(taskId);
          blockedTasks.add({
            'task_id': taskId,
            'status': rawStatus,
            'description': description,
          });
        } else if (rawStatus == 'failed') {
          failedTaskIds.add(taskId);
          blockedTasks.add({
            'task_id': taskId,
            'status': rawStatus,
            'description': description,
            'error': decoded?['error']?.toString(),
          });
        }
      }
    }

    if (blockedTasks.isEmpty) {
      return null;
    }

    final running = blockedTasks
        .where(
          (task) => task['status'] == 'running' || task['status'] == 'pending',
        )
        .toList(growable: false);
    final failed = blockedTasks
        .where(
          (task) => task['status'] == 'failed' || task['status'] == 'cancelled',
        )
        .toList(growable: false);
    final code = running.isNotEmpty
        ? 'subagent_still_running'
        : failed.isNotEmpty
        ? 'subagent_failed'
        : 'subagent_status_unverified';
    final error = running.isNotEmpty
        ? 'One or more background subagent tasks are still running, so the completion claim is not verified yet.'
        : failed.isNotEmpty
        ? 'One or more background subagent tasks failed, so the completion claim is not verified.'
        : 'One or more background subagent tasks could not be verified, so the completion claim is not verified.';

    return ToolResultInfo(
      id: 'subagent_monitor_${DateTime.now().microsecondsSinceEpoch}',
      name: 'get_subagent_result',
      arguments: {
        'task_ids': blockedTasks
            .map((task) => task['task_id'])
            .whereType<String>()
            .toList(growable: false),
      },
      result: jsonEncode({
        'ok': false,
        'code': code,
        'error': error,
        'tasks': blockedTasks,
        'claimedResponse': _claims.clipForDiagnostic(candidateResponse),
        'required_action':
            'Call get_subagent_result for each pending task_id until the status becomes completed, and do not claim completion until every relevant background subagent task finishes successfully.',
      }),
    );
  }

  SubagentTaskStatus? _statusFromSubagentTaskResult(String rawStatus) {
    switch (rawStatus) {
      case 'pending':
        return SubagentTaskStatus.pending;
      case 'running':
        return SubagentTaskStatus.running;
      case 'completed':
        return SubagentTaskStatus.completed;
      case 'failed':
        return SubagentTaskStatus.failed;
      case 'cancelled':
        return SubagentTaskStatus.cancelled;
      default:
        return null;
    }
  }

  List<String> jobIds(List<ToolResultInfo> toolResults) {
    final jobIds = <String>[];
    for (final result in toolResults) {
      final name = result.name.trim().toLowerCase();
      if (name != 'process_start' &&
          (name != 'local_execute_command' ||
              !argumentIsTruthy(result.arguments['background'])) &&
          name != 'process_status' &&
          name != 'process_wait') {
        continue;
      }
      final decoded = ProposalParsingTextUtils.tryDecodeMap(result.result);
      final jobId = decoded?['job_id']?.toString().trim();
      if (jobId != null && jobId.isNotEmpty) {
        jobIds.add(jobId);
      }
    }
    return jobIds.toSet().toList(growable: false);
  }
}
