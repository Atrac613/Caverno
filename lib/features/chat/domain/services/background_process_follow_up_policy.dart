import '../entities/tool_call_info.dart';
import 'proposal_parsing_text_utils.dart';

/// Decides whether the tool loop should wait on a background job it started.
///
/// Pure over the turn's tool results, so it lives outside ChatNotifier: the
/// notifier only needs to know whether to issue another `process_wait`.
class BackgroundProcessFollowUpPolicy {
  const BackgroundProcessFollowUpPolicy._();

  /// A `process_wait` call for the newest job still reported as running, or
  /// null when every job the turn touched has settled.
  static ToolCallInfo? followUpToolCall(
    List<ToolResultInfo> toolResults, {
    required int waitMs,
  }) {
    final latestStatusesByJobId = <String, String>{};
    for (final result in toolResults.reversed) {
      final name = result.name.trim().toLowerCase();
      final decoded = ProposalParsingTextUtils.tryDecodeMap(result.result);
      if (decoded == null) {
        continue;
      }
      if (name == 'background_process_monitor' &&
          decoded['code'] == 'background_process_still_running') {
        final jobs = decoded['jobs'];
        if (jobs is! List) {
          continue;
        }
        for (final job in jobs) {
          if (job is! Map) {
            continue;
          }
          final jobId = job['job_id']?.toString().trim();
          if (jobId == null || jobId.isEmpty) {
            continue;
          }
          latestStatusesByJobId.putIfAbsent(
            jobId,
            () => job['status']?.toString().trim().toLowerCase() ?? '',
          );
        }
        continue;
      }
      if (name == 'process_start' ||
          name == 'process_status' ||
          name == 'process_wait' ||
          name == 'local_execute_command') {
        final jobId = decoded['job_id']?.toString().trim();
        if (jobId == null || jobId.isEmpty) {
          continue;
        }
        latestStatusesByJobId.putIfAbsent(
          jobId,
          () =>
              result.outcome?.processState?.name ??
              decoded['status']?.toString().trim().toLowerCase() ??
              '',
        );
      }
    }
    for (final entry in latestStatusesByJobId.entries) {
      if (entry.value != 'running') {
        continue;
      }
      return ToolCallInfo(
        id:
            'background_process_monitor_followup_'
            '${DateTime.now().microsecondsSinceEpoch}',
        name: 'process_wait',
        arguments: {'job_id': entry.key, 'wait_ms': waitMs},
      );
    }
    return null;
  }

  /// Backs off as the loop iterates, so a long job is not polled tightly.
  ///
  /// Kept above the tool's own floor so the backoff still means something: with
  /// a 15s clamp on `wait_ms`, the old 5s-to-15s ramp flattened into a constant.
  static int waitMsForIteration(int iteration) {
    return (15000 + iteration * 15000).clamp(15000, 120000).toInt();
  }
}
