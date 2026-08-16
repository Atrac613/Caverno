/// The monitor's view of one background job at a point in time.
///
/// Split from the service because it is a value, not behaviour: the tool
/// handler, the list tool, and the UI all read it without touching polling.
class BackgroundProcessMonitorSnapshot {
  const BackgroundProcessMonitorSnapshot({
    required this.jobId,
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.startedAt,
    required this.lastCheckedAt,
    this.ok = true,
    this.label,
    this.pid,
    this.exitCode,
    this.elapsedMs,
    this.finishedAt,
    this.stdoutTail = '',
    this.stderrTail = '',
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.error,
  });

  final String jobId;
  final String status;
  final String command;
  final String workingDirectory;
  final String? label;
  final int? pid;
  final int? exitCode;
  final int? elapsedMs;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final DateTime lastCheckedAt;
  final String stdoutTail;
  final String stderrTail;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final bool ok;
  final String? error;

  bool get isRunning => status == 'running';

  bool get isTerminal => status == 'exited' || status == 'unknown';

  bool get hasFailedExit => exitCode != null && exitCode != 0;

  BackgroundProcessMonitorSnapshot copyWith({
    String? jobId,
    String? status,
    String? command,
    String? workingDirectory,
    String? label,
    int? pid,
    int? exitCode,
    int? elapsedMs,
    DateTime? startedAt,
    DateTime? finishedAt,
    DateTime? lastCheckedAt,
    String? stdoutTail,
    String? stderrTail,
    bool? stdoutTruncated,
    bool? stderrTruncated,
    bool? ok,
    String? error,
  }) {
    return BackgroundProcessMonitorSnapshot(
      jobId: jobId ?? this.jobId,
      status: status ?? this.status,
      command: command ?? this.command,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      label: label ?? this.label,
      pid: pid ?? this.pid,
      exitCode: exitCode ?? this.exitCode,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      stdoutTail: stdoutTail ?? this.stdoutTail,
      stderrTail: stderrTail ?? this.stderrTail,
      stdoutTruncated: stdoutTruncated ?? this.stdoutTruncated,
      stderrTruncated: stderrTruncated ?? this.stderrTruncated,
      ok: ok ?? this.ok,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'job_id': jobId,
      'status': status,
      'command': command,
      'working_directory': workingDirectory,
      if (label != null && label!.isNotEmpty) 'label': label,
      if (pid != null) 'pid': pid,
      if (exitCode != null) 'exit_code': exitCode,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      'started_at': startedAt.toIso8601String(),
      if (finishedAt != null) 'finished_at': finishedAt!.toIso8601String(),
      'last_checked_at': lastCheckedAt.toIso8601String(),
      'stdout_tail': stdoutTail,
      'stderr_tail': stderrTail,
      'stdout_truncated': stdoutTruncated,
      'stderr_truncated': stderrTruncated,
      'ok': ok,
      if (error != null && error!.isNotEmpty) 'error': error,
    };
  }
}
