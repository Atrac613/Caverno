part of 'background_process_tools.dart';

/// A running job and the turn that started it, held between owners.
final class _CarriedBackgroundProcessJob {
  const _CarriedBackgroundProcessJob({required this.owner, required this.job});

  final ChatTurnOwner owner;
  final _BackgroundProcessJob job;
}

/// Keeps a running process alive across the turn boundary.
///
/// A turn is not the lifetime of a background process. A release, a build, or
/// a test run routinely outlives the turn that launched it, and session
/// a00b77ce shows the cost of pretending otherwise: an approved production
/// release was terminated 57 seconds in because the turn watching it failed on
/// a rate limit, and the next turn could only report that no job existed.
///
/// Retirement therefore carries running jobs instead of killing them, and the
/// next live owner of the *same conversation* adopts one on first reference.
/// Adoption is per-conversation, never global: it must not hand one thread a
/// job another thread started.
extension BackgroundProcessCarryOver on BackgroundProcessTools {
  /// Moves the owner's still-running jobs out of retirement's reach.
  ///
  /// Called before `_retireState`, which terminates whatever is left in the
  /// state. Exited jobs stay behind so their streams are disposed normally;
  /// only live processes are worth carrying.
  void _carryRunningJobs(ChatTurnOwner owner, _OwnerProcessState state) {
    if (_disposed) return;
    for (final job in state.jobs.values.toList(growable: false)) {
      if (!job.isRunning) continue;
      state.jobs.remove(job.id);
      _carriedJobs.putIfAbsent(
        owner.conversationId,
        () => <String, _CarriedBackgroundProcessJob>{},
      )[job.id] = _CarriedBackgroundProcessJob(
        owner: owner,
        job: job,
      );
      appLog(
        '[BackgroundProcess] Carried ${job.id} (pid ${job.process.pid}) past '
        'generation ${owner.interactionGeneration}; still running: '
        '${job.command}',
      );
    }
  }

  _BackgroundProcessJob? _adoptCarriedJob(ChatTurnOwner owner, String jobId) {
    if (!_canAdopt(owner)) return null;
    final carried = _carriedJobs[owner.conversationId]?[jobId];
    return carried == null ? null : _adoptJob(owner, carried);
  }

  _BackgroundProcessJob? _adoptCarriedRunningJob(
    ChatTurnOwner owner,
    String command,
    String workingDirectory,
  ) {
    if (!_canAdopt(owner)) return null;
    final carried = _carriedJobs[owner.conversationId];
    if (carried == null) return null;
    for (final entry in carried.values) {
      if (entry.job.isRunning &&
          entry.job.command == command &&
          entry.job.workingDirectory == workingDirectory) {
        return _adoptJob(owner, entry);
      }
    }
    return null;
  }

  _BackgroundProcessJob _adoptJob(
    ChatTurnOwner owner,
    _CarriedBackgroundProcessJob carried,
  ) {
    final pool = _carriedJobs[carried.owner.conversationId];
    pool?.remove(carried.job.id);
    if (pool != null && pool.isEmpty) {
      _carriedJobs.remove(carried.owner.conversationId);
    }
    _ownerStates
            .putIfAbsent(owner, _OwnerProcessState.new)
            .jobs[carried.job.id] =
        carried.job;
    appLog(
      '[BackgroundProcess] Adopted ${carried.job.id} '
      '(pid ${carried.job.process.pid}) from generation '
      '${carried.owner.interactionGeneration} into '
      '${owner.interactionGeneration}',
    );
    return carried.job;
  }

  /// Whether [owner] is a live turn that may take over a carried job.
  ///
  /// A retired owner never adopts: its turn is over, and handing it back the
  /// job it just released would resurrect state the release was meant to end.
  bool _canAdopt(ChatTurnOwner owner) =>
      !_disposed &&
      !_retiredOwners.contains(owner) &&
      !(_ownerStates[owner]?.retired ?? false);

  /// Ends carried jobs through the same recovery path a retiring turn used.
  ///
  /// Carrying moved *when* termination happens, not *how*: an unconfirmed kill
  /// still leaves a receipt and holds the resource fence, so a caller can
  /// reconcile it or explicitly accept the risk exactly as before.
  Future<void> _terminateCarriedJobs({String? conversationId}) async {
    final conversationIds = conversationId == null
        ? _carriedJobs.keys.toList(growable: false)
        : <String>[conversationId];
    final terminations = <Future<void>>[];
    for (final id in conversationIds) {
      final carried = _carriedJobs.remove(id);
      if (carried == null) continue;
      for (final entry in carried.values) {
        appLog(
          '[BackgroundProcess] Terminating carried ${entry.job.id} '
          '(pid ${entry.job.process.pid}): ${entry.job.command}',
        );
        final state = _ownerStates.putIfAbsent(
          entry.owner,
          _OwnerProcessState.new,
        );
        state.jobs[entry.job.id] = entry.job;
        final record = _registerExistingJobRecovery(
          entry.owner,
          state,
          entry.job,
        );
        unawaited(_attemptRecovery(record));
        // The lease, not the attempt: an unconfirmed kill holds the lease until
        // a caller reconciles or accepts it, and this call is not finished
        // while a process it claims to have ended may still be alive.
        terminations.add(record.lease.settled);
      }
    }
    await Future.wait<void>(terminations);
  }
}
