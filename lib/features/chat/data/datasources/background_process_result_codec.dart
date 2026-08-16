part of 'background_process_tools.dart';

extension _BackgroundProcessResultCodec on BackgroundProcessTools {
  FirstPartyToolExecutionResult _retiredStartResult(
    String command,
    String workingDirectory,
  ) => _error(
    'process_start_cancelled',
    command: command,
    workingDirectory: workingDirectory,
    message:
        'The background process owner was cleared before startup completed.',
  );

  FirstPartyToolExecutionResult _unconfirmedStartResult(
    _BackgroundProcessRecoveryRecord recovery,
    Object? startupError,
  ) {
    final payload = {
      ...recovery.job.toStatusJson(
        tailChars: BackgroundProcessTools._defaultTailChars,
      ),
      'ok': true,
      'effect_uncertain': true,
      'termination_unconfirmed': true,
      ...recovery.receipt.toJson(),
      'error':
          startupError?.toString() ??
          'The process started after its owner retired and exact termination '
              'could not be confirmed.',
    };
    return _jobResult(recovery.job, payload);
  }

  FirstPartyToolExecutionResult _terminationUnconfirmedResult(
    _BackgroundProcessRecoveryRecord recovery,
    String? message,
  ) {
    return FirstPartyToolExecutionResult.payloadOnly(
      jsonEncode({
        'ok': false,
        'code': 'background_process_termination_unconfirmed',
        ...recovery.receipt.toJson(),
        'effect_uncertain': true,
        'termination_unconfirmed': true,
        'error':
            message ??
            'The background process did not confirm exact termination.',
      }),
    );
  }

  FirstPartyToolExecutionResult _notFound(String jobId) => _error(
    'job_not_found',
    jobId: jobId,
    message: 'No background process job exists for job_id: $jobId',
  );

  FirstPartyToolExecutionResult _error(
    String code, {
    String? jobId,
    String? command,
    String? workingDirectory,
    String? message,
  }) {
    return FirstPartyToolExecutionResult.payloadOnly(
      jsonEncode({
        'ok': false,
        'code': code,
        'job_id': ?jobId,
        'command': ?command,
        'working_directory': ?workingDirectory,
        'error': ?message,
      }),
    );
  }

  FirstPartyToolExecutionResult _statusResult(
    _BackgroundProcessJob job,
    Map<String, dynamic> extra, {
    int tailChars = BackgroundProcessTools._defaultTailChars,
  }) {
    return _jobResult(job, {
      ...job.toStatusJson(tailChars: tailChars),
      'ok': true,
      ...extra,
    });
  }

  FirstPartyToolExecutionResult _jobResult(
    _BackgroundProcessJob job,
    Map<String, dynamic> payload,
  ) => FirstPartyToolExecutionResult(
    result: jsonEncode(payload),
    outcome: ToolOutcome(
      processState: job.isRunning
          ? ToolProcessState.running
          : ToolProcessState.exited,
      exitCode: job.exitCode,
    ),
  );

  String _newJobId(DateTime startedAt) =>
      'proc_${startedAt.microsecondsSinceEpoch}_${++_nextId}';

  int _normalizeTailChars(int? value) =>
      (value ?? BackgroundProcessTools._defaultTailChars)
          .clamp(1, BackgroundProcessTools._maxTailChars)
          .toInt();

  /// Clamps `wait_ms` up as well as down.
  ///
  /// A wait returns as soon as the process exits, so the floor only costs
  /// latency while the job is genuinely still running -- and that is the case
  /// worth slowing down. Every poll re-sends the whole conversation, so a poll
  /// costs roughly 16k prompt tokens no matter how briefly it waits.
  ///
  /// The first floor (5s, replacing no floor at all) stopped session a00b77ce's
  /// 1s polling from burning an organization's per-minute token budget. It did
  /// not stop the polling from dominating the session: 783fd214 watched a 392
  /// second build with 27 observations, 26 of them at exactly the 5s floor the
  /// model anchored on, and spent 55% of a million-token session waiting. The
  /// floor is what the model actually picks, so it has to be a duration worth
  /// paying 16k tokens for.
  int _normalizeWaitMs(int? value) => (value ?? _defaultWaitMs)
      .clamp(
        BackgroundProcessTools._minWaitMs,
        BackgroundProcessTools._maxWaitMs,
      )
      .toInt();

  static const int _defaultWaitMs = 30000;
}
