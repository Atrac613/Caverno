part of 'background_process_tools.dart';

extension _BackgroundProcessResultCodec on BackgroundProcessTools {
  String _retiredStartResult(String command, String workingDirectory) => _error(
    'process_start_cancelled',
    command: command,
    workingDirectory: workingDirectory,
    message:
        'The background process owner was cleared before startup completed.',
  );

  String _unconfirmedStartResult(
    _BackgroundProcessRecoveryRecord recovery,
    Object? startupError,
  ) {
    return jsonEncode({
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
    });
  }

  String _terminationUnconfirmedResult(
    _BackgroundProcessRecoveryRecord recovery,
    String? message,
  ) {
    return jsonEncode({
      'ok': false,
      'code': 'background_process_termination_unconfirmed',
      ...recovery.receipt.toJson(),
      'effect_uncertain': true,
      'termination_unconfirmed': true,
      'error':
          message ??
          'The background process did not confirm exact termination.',
    });
  }

  String _notFound(String jobId) => _error(
    'job_not_found',
    jobId: jobId,
    message: 'No background process job exists for job_id: $jobId',
  );

  String _error(
    String code, {
    String? jobId,
    String? command,
    String? workingDirectory,
    String? message,
  }) {
    return jsonEncode({
      'ok': false,
      'code': code,
      'job_id': ?jobId,
      'command': ?command,
      'working_directory': ?workingDirectory,
      'error': ?message,
    });
  }

  String _statusResult(
    _BackgroundProcessJob job,
    Map<String, dynamic> extra, {
    int tailChars = BackgroundProcessTools._defaultTailChars,
  }) {
    return jsonEncode({
      ...job.toStatusJson(tailChars: tailChars),
      'ok': true,
      ...extra,
    });
  }

  String _newJobId(DateTime startedAt) =>
      'proc_${startedAt.microsecondsSinceEpoch}_${++_nextId}';

  int _normalizeTailChars(int? value) =>
      (value ?? BackgroundProcessTools._defaultTailChars)
          .clamp(1, BackgroundProcessTools._maxTailChars)
          .toInt();

  int _normalizeWaitMs(int? value) =>
      (value ?? 1000).clamp(0, BackgroundProcessTools._maxWaitMs).toInt();
}
