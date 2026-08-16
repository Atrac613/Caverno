import 'dart:async';
import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import 'background_process_monitor_snapshot.dart';
import 'background_process_tools.dart';

export 'background_process_monitor_snapshot.dart';

typedef BackgroundProcessStatusReader =
    Future<String> Function({
      required ChatTurnOwner owner,
      required String jobId,
      int? tailChars,
    });

typedef _OwnedBackgroundProcessMonitorSnapshot = ({
  ChatTurnOwner owner,
  BackgroundProcessMonitorSnapshot snapshot,
});

class BackgroundProcessMonitorService {
  BackgroundProcessMonitorService({
    required BackgroundProcessTools tools,
    Duration pollInterval = const Duration(seconds: 2),
    BackgroundProcessStatusReader? statusReader,
  }) : _pollInterval = pollInterval,
       _statusReader =
           statusReader ??
           (({
             required ChatTurnOwner owner,
             required String jobId,
             int? tailChars,
           }) =>
               tools.status(owner: owner, jobId: jobId, tailChars: tailChars));

  final Duration _pollInterval;
  final BackgroundProcessStatusReader _statusReader;
  final Map<ChatTurnOwner, Map<String, BackgroundProcessMonitorSnapshot>>
  _snapshotsByOwner = {};
  final StreamController<_OwnedBackgroundProcessMonitorSnapshot> _events =
      StreamController<_OwnedBackgroundProcessMonitorSnapshot>.broadcast();
  final Map<ChatTurnOwner, Timer> _timersByOwner = {};
  final Set<ChatTurnOwner> _pollingOwners = {};
  final Set<ChatTurnOwner> _retiredOwners = {};

  /// Snapshots of jobs still running when their owner retired, by conversation.
  ///
  /// The mirror of `BackgroundProcessTools._carriedJobs`: the process survives
  /// the turn, so the record of it has to as well, or `process_list` reports an
  /// empty registry for a job that is very much alive.
  final Map<String, Map<String, BackgroundProcessMonitorSnapshot>>
  _carriedSnapshots = {};
  bool _disposed = false;

  Stream<BackgroundProcessMonitorSnapshot> eventsFor(ChatTurnOwner owner) =>
      _events.stream
          .where((event) => event.owner == owner)
          .map((event) => event.snapshot);

  List<BackgroundProcessMonitorSnapshot> snapshots(ChatTurnOwner owner) =>
      List<BackgroundProcessMonitorSnapshot>.unmodifiable(
        _snapshotsFor(owner).values,
      );

  List<BackgroundProcessMonitorSnapshot> listJobs(
    ChatTurnOwner owner, {
    Iterable<String>? jobIds,
    bool includeFinished = true,
    int? limit,
  }) {
    final requestedIds = jobIds
        ?.map((jobId) => jobId.trim())
        .where((jobId) => jobId.isNotEmpty)
        .toSet();
    final ownerSnapshots = _snapshotsFor(owner);
    final filtered = requestedIds == null || requestedIds.isEmpty
        ? ownerSnapshots.values
        : ownerSnapshots.values.where(
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

  List<BackgroundProcessMonitorSnapshot> activeSnapshots(ChatTurnOwner owner) =>
      List<BackgroundProcessMonitorSnapshot>.unmodifiable(
        _snapshotsFor(owner).values.where((snapshot) => snapshot.isRunning),
      );

  BackgroundProcessMonitorSnapshot? byJobId(ChatTurnOwner owner, String jobId) {
    return _snapshotsFor(owner)[jobId];
  }

  BackgroundProcessMonitorSnapshot? registerProcessStartResult({
    required ChatTurnOwner owner,
    required String result,
    required Map<String, dynamic> arguments,
  }) {
    if (!_accepts(owner)) {
      return null;
    }
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
    return _store(owner, snapshot) ? snapshot : null;
  }

  Future<BackgroundProcessMonitorSnapshot?> refreshJob(
    ChatTurnOwner owner,
    String jobId,
  ) async {
    if (!_accepts(owner)) {
      return null;
    }
    final previous = _snapshotsFor(owner)[jobId];
    final statusResult = await _statusReader(owner: owner, jobId: jobId);
    if (!_accepts(owner)) {
      return null;
    }
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
      return _store(owner, snapshot) ? snapshot : null;
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
    return _store(owner, snapshot) ? snapshot : null;
  }

  Future<List<BackgroundProcessMonitorSnapshot>> refreshActiveJobs(
    ChatTurnOwner owner,
  ) async {
    if (!_accepts(owner)) {
      return const <BackgroundProcessMonitorSnapshot>[];
    }
    final jobIds = activeSnapshots(
      owner,
    ).map((snapshot) => snapshot.jobId).toList(growable: false);
    return refreshJobs(owner, jobIds);
  }

  Future<List<BackgroundProcessMonitorSnapshot>> refreshJobs(
    ChatTurnOwner owner,
    Iterable<String> jobIds,
  ) async {
    if (!_accepts(owner)) {
      return const <BackgroundProcessMonitorSnapshot>[];
    }
    final refreshed = <BackgroundProcessMonitorSnapshot>[];
    for (final jobId in jobIds.toSet()) {
      final snapshot = await refreshJob(owner, jobId);
      if (snapshot != null) {
        refreshed.add(snapshot);
      }
    }
    return _accepts(owner)
        ? refreshed
        : const <BackgroundProcessMonitorSnapshot>[];
  }

  void clearOwner(ChatTurnOwner owner) {
    _retiredOwners.add(owner);
    final snapshots = _snapshotsByOwner.remove(owner);
    _timersByOwner.remove(owner)?.cancel();
    _pollingOwners.remove(owner);
    if (_disposed || snapshots == null) {
      return;
    }
    final running = {
      for (final entry in snapshots.entries)
        if (entry.value.isRunning) entry.key: entry.value,
    };
    if (running.isEmpty) {
      return;
    }
    _carriedSnapshots
        .putIfAbsent(
          owner.conversationId,
          () => <String, BackgroundProcessMonitorSnapshot>{},
        )
        .addAll(running);
  }

  /// Drops the carried snapshots for a conversation that has ended.
  void clearConversation(String conversationId) {
    _carriedSnapshots.remove(conversationId);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final timer in _timersByOwner.values) {
      timer.cancel();
    }
    _timersByOwner.clear();
    _pollingOwners.clear();
    _snapshotsByOwner.clear();
    _carriedSnapshots.clear();
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
  }

  Map<String, BackgroundProcessMonitorSnapshot> _snapshotsFor(
    ChatTurnOwner owner,
  ) {
    if (!_accepts(owner)) {
      return const <String, BackgroundProcessMonitorSnapshot>{};
    }
    _adoptCarriedSnapshots(owner);
    return _snapshotsByOwner[owner] ??
        const <String, BackgroundProcessMonitorSnapshot>{};
  }

  /// Hands a live owner the jobs its conversation left running.
  ///
  /// Lazy rather than eager because a turn that never asks about background
  /// work should not start a poll timer for it; the first read is what makes
  /// the owner responsible for the job.
  void _adoptCarriedSnapshots(ChatTurnOwner owner) {
    final carried = _carriedSnapshots.remove(owner.conversationId);
    if (carried == null || carried.isEmpty) {
      return;
    }
    final target = _snapshotsByOwner.putIfAbsent(
      owner,
      () => <String, BackgroundProcessMonitorSnapshot>{},
    );
    for (final entry in carried.entries) {
      target.putIfAbsent(entry.key, () => entry.value);
    }
    _updateTimer(owner);
  }

  bool _accepts(ChatTurnOwner owner) {
    return !_disposed && !_retiredOwners.contains(owner);
  }

  bool _store(ChatTurnOwner owner, BackgroundProcessMonitorSnapshot snapshot) {
    if (!_accepts(owner)) {
      return false;
    }
    _snapshotsByOwner.putIfAbsent(
      owner,
      () => <String, BackgroundProcessMonitorSnapshot>{},
    )[snapshot.jobId] = snapshot;
    if (!_events.isClosed) {
      _events.add((owner: owner, snapshot: snapshot));
    }
    _updateTimer(owner);
    return true;
  }

  void _updateTimer(ChatTurnOwner owner) {
    if (!_accepts(owner) || activeSnapshots(owner).isEmpty) {
      _timersByOwner.remove(owner)?.cancel();
      return;
    }
    _timersByOwner.putIfAbsent(
      owner,
      () => Timer.periodic(_pollInterval, (_) {
        unawaited(_pollActiveJobs(owner));
      }),
    );
  }

  Future<void> _pollActiveJobs(ChatTurnOwner owner) async {
    if (!_accepts(owner) || !_pollingOwners.add(owner)) {
      return;
    }
    try {
      await refreshActiveJobs(owner);
    } finally {
      _pollingOwners.remove(owner);
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
    final startedAt =
        _dateValue(payload['started_at']) ??
        _dateValue(fallbackArguments['started_at']) ??
        now;
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
