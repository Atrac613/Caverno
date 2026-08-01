import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/tool_call_info.dart';
import 'background_process_monitor_service.dart';

/// Converts owner-scoped process snapshots into completion-blocking feedback.
final class BackgroundProcessCompletionMonitor {
  BackgroundProcessCompletionMonitor({
    required BackgroundProcessMonitorService monitor,
    DateTime Function()? clock,
  }) : _monitor = monitor,
       _clock = clock ?? DateTime.now;

  final BackgroundProcessMonitorService _monitor;
  final DateTime Function() _clock;

  Future<ToolResultInfo?> buildFeedback({
    required ChatTurnOwner owner,
    required List<String> jobIds,
    required String claimedResponse,
  }) async {
    if (jobIds.isEmpty) {
      return null;
    }
    final snapshots = await _monitor.refreshJobs(owner, jobIds);
    final blocking = snapshots
        .where(
          (snapshot) =>
              snapshot.isRunning ||
              snapshot.hasFailedExit ||
              !snapshot.ok ||
              snapshot.status == 'unknown',
        )
        .toList(growable: false);
    if (blocking.isEmpty) {
      return null;
    }
    final hasRunning = blocking.any((snapshot) => snapshot.isRunning);
    final hasFailedExit = blocking.any((snapshot) => snapshot.hasFailedExit);
    final code = hasRunning
        ? 'background_process_still_running'
        : hasFailedExit
        ? 'background_process_failed'
        : 'background_process_status_unverified';
    final error = hasRunning
        ? 'A background process is still running, so the completion claim is not verified yet.'
        : hasFailedExit
        ? 'A background process exited with a non-zero status, so the completion claim is not verified.'
        : 'A background process status could not be verified, so the completion claim is not verified.';

    return ToolResultInfo(
      id: 'background_process_monitor_${_clock().microsecondsSinceEpoch}',
      name: 'background_process_monitor',
      arguments: {'job_ids': jobIds},
      result: jsonEncode({
        'ok': false,
        'code': code,
        'error': error,
        'jobs': blocking.map((snapshot) => snapshot.toJson()).toList(),
        'claimedResponse': claimedResponse,
        'required_action':
            'Use process_list(refresh: true, include_finished: false) to refresh running background jobs, then use process_status, process_tail, or process_wait for the specific job. Inspect stdout_tail, stderr_tail, elapsed_ms, and status to report concise progress before continuing to monitor. Do not just wait silently, and do not claim completion until the relevant process has exited successfully.',
        'progress_report_required': true,
        'progress_report_fields': const [
          'status',
          'elapsed_ms',
          'stdout_tail',
          'stderr_tail',
        ],
      }),
    );
  }
}
