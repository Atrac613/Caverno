import 'dart:async';
import 'dart:convert';

import 'background_process_tools.dart';

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

class BackgroundProcessMonitorService {
  BackgroundProcessMonitorService({
    required BackgroundProcessTools tools,
    Duration pollInterval = const Duration(seconds: 2),
  }) : _tools = tools,
       _pollInterval = pollInterval;

  final BackgroundProcessTools _tools;
  final Duration _pollInterval;
  final Map<String, BackgroundProcessMonitorSnapshot> _snapshots = {};
  final StreamController<BackgroundProcessMonitorSnapshot> _events =
      StreamController<BackgroundProcessMonitorSnapshot>.broadcast();
  Timer? _timer;
  bool _polling = false;

  Stream<BackgroundProcessMonitorSnapshot> get events => _events.stream;

  List<BackgroundProcessMonitorSnapshot> get snapshots =>
      List<BackgroundProcessMonitorSnapshot>.unmodifiable(_snapshots.values);

  List<BackgroundProcessMonitorSnapshot> listJobs({
    Iterable<String>? jobIds,
    bool includeFinished = true,
    int? limit,
  }) {
    final requestedIds = jobIds
        ?.map((jobId) => jobId.trim())
        .where((jobId) => jobId.isNotEmpty)
        .toSet();
    final filtered = requestedIds == null || requestedIds.isEmpty
        ? _snapshots.values
        : _snapshots.values.where(
            (snapshot) => requestedIds.contains(snapshot.jobId),
          );

    final list =
        filtered
            .where((snapshot) => includeFinished || snapshot.isRunning)
            .toList(growable: false)
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    final clampedLimit = limit == null || limit <= 0
        ? list.length
        : limit.clamp(1, 500);
    return List<BackgroundProcessMonitorSnapshot>.unmodifiable(
      list.take(clampedLimit).toList(growable: false),
    );
  }

  List<BackgroundProcessMonitorSnapshot> get activeSnapshots => _snapshots
      .values
      .where((snapshot) => snapshot.isRunning)
      .toList(growable: false);

  BackgroundProcessMonitorSnapshot? byJobId(String jobId) {
    return _snapshots[jobId];
  }

  BackgroundProcessMonitorSnapshot? registerProcessStartResult({
    required String result,
    required Map<String, dynamic> arguments,
  }) {
    final decoded = _decodeJsonMap(result);
    if (decoded == null || decoded['ok'] != true) {
      return null;
    }
    final snapshot = _snapshotFromPayload(
      decoded,
      fallbackArguments: arguments,
      fallbackStatus: 'running',
    );
    if (snapshot == null) {
      return null;
    }
    _store(snapshot);
    return snapshot;
  }

  Future<BackgroundProcessMonitorSnapshot?> refreshJob(String jobId) async {
    final previous = _snapshots[jobId];
    final statusResult = await _tools.status(jobId: jobId);
    final decoded = _decodeJsonMap(statusResult);
    final now = DateTime.now();
    if (decoded == null) {
      final snapshot =
          previous?.copyWith(
            status: 'unknown',
            ok: false,
            error: 'Process status returned invalid JSON.',
            lastCheckedAt: now,
          ) ??
          BackgroundProcessMonitorSnapshot(
            jobId: jobId,
            status: 'unknown',
            command: '',
            workingDirectory: '',
            startedAt: now,
            lastCheckedAt: now,
            ok: false,
            error: 'Process status returned invalid JSON.',
          );
      _store(snapshot);
      return snapshot;
    }

    final snapshot =
        _snapshotFromPayload(
          decoded,
          fallbackArguments: previous?.toJson() ?? const <String, dynamic>{},
          fallbackStatus: previous?.status ?? 'unknown',
        ) ??
        previous?.copyWith(
          status: 'unknown',
          ok: false,
          error: _stringValue(decoded['error']) ?? 'Process status failed.',
          lastCheckedAt: now,
        );
    if (snapshot == null) {
      return null;
    }
    _store(snapshot);
    return snapshot;
  }

  Future<List<BackgroundProcessMonitorSnapshot>> refreshActiveJobs() async {
    final jobIds = activeSnapshots
        .map((snapshot) => snapshot.jobId)
        .toList(growable: false);
    final refreshed = <BackgroundProcessMonitorSnapshot>[];
    for (final jobId in jobIds) {
      final snapshot = await refreshJob(jobId);
      if (snapshot != null) {
        refreshed.add(snapshot);
      }
    }
    return refreshed;
  }

  Future<List<BackgroundProcessMonitorSnapshot>> refreshJobs(
    Iterable<String> jobIds,
  ) async {
    final refreshed = <BackgroundProcessMonitorSnapshot>[];
    for (final jobId in jobIds.toSet()) {
      final snapshot = await refreshJob(jobId);
      if (snapshot != null) {
        refreshed.add(snapshot);
      }
    }
    return refreshed;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_events.close());
  }

  void _store(BackgroundProcessMonitorSnapshot snapshot) {
    _snapshots[snapshot.jobId] = snapshot;
    if (!_events.isClosed) {
      _events.add(snapshot);
    }
    _updateTimer();
  }

  void _updateTimer() {
    if (activeSnapshots.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_pollInterval, (_) {
      unawaited(_pollActiveJobs());
    });
  }

  Future<void> _pollActiveJobs() async {
    if (_polling) {
      return;
    }
    _polling = true;
    try {
      await refreshActiveJobs();
    } finally {
      _polling = false;
    }
  }

  BackgroundProcessMonitorSnapshot? _snapshotFromPayload(
    Map<String, dynamic> payload, {
    required Map<String, dynamic> fallbackArguments,
    required String fallbackStatus,
  }) {
    final jobId = _stringValue(payload['job_id']);
    if (jobId == null || jobId.isEmpty) {
      return null;
    }
    final now = DateTime.now();
    final ok = payload['ok'] != false;
    final status =
        _stringValue(payload['status']) ?? (ok ? fallbackStatus : 'unknown');
    final startedAt = _dateValue(payload['started_at']) ?? now;
    return BackgroundProcessMonitorSnapshot(
      jobId: jobId,
      status: status,
      command:
          _stringValue(payload['command']) ??
          _stringValue(fallbackArguments['command']) ??
          '',
      workingDirectory:
          _stringValue(payload['working_directory']) ??
          _stringValue(fallbackArguments['working_directory']) ??
          '',
      label:
          _stringValue(payload['label']) ??
          _stringValue(fallbackArguments['label']),
      pid: _intValue(payload['pid']),
      exitCode: _intValue(payload['exit_code']),
      elapsedMs: _intValue(payload['elapsed_ms']),
      startedAt: startedAt,
      finishedAt: _dateValue(payload['finished_at']),
      lastCheckedAt: now,
      stdoutTail: _stringValue(payload['stdout_tail']) ?? '',
      stderrTail: _stringValue(payload['stderr_tail']) ?? '',
      stdoutTruncated: payload['stdout_truncated'] == true,
      stderrTruncated: payload['stderr_truncated'] == true,
      ok: ok,
      error: _stringValue(payload['error']),
    );
  }

  Map<String, dynamic>? _decodeJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _stringValue(Object? value) {
    if (value == null) return null;
    final string = value.toString().trim();
    return string.isEmpty ? null : string;
  }

  int? _intValue(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  DateTime? _dateValue(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
