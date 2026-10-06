part of 'background_process_tools.dart';

/// The user's view of one conversation's background jobs.
///
/// The tool API is keyed by [ChatTurnOwner] because a turn may only touch the
/// jobs it owns or adopts. The sidebar has no turn: it asks about a
/// conversation, and must see a job whether a live turn owns it or it sits in
/// the carried pool between turns. Reading must therefore never adopt --
/// adoption would hand the job to a retired or foreign owner and change what
/// the next turn's `process_list` reports.
extension BackgroundProcessConversationView on BackgroundProcessTools {
  static const int defaultTailChars = 4000;

  /// Snapshots of every job [conversationId] can still reach, newest first.
  List<BackgroundProcessMonitorSnapshot> conversationJobs(
    String conversationId, {
    int tailChars = defaultTailChars,
  }) {
    if (_disposed) return const <BackgroundProcessMonitorSnapshot>[];
    final now = DateTime.now();
    final snapshots = [
      for (final job in _conversationJobs(conversationId).values)
        _viewSnapshot(job, tailChars: tailChars, now: now),
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List<BackgroundProcessMonitorSnapshot>.unmodifiable(snapshots);
  }

  /// Stops a running job at the user's request.
  ///
  /// The same signal `process_cancel` sends, so a job stopped from the
  /// sidebar reads to the model exactly like one it cancelled itself. Returns
  /// false when the job is unknown to [conversationId] or already exited.
  bool stopConversationJob(String conversationId, String jobId) {
    if (_disposed) return false;
    final job = _conversationJobs(conversationId)[jobId];
    if (job == null || !job.isRunning) return false;
    appLog(
      '[BackgroundProcess] User stopped ${job.id} (pid ${job.process.pid}): '
      '${job.command}',
    );
    job.requestCancel();
    return true;
  }

  /// Adapts [onJobFinished] to one job of [conversationId]; null when no
  /// one listens, so jobs then carry no callback at all.
  void Function(_BackgroundProcessJob job)? _jobFinishedReporter(
    String conversationId,
  ) {
    final report = onJobFinished;
    if (report == null) return null;
    return (job) {
      final end = job.finishedAt ?? DateTime.now();
      report(
        conversationId: conversationId,
        elapsedMs: end.difference(job.startedAt).inMilliseconds,
        exitCode: job.exitCode,
      );
    };
  }

  Map<String, _BackgroundProcessJob> _conversationJobs(String conversationId) {
    final jobs = <String, _BackgroundProcessJob>{};
    for (final entry in _ownerStates.entries) {
      if (entry.key.conversationId != conversationId || entry.value.retired) {
        continue;
      }
      jobs.addAll(entry.value.jobs);
    }
    for (final carried
        in _carriedJobs[conversationId]?.values ??
            const <_CarriedBackgroundProcessJob>[]) {
      jobs.putIfAbsent(carried.job.id, () => carried.job);
    }
    return jobs;
  }

  BackgroundProcessMonitorSnapshot _viewSnapshot(
    _BackgroundProcessJob job, {
    required int tailChars,
    required DateTime now,
  }) {
    final end = job.finishedAt ?? now;
    return BackgroundProcessMonitorSnapshot(
      jobId: job.id,
      status: job.status,
      command: job.command,
      workingDirectory: job.workingDirectory,
      label: job.label,
      pid: job.process.pid,
      exitCode: job.exitCode,
      elapsedMs: end.difference(job.startedAt).inMilliseconds,
      startedAt: job.startedAt,
      finishedAt: job.finishedAt,
      lastCheckedAt: now,
      stdoutTail: job.stdout.tail(tailChars),
      stderrTail: job.stderr.tail(tailChars),
      stdoutTruncated: job.stdout.truncated,
      stderrTruncated: job.stderr.truncated,
    );
  }
}
