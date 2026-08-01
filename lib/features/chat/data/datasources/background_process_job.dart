part of 'background_process_tools.dart';

final class _OwnerProcessState {
  final Map<String, _BackgroundProcessJob> jobs = {};
  final Map<String, _PendingProcessLaunchLease> pendingStarts = {};
  bool retired = false;
  Future<void>? retirement;
}

final class _BackgroundProcessJob {
  _BackgroundProcessJob({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.process,
    required this.startedAt,
    required BackgroundProcessTerminator terminator,
    required this.processGroupId,
    this.label,
  }) : _terminator = terminator;

  final String id, command, workingDirectory;
  final String? label;
  final Process process;
  final DateTime startedAt;
  final int? processGroupId;
  final BackgroundProcessTerminator _terminator;
  final _RingTextBuffer stdout = _RingTextBuffer(
    BackgroundProcessTools._maxBufferChars,
  );
  final _RingTextBuffer stderr = _RingTextBuffer(
    BackgroundProcessTools._maxBufferChars,
  );
  final Completer<void> _done = Completer<void>();
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _stderrDone = Completer<void>();
  StreamSubscription<String>? _stdoutSubscription, _stderrSubscription;
  Future<void> _terminationTail = Future<void>.value();
  List<int> _unresolvedDescendantProcessIds = const <int>[];
  bool _descendantDiscoveryUncertain = false;
  bool _unrecoverableDescendantUncertainty = false;
  int? exitCode;
  DateTime? finishedAt;
  bool _attached = false;

  bool get isRunning => exitCode == null;
  Future<void> get done => _done.future;
  String get status => isRunning ? 'running' : 'exited';

  void attach() {
    if (_attached) return;
    _attached = true;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(
          stdout.add,
          onError: (Object error) => stderr.add('$error\n'),
          onDone: () => _complete(_stdoutDone),
        );
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(
          stderr.add,
          onError: (Object error) => stderr.add('$error\n'),
          onDone: () => _complete(_stderrDone),
        );
    unawaited(_completeWhenProcessExits());
  }

  Future<BackgroundProcessTerminationReport> terminate() {
    final result = _terminationTail.then((_) async {
      if (_unrecoverableDescendantUncertainty ||
          (!isRunning &&
              _descendantDiscoveryUncertain &&
              _unresolvedDescendantProcessIds.isEmpty)) {
        return const BackgroundProcessTerminationReport.unconfirmed(
          rootTerminationConfirmed: true,
          descendantTerminationConfirmed: false,
          error:
              'The process exited before its descendant set could be '
              'confirmed.',
        );
      }
      if (!isRunning &&
          !_descendantDiscoveryUncertain &&
          _unresolvedDescendantProcessIds.isEmpty) {
        return const BackgroundProcessTerminationReport.confirmed();
      }
      try {
        final report = await _terminator(
          process,
          processGroupId: processGroupId,
          knownDescendantProcessIds: _unresolvedDescendantProcessIds,
        );
        _unresolvedDescendantProcessIds = List<int>.unmodifiable(
          report.liveDescendantProcessIds,
        );
        _descendantDiscoveryUncertain = !report.descendantDiscoveryConfirmed;
        _unrecoverableDescendantUncertainty =
            report.rootTerminationConfirmed &&
            !report.descendantDiscoveryConfirmed;
        return report;
      } catch (error) {
        return BackgroundProcessTerminationReport.unconfirmed(
          rootTerminationConfirmed: !isRunning,
          descendantTerminationConfirmed: false,
          liveDescendantProcessIds: _unresolvedDescendantProcessIds,
          error: error.toString(),
        );
      }
    });
    _terminationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void requestCancel() {
    if (isRunning) process.kill();
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
      _complete(_done);
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
    _complete(_stdoutDone);
    await _stderrSubscription?.cancel();
    _complete(_stderrDone);
  }

  static void _complete(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }
}

final class _RingTextBuffer {
  _RingTextBuffer(this.maxChars);

  final int maxChars;
  final StringBuffer _buffer = StringBuffer();
  bool truncated = false;

  void add(String chunk) {
    if (chunk.isEmpty) return;
    _buffer.write(chunk);
    final text = _buffer.toString();
    if (text.length <= maxChars) return;
    truncated = true;
    _buffer
      ..clear()
      ..write(text.substring(text.length - maxChars));
  }

  String tail(int maxChars) {
    final text = _buffer.toString();
    return text.length <= maxChars
        ? text
        : text.substring(text.length - maxChars);
  }
}
