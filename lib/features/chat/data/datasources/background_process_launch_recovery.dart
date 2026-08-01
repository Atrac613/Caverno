part of 'background_process_tools.dart';

enum BackgroundProcessRecoveryDisposition {
  terminationConfirmed,
  terminationUnconfirmed,
  alreadyResolved,
  riskAcknowledged,
  receiptMismatch,
}

/// Exact capability for reconciling one process whose launch crossed retirement.
final class BackgroundProcessRecoveryReceipt {
  const BackgroundProcessRecoveryReceipt._({
    required this.owner,
    required this.jobId,
    required this.processId,
    required this.command,
    required this.workingDirectory,
    required this.recoveryToken,
    required this.processGroupId,
  });

  final ChatTurnOwner owner;
  final String jobId;
  final int processId;
  final String command;
  final String workingDirectory;
  final String recoveryToken;

  /// Null when the platform launch API cannot establish a dedicated group.
  final int? processGroupId;

  bool matches(BackgroundProcessRecoveryReceipt other) =>
      owner == other.owner &&
      jobId == other.jobId &&
      processId == other.processId &&
      command == other.command &&
      workingDirectory == other.workingDirectory &&
      recoveryToken == other.recoveryToken &&
      processGroupId == other.processGroupId;

  Map<String, dynamic> toJson() => {
    'job_id': jobId,
    'pid': processId,
    'recovery_token': recoveryToken,
    if (processGroupId != null) 'process_group_id': processGroupId,
  };
}

final class BackgroundProcessRecoveryAcknowledgement {
  const BackgroundProcessRecoveryAcknowledgement({
    required this.disposition,
    required this.receipt,
    this.error,
  });

  final BackgroundProcessRecoveryDisposition disposition;
  final BackgroundProcessRecoveryReceipt receipt;
  final String? error;

  bool get terminationConfirmed =>
      disposition ==
          BackgroundProcessRecoveryDisposition.terminationConfirmed ||
      disposition == BackgroundProcessRecoveryDisposition.alreadyResolved;
}

final class BackgroundProcessTerminationReport {
  const BackgroundProcessTerminationReport.confirmed()
    : rootTerminationConfirmed = true,
      descendantTerminationConfirmed = true,
      descendantDiscoveryConfirmed = true,
      liveDescendantProcessIds = const <int>[],
      error = null;

  const BackgroundProcessTerminationReport.unconfirmed({
    required this.rootTerminationConfirmed,
    required this.descendantTerminationConfirmed,
    this.descendantDiscoveryConfirmed = false,
    this.liveDescendantProcessIds = const <int>[],
    this.error,
  });

  final bool rootTerminationConfirmed;
  final bool descendantTerminationConfirmed;
  final bool descendantDiscoveryConfirmed;
  final List<int> liveDescendantProcessIds;
  final String? error;

  bool get isConfirmed =>
      rootTerminationConfirmed &&
      descendantTerminationConfirmed &&
      descendantDiscoveryConfirmed;
}

typedef BackgroundProcessTerminator =
    Future<BackgroundProcessTerminationReport> Function(
      Process process, {
      required int? processGroupId,
      required List<int> knownDescendantProcessIds,
    });

final class _PendingProcessLaunchLease {
  _PendingProcessLaunchLease({
    required this.owner,
    required this.jobId,
    required this.command,
    required this.workingDirectory,
    required this.resourceKey,
    required this.token,
  });

  final ChatTurnOwner owner;
  final String jobId;
  final String command;
  final String workingDirectory;
  final String resourceKey;
  final String token;
  final Completer<void> _settled = Completer<void>();

  Future<void> get settled => _settled.future;

  void complete() {
    if (!_settled.isCompleted) _settled.complete();
  }
}

final class _BackgroundProcessRecoveryRecord {
  _BackgroundProcessRecoveryRecord({
    required this.receipt,
    required this.lease,
    required this.job,
  });

  final BackgroundProcessRecoveryReceipt receipt;
  final _PendingProcessLaunchLease lease;
  final _BackgroundProcessJob job;
  Future<void> _settlementTail = Future<void>.value();
  bool released = false;

  Future<T> serialize<T>(Future<T> Function() operation) {
    final result = _settlementTail.then((_) => operation());
    _settlementTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

final class _ResolvedBackgroundProcessRecovery {
  const _ResolvedBackgroundProcessRecovery({
    required this.receipt,
    required this.forceAcknowledged,
  });

  final BackgroundProcessRecoveryReceipt receipt;
  final bool forceAcknowledged;
}

Future<BackgroundProcessTerminationReport> _defaultBackgroundProcessTerminator(
  Process process, {
  required int? processGroupId,
  required List<int> knownDescendantProcessIds,
}) async {
  if (Platform.isWindows) {
    return _terminateWindowsProcessTree(process);
  }
  return _terminatePosixProcessTree(
    process,
    processGroupId: processGroupId,
    knownDescendantProcessIds: knownDescendantProcessIds,
  );
}

Future<BackgroundProcessTerminationReport> _terminateWindowsProcessTree(
  Process process,
) async {
  try {
    final result = await Process.run('taskkill', [
      '/PID',
      '${process.pid}',
      '/T',
      '/F',
    ]);
    final rootConfirmed = await _awaitProcessExit(process);
    return result.exitCode == 0 && rootConfirmed
        ? const BackgroundProcessTerminationReport.confirmed()
        : BackgroundProcessTerminationReport.unconfirmed(
            rootTerminationConfirmed: rootConfirmed,
            descendantTerminationConfirmed: result.exitCode == 0,
            descendantDiscoveryConfirmed: result.exitCode == 0,
            error: result.stderr.toString().trim(),
          );
  } catch (error) {
    final rootConfirmed = await _terminateRootOnly(process);
    return BackgroundProcessTerminationReport.unconfirmed(
      rootTerminationConfirmed: rootConfirmed,
      descendantTerminationConfirmed: false,
      error: error.toString(),
    );
  }
}

Future<BackgroundProcessTerminationReport> _terminatePosixProcessTree(
  Process process, {
  required int? processGroupId,
  required List<int> knownDescendantProcessIds,
}) async {
  if (processGroupId != null) {
    Process.killPid(-processGroupId, ProcessSignal.sigterm);
    if (await _awaitProcessExit(process)) {
      return const BackgroundProcessTerminationReport.confirmed();
    }
    Process.killPid(-processGroupId, ProcessSignal.sigkill);
    return await _awaitProcessExit(process)
        ? const BackgroundProcessTerminationReport.confirmed()
        : const BackgroundProcessTerminationReport.unconfirmed(
            rootTerminationConfirmed: false,
            descendantTerminationConfirmed: false,
          );
  }

  final descendants = <int>{...knownDescendantProcessIds}.toList();
  for (final pid in descendants) {
    Process.killPid(pid, ProcessSignal.sigstop);
  }
  process.kill(ProcessSignal.sigstop);
  await Future<void>.delayed(const Duration(milliseconds: 20));

  var discoveryConfirmed = true;
  var descendantSetStabilized = false;
  for (var scan = 0; scan < 8; scan += 1) {
    final snapshot = await _descendantProcessIds(process.pid);
    if (!snapshot.confirmed) {
      discoveryConfirmed = false;
      break;
    }
    final newlyObserved = snapshot.processIds
        .where((pid) => !descendants.contains(pid))
        .toList(growable: false);
    if (newlyObserved.isEmpty) {
      descendantSetStabilized = true;
      break;
    }
    for (final pid in newlyObserved) {
      descendants.add(pid);
      Process.killPid(pid, ProcessSignal.sigstop);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  discoveryConfirmed = discoveryConfirmed && descendantSetStabilized;

  for (final pid in descendants.reversed) {
    Process.killPid(pid, ProcessSignal.sigterm);
    Process.killPid(pid, ProcessSignal.sigcont);
  }
  process.kill(ProcessSignal.sigterm);
  process.kill(ProcessSignal.sigcont);

  final rootConfirmed = await _awaitProcessExit(
    process,
    timeout: const Duration(milliseconds: 300),
  );
  var liveDescendants = await _liveProcessIds(descendants);
  if (!rootConfirmed || liveDescendants.isNotEmpty) {
    for (final pid in liveDescendants.reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    process.kill(ProcessSignal.sigkill);
  }
  final finalRootConfirmed = rootConfirmed || await _awaitProcessExit(process);
  liveDescendants = await _waitForProcessIdsToExit(descendants);
  return finalRootConfirmed && liveDescendants.isEmpty && discoveryConfirmed
      ? const BackgroundProcessTerminationReport.confirmed()
      : BackgroundProcessTerminationReport.unconfirmed(
          rootTerminationConfirmed: finalRootConfirmed,
          descendantTerminationConfirmed:
              discoveryConfirmed && liveDescendants.isEmpty,
          descendantDiscoveryConfirmed: discoveryConfirmed,
          liveDescendantProcessIds: liveDescendants,
          error: discoveryConfirmed
              ? null
              : 'The descendant process set could not be confirmed.',
        );
}

Future<bool> _terminateRootOnly(Process process) async {
  process.kill();
  if (await _awaitProcessExit(process)) return true;
  if (!Platform.isWindows) process.kill(ProcessSignal.sigkill);
  return _awaitProcessExit(process);
}

Future<bool> _awaitProcessExit(
  Process process, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    await process.exitCode.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  } catch (_) {
    return false;
  }
}

final class _DescendantProcessSnapshot {
  const _DescendantProcessSnapshot({
    required this.confirmed,
    required this.processIds,
  });

  final bool confirmed;
  final List<int> processIds;
}

Future<_DescendantProcessSnapshot> _descendantProcessIds(
  int rootProcessId,
) async {
  try {
    final result = await Process.run('ps', const ['-axo', 'pid=,ppid=']);
    if (result.exitCode != 0) {
      return const _DescendantProcessSnapshot(
        confirmed: false,
        processIds: <int>[],
      );
    }
    final children = <int, List<int>>{};
    for (final line in result.stdout.toString().split('\n')) {
      if (line.trim().isEmpty) continue;
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length != 2) {
        return const _DescendantProcessSnapshot(
          confirmed: false,
          processIds: <int>[],
        );
      }
      final pid = int.tryParse(fields[0]);
      final parentPid = int.tryParse(fields[1]);
      if (pid == null || parentPid == null) {
        return const _DescendantProcessSnapshot(
          confirmed: false,
          processIds: <int>[],
        );
      }
      children.putIfAbsent(parentPid, () => <int>[]).add(pid);
    }
    final descendants = <int>[];
    final pending = <int>[rootProcessId];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      final directChildren = children[parent] ?? const <int>[];
      descendants.addAll(directChildren);
      pending.addAll(directChildren);
    }
    return _DescendantProcessSnapshot(confirmed: true, processIds: descendants);
  } catch (_) {
    return const _DescendantProcessSnapshot(
      confirmed: false,
      processIds: <int>[],
    );
  }
}

Future<List<int>> _liveProcessIds(Iterable<int> processIds) async {
  final ids = processIds.toSet().toList(growable: false);
  if (ids.isEmpty) return const <int>[];
  try {
    final result = await Process.run('ps', ['-p', ids.join(','), '-o', 'pid=']);
    final parsed = result.stdout
        .toString()
        .split(RegExp(r'\s+'))
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    if (result.exitCode == 0) return parsed;
    return result.stderr.toString().trim().isEmpty ? parsed : ids;
  } catch (_) {
    return ids;
  }
}

Future<List<int>> _waitForProcessIdsToExit(Iterable<int> processIds) async {
  var live = await _liveProcessIds(processIds);
  for (var attempt = 0; attempt < 20 && live.isNotEmpty; attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    live = await _liveProcessIds(live);
  }
  return live;
}
