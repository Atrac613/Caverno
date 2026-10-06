part of 'background_process_tools.dart';

/// Reuses a job only when its execution authority matches the new request.
extension BackgroundProcessJobLookup on BackgroundProcessTools {
  _BackgroundProcessJob? _runningJobFor(
    _OwnerProcessState state,
    (String, String, String?) route,
  ) {
    for (final job in state.jobs.values) {
      if (job.isRunning && job.executionRoute == route) return job;
    }
    return null;
  }
}
