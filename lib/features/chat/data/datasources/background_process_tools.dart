import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_shell_tools.dart';

class BackgroundProcessTools {
  BackgroundProcessTools();

  static const int _maxBufferChars = 24000;
  static const int _defaultTailChars = 4000;
  static const int _maxTailChars = 12000;
  static const int _maxWaitMs = 30000;

  final Map<String, _BackgroundProcessJob> _jobs = {};
  int _nextId = 0;

  bool get isSupported => LocalShellTools.isDesktopPlatform;

  Future<String> start({
    required String command,
    required String workingDirectory,
    String? label,
  }) async {
    final normalizedCommand = LocalShellTools.normalizeCommand(command);
    if (normalizedCommand.isEmpty) {
      return jsonEncode({'ok': false, 'code': 'command_required'});
    }

    final directory = Directory(workingDirectory);
    if (!directory.existsSync()) {
      return jsonEncode({
        'ok': false,
        'code': 'working_directory_not_found',
        'error': 'Working directory does not exist: $workingDirectory',
      });
    }
    final gitWriteBlockedResult = LocalShellTools.gitWriteCommandBlockedResult(
      command: normalizedCommand,
      workingDirectory: directory.absolute.path,
    );
    if (gitWriteBlockedResult != null) {
      return gitWriteBlockedResult;
    }

    final existingJob = _runningJobFor(
      command: normalizedCommand,
      workingDirectory: directory.absolute.path,
    );
    if (existingJob != null) {
      return jsonEncode({
        ...existingJob.toStatusJson(tailChars: _defaultTailChars),
        'ok': true,
        'duplicate_existing': true,
        'note':
            'A matching command is already running. Reuse this job_id and monitor it instead of starting another process.',
      });
    }

    final shellExecutable = Platform.isWindows ? 'cmd' : 'sh';
    final shellArgs = Platform.isWindows
        ? ['/C', normalizedCommand]
        : ['-c', normalizedCommand];
    final startedAt = DateTime.now();
    final id = _newJobId(startedAt);

    try {
      final process = await Process.start(
        shellExecutable,
        shellArgs,
        workingDirectory: directory.absolute.path,
      );
      final job = _BackgroundProcessJob(
        id: id,
        command: normalizedCommand,
        workingDirectory: directory.absolute.path,
        label: label,
        process: process,
        startedAt: startedAt,
      );
      _jobs[id] = job;
      job.attach();
      return jsonEncode({
        ...job.toStatusJson(tailChars: _defaultTailChars),
        'ok': true,
        'status': 'running',
        'note':
            'The process is running in the background. Use process_status, process_tail, or process_wait with this job_id.',
      });
    } catch (error) {
      return jsonEncode({
        'ok': false,
        'code': 'process_start_failed',
        'command': normalizedCommand,
        'working_directory': directory.absolute.path,
        'error': error.toString(),
      });
    }
  }

  Future<String> status({required String jobId, int? tailChars}) async {
    final job = _jobs[jobId];
    if (job == null) {
      return jsonEncode({
        'ok': false,
        'code': 'job_not_found',
        'job_id': jobId,
        'error': 'No background process job exists for job_id: $jobId',
      });
    }
    return jsonEncode({
      ...job.toStatusJson(tailChars: _normalizeTailChars(tailChars)),
      'ok': true,
    });
  }

  Future<String> tail({required String jobId, int? maxChars}) async {
    final job = _jobs[jobId];
    if (job == null) {
      return jsonEncode({
        'ok': false,
        'code': 'job_not_found',
        'job_id': jobId,
        'error': 'No background process job exists for job_id: $jobId',
      });
    }
    return jsonEncode({
      'ok': true,
      'job_id': job.id,
      'status': job.status,
      'stdout_tail': job.stdout.tail(_normalizeTailChars(maxChars)),
      'stderr_tail': job.stderr.tail(_normalizeTailChars(maxChars)),
      'stdout_truncated': job.stdout.truncated,
      'stderr_truncated': job.stderr.truncated,
    });
  }

  Future<String> wait({required String jobId, int? waitMs}) async {
    final job = _jobs[jobId];
    if (job == null) {
      return jsonEncode({
        'ok': false,
        'code': 'job_not_found',
        'job_id': jobId,
        'error': 'No background process job exists for job_id: $jobId',
      });
    }

    if (job.isRunning) {
      final duration = Duration(milliseconds: _normalizeWaitMs(waitMs));
      try {
        await job.done.timeout(duration);
      } on TimeoutException {
        // Returning the current running status is the expected outcome.
      }
    }

    return jsonEncode({
      ...job.toStatusJson(tailChars: _defaultTailChars),
      'ok': true,
    });
  }

  Future<String> cancel({required String jobId}) async {
    final job = _jobs[jobId];
    if (job == null) {
      return jsonEncode({
        'ok': false,
        'code': 'job_not_found',
        'job_id': jobId,
        'error': 'No background process job exists for job_id: $jobId',
      });
    }
    if (job.isRunning) {
      job.process.kill();
    }
    return jsonEncode({
      ...job.toStatusJson(tailChars: _defaultTailChars),
      'ok': true,
      'cancel_requested': true,
    });
  }

  Future<void> dispose() async {
    for (final job in _jobs.values) {
      if (job.isRunning) {
        job.process.kill();
      }
      await job.dispose();
    }
    _jobs.clear();
  }

  _BackgroundProcessJob? _runningJobFor({
    required String command,
    required String workingDirectory,
  }) {
    for (final job in _jobs.values) {
      if (job.isRunning &&
          job.command == command &&
          job.workingDirectory == workingDirectory) {
        return job;
      }
    }
    return null;
  }

  String _newJobId(DateTime startedAt) {
    _nextId += 1;
    return 'proc_${startedAt.microsecondsSinceEpoch}_$_nextId';
  }

  int _normalizeTailChars(int? value) {
    return (value ?? _defaultTailChars).clamp(1, _maxTailChars).toInt();
  }

  int _normalizeWaitMs(int? value) {
    return (value ?? 1000).clamp(0, _maxWaitMs).toInt();
  }
}

class _BackgroundProcessJob {
  _BackgroundProcessJob({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.process,
    required this.startedAt,
    this.label,
  });

  final String id;
  final String command;
  final String workingDirectory;
  final String? label;
  final Process process;
  final DateTime startedAt;
  final _RingTextBuffer stdout = _RingTextBuffer(
    BackgroundProcessTools._maxBufferChars,
  );
  final _RingTextBuffer stderr = _RingTextBuffer(
    BackgroundProcessTools._maxBufferChars,
  );
  final Completer<void> _done = Completer<void>();
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _stderrDone = Completer<void>();
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  int? exitCode;
  DateTime? finishedAt;

  bool get isRunning => exitCode == null;
  Future<void> get done => _done.future;

  String get status => isRunning ? 'running' : 'exited';

  void attach() {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(
          stdout.add,
          onError: (Object error) => stderr.add('$error\n'),
          onDone: () {
            if (!_stdoutDone.isCompleted) {
              _stdoutDone.complete();
            }
          },
        );
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(
          stderr.add,
          onError: (Object error) => stderr.add('$error\n'),
          onDone: () {
            if (!_stderrDone.isCompleted) {
              _stderrDone.complete();
            }
          },
        );
    unawaited(_completeWhenProcessExits());
  }

  Future<void> _completeWhenProcessExits() async {
    try {
      exitCode = await process.exitCode;
      finishedAt = DateTime.now();
      await Future.wait<void>([
        _stdoutDone.future,
        _stderrDone.future,
      ]).timeout(const Duration(seconds: 1));
    } on TimeoutException {
      stderr.add(
        'Timed out while waiting for process output streams to close.\n',
      );
    } catch (error) {
      stderr.add('$error\n');
      exitCode = -1;
      finishedAt = DateTime.now();
    } finally {
      if (!_done.isCompleted) {
        _done.complete();
      }
    }
  }

  Map<String, dynamic> toStatusJson({required int tailChars}) {
    final now = DateTime.now();
    return {
      'job_id': id,
      'status': status,
      'pid': process.pid,
      'command': command,
      'working_directory': workingDirectory,
      if (label != null && label!.isNotEmpty) 'label': label,
      'started_at': startedAt.toIso8601String(),
      if (finishedAt != null) 'finished_at': finishedAt!.toIso8601String(),
      'elapsed_ms': now.difference(startedAt).inMilliseconds,
      if (exitCode != null) 'exit_code': exitCode,
      'stdout_tail': stdout.tail(tailChars),
      'stderr_tail': stderr.tail(tailChars),
      'stdout_truncated': stdout.truncated,
      'stderr_truncated': stderr.truncated,
    };
  }

  Future<void> dispose() async {
    await _stdoutSubscription?.cancel();
    if (!_stdoutDone.isCompleted) {
      _stdoutDone.complete();
    }
    await _stderrSubscription?.cancel();
    if (!_stderrDone.isCompleted) {
      _stderrDone.complete();
    }
  }
}

class _RingTextBuffer {
  _RingTextBuffer(this.maxChars);

  final int maxChars;
  final StringBuffer _buffer = StringBuffer();
  bool truncated = false;

  void add(String chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _buffer.write(chunk);
    final text = _buffer.toString();
    if (text.length <= maxChars) {
      return;
    }
    truncated = true;
    final clipped = text.substring(text.length - maxChars);
    _buffer
      ..clear()
      ..write(clipped);
  }

  String tail(int maxChars) {
    final text = _buffer.toString();
    if (text.length <= maxChars) {
      return text;
    }
    return text.substring(text.length - maxChars);
  }
}
