part of 'background_process_tools.dart';

extension _BackgroundProcessRecoveryRegistry on BackgroundProcessTools {
  _PendingProcessLaunchLease? _acquireLaunchLease({
    required _OwnerProcessState state,
    required ChatTurnOwner owner,
    required String jobId,
    required String command,
    required String workingDirectory,
    required String resourceKey,
  }) {
    final fences = _resourceFences[resourceKey];
    if (fences != null && fences.isNotEmpty) return null;
    final token = _newRecoveryToken();
    final lease = _PendingProcessLaunchLease(
      owner: owner,
      jobId: jobId,
      command: command,
      workingDirectory: workingDirectory,
      resourceKey: resourceKey,
      token: token,
    );
    state.pendingStarts[token] = lease;
    _resourceFences.putIfAbsent(resourceKey, () => <String>{}).add(token);
    return lease;
  }

  _BackgroundProcessRecoveryRecord _registerRecovery(
    _OwnerProcessState state,
    _PendingProcessLaunchLease lease,
    _BackgroundProcessJob job,
  ) {
    final receipt = BackgroundProcessRecoveryReceipt._(
      owner: lease.owner,
      jobId: lease.jobId,
      processId: job.process.pid,
      command: lease.command,
      workingDirectory: lease.workingDirectory,
      recoveryToken: lease.token,
      processGroupId: job.processGroupId,
    );
    final record = _BackgroundProcessRecoveryRecord(
      receipt: receipt,
      lease: lease,
      job: job,
    );
    _recoveries[lease.token] = record;
    return record;
  }

  _BackgroundProcessRecoveryRecord _registerExistingJobRecovery(
    ChatTurnOwner owner,
    _OwnerProcessState state,
    _BackgroundProcessJob job,
  ) {
    final existing = _recoveryForJob(owner, job.id);
    if (existing != null) return existing;
    state.jobs.remove(job.id);
    final resourceKey = _resourceKey(
      job.command,
      Directory(job.workingDirectory),
    );
    final token = _newRecoveryToken();
    final lease = _PendingProcessLaunchLease(
      owner: owner,
      jobId: job.id,
      command: job.command,
      workingDirectory: job.workingDirectory,
      resourceKey: resourceKey,
      token: token,
    );
    state.pendingStarts[token] = lease;
    _resourceFences.putIfAbsent(resourceKey, () => <String>{}).add(token);
    return _registerRecovery(state, lease, job);
  }

  void _promoteRecovery(
    _OwnerProcessState state,
    _BackgroundProcessRecoveryRecord record,
  ) {
    _recoveries.remove(record.receipt.recoveryToken);
    record.released = true;
    state.jobs[record.job.id] = record.job;
    _settleLaunchLease(state, record.lease);
  }

  Future<BackgroundProcessRecoveryAcknowledgement> _attemptRecovery(
    _BackgroundProcessRecoveryRecord record,
  ) {
    return record.serialize(() async {
      if (record.released) {
        final resolved = _resolvedRecoveries[record.receipt.recoveryToken];
        return BackgroundProcessRecoveryAcknowledgement(
          disposition: resolved?.forceAcknowledged == true
              ? BackgroundProcessRecoveryDisposition.riskAcknowledged
              : BackgroundProcessRecoveryDisposition.alreadyResolved,
          receipt: record.receipt,
        );
      }
      final report = await record.job.terminate();
      if (!report.isConfirmed) {
        return BackgroundProcessRecoveryAcknowledgement(
          disposition:
              BackgroundProcessRecoveryDisposition.terminationUnconfirmed,
          receipt: record.receipt,
          error: report.error,
        );
      }
      await _releaseRecovery(record, forceAcknowledged: false);
      return BackgroundProcessRecoveryAcknowledgement(
        disposition: BackgroundProcessRecoveryDisposition.terminationConfirmed,
        receipt: record.receipt,
      );
    });
  }

  Future<void> _releaseRecovery(
    _BackgroundProcessRecoveryRecord record, {
    required bool forceAcknowledged,
  }) async {
    if (record.released) return;
    record.released = true;
    try {
      await record.job.dispose();
    } catch (_) {
      // Stream cleanup cannot reopen a confirmed or explicitly accepted effect.
    }
    _recoveries.remove(record.receipt.recoveryToken);
    _rememberResolvedRecovery(
      record.receipt,
      forceAcknowledged: forceAcknowledged,
    );
    final state = _ownerStates[record.receipt.owner];
    if (state != null) {
      state.jobs.remove(record.receipt.jobId);
      _settleLaunchLease(state, record.lease);
    } else {
      _releaseResourceFence(record.lease);
      record.lease.complete();
    }
  }

  void _settleLaunchLease(
    _OwnerProcessState state,
    _PendingProcessLaunchLease lease,
  ) {
    state.pendingStarts.remove(lease.token);
    _releaseResourceFence(lease);
    lease.complete();
    if (!state.retired &&
        state.pendingStarts.isEmpty &&
        state.jobs.isEmpty &&
        identical(_ownerStates[lease.owner], state)) {
      _ownerStates.remove(lease.owner);
    }
  }

  void _releaseResourceFence(_PendingProcessLaunchLease lease) {
    final fences = _resourceFences[lease.resourceKey];
    fences?.remove(lease.token);
    if (fences?.isEmpty == true) {
      _resourceFences.remove(lease.resourceKey);
    }
  }

  Future<void> _retireState(
    ChatTurnOwner owner,
    _OwnerProcessState state,
  ) async {
    final jobs = state.jobs.values.toList(growable: false);
    final records = jobs
        .map((job) => _registerExistingJobRecovery(owner, state, job))
        .toList(growable: false);
    final pendingSettlements = state.pendingStarts.values
        .map((lease) => lease.settled)
        .toList(growable: false);
    for (final record in records) {
      unawaited(_attemptRecovery(record));
    }
    await Future.wait<void>(pendingSettlements);
    if (identical(_ownerStates[owner], state)) {
      _ownerStates.remove(owner);
    }
  }

  _BackgroundProcessRecoveryRecord? _recoveryForJob(
    ChatTurnOwner owner,
    String jobId,
  ) {
    for (final record in _recoveries.values) {
      if (record.receipt.owner == owner && record.receipt.jobId == jobId) {
        return record;
      }
    }
    return null;
  }

  void _rememberResolvedRecovery(
    BackgroundProcessRecoveryReceipt receipt, {
    required bool forceAcknowledged,
  }) {
    _resolvedRecoveries[receipt.recoveryToken] =
        _ResolvedBackgroundProcessRecovery(
          receipt: receipt,
          forceAcknowledged: forceAcknowledged,
        );
    while (_resolvedRecoveries.length > 128) {
      _resolvedRecoveries.remove(_resolvedRecoveries.keys.first);
    }
  }

  String _resourceKey(String command, Directory workingDirectory) {
    var canonicalDirectory = workingDirectory.absolute.path;
    try {
      canonicalDirectory = workingDirectory.resolveSymbolicLinksSync();
    } catch (_) {
      // The validated absolute path remains an exact conservative fallback.
    }
    return jsonEncode([canonicalDirectory, command]);
  }

  String _newRecoveryToken() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
