part of 'file_rollback_checkpoint_store.dart';

extension FileRollbackTurnCheckpointOperations on FileRollbackCheckpointStore {
  Future<FileTurnRollbackPreview?> _previewLastFileTurnCheckpoint(
    ChatTurnOwner owner,
  ) async {
    if (_isRetired(owner)) return null;
    final state = _states[owner];
    final stack = state?.turnCheckpoints;
    final checkpoint = stack == null || stack.isEmpty ? null : stack.last;
    if (state == null || checkpoint == null) return null;
    final checkpointRef = (owner: owner, token: checkpoint.token);
    if (_turnRollbackAttempts.containsKey(checkpointRef)) return null;

    return mutationPathFence.runExclusiveAll(
      checkpoint.entries.map((entry) => entry.path),
      () async {
        if (!_isExactTurnCheckpoint(owner, state, checkpoint) ||
            _turnRollbackAttempts.containsKey(checkpointRef)) {
          return null;
        }
        final snapshots = <_FileTurnRollbackBoundSnapshot>[];
        final previews = <String>[];
        for (final entry in checkpoint.entries) {
          final snapshot = await _loadTurnRollbackSnapshot(entry.path);
          snapshots.add(
            _FileTurnRollbackBoundSnapshot(entry: entry, snapshot: snapshot),
          );
          previews.add(_buildTurnRollbackPreview(entry, snapshot));
        }
        if (!_isExactTurnCheckpoint(owner, state, checkpoint) ||
            _turnRollbackAttempts.containsKey(checkpointRef)) {
          return null;
        }

        final previewToken = _nextCheckpointToken++;
        final fingerprint = _turnRollbackStateFingerprint(
          checkpoint,
          snapshots,
        );
        final binding = _FileTurnRollbackPreviewBinding(
          owner: owner,
          previewToken: previewToken,
          checkpoint: checkpoint,
          currentStateFingerprint: fingerprint,
          snapshots: List<_FileTurnRollbackBoundSnapshot>.unmodifiable(
            snapshots,
          ),
        );
        _turnPreviewBindings.removeWhere(
          (_, candidate) => candidate.checkpointRef == checkpointRef,
        );
        _turnPreviewBindings[previewToken] = binding;
        final count = checkpoint.entries.length;
        return FileTurnRollbackPreview(
          owner: owner,
          checkpointToken: previewToken,
          turnId: checkpoint.turnId,
          paths: checkpoint.entries
              .map((entry) => entry.path)
              .toList(growable: false),
          preview: previews.join('\n\n'),
          summary: count == 1
              ? 'Revert the last agent turn file change.'
              : 'Revert $count file changes from the last agent turn.',
          currentStateFingerprint: fingerprint,
        );
      },
    );
  }

  Future<McpToolResult> _rollbackLastFileTurnCheckpoint(
    ChatTurnOwner owner,
    int expectedCheckpointToken,
  ) async {
    final binding = _turnPreviewBindings[expectedCheckpointToken];
    if (binding == null) {
      final checkpoints = _states[owner]?.turnCheckpoints;
      return checkpoints == null || checkpoints.isEmpty
          ? _noTurnCheckpointResult()
          : _changedTurnCheckpointResult();
    }
    if (binding.owner != owner) {
      return _changedTurnCheckpointResult();
    }
    final recoveryReceipt = _recoveryReceiptByCheckpoint[binding.checkpointRef];
    if (recoveryReceipt != null) {
      return _turnRollbackRecoveryRequiredResult(
        binding.checkpoint.turnId,
        recoveryReceipt,
        'An earlier rollback attempt still requires exact reconciliation.',
      );
    }
    if (_isRetired(owner)) return _noTurnCheckpointResult();
    final state = _states[owner];
    if (state == null ||
        !_isExactTurnCheckpoint(owner, state, binding.checkpoint) ||
        _turnRollbackAttempts.containsKey(binding.checkpointRef)) {
      return _changedTurnCheckpointResult();
    }

    final transactionToken = _turnRollbackExactToken(
      'turn-rollback-transaction',
      binding,
    );
    final recoveryToken = _turnRollbackExactToken(
      'turn-rollback-recovery',
      binding,
    );
    final attempt = _FileTurnRollbackAttempt(
      binding: binding,
      state: state,
      transactionToken: transactionToken,
      recoveryReceipt: recoveryToken,
    );
    _turnRollbackAttempts[binding.checkpointRef] = attempt;

    FileMutationPathGroupTransaction? transaction;
    var retainFence = false;
    try {
      transaction = await mutationPathFence.beginTransactionAll(
        paths: binding.checkpoint.entries.map((entry) => entry.path),
        transactionToken: transactionToken,
      );
      final settlement = await _executeTurnRollback(attempt);
      final recovery = settlement.recovery;
      if (recovery != null) {
        _turnRollbackRecoveries[recoveryToken] = recovery;
        _recoveryReceiptByCheckpoint[binding.checkpointRef] = recoveryToken;
        retainFence = true;
      }
      return settlement.result;
    } catch (error) {
      final settlement = await _settleTurnRollbackFailure(
        attempt,
        'Unexpected rollback boundary failure: $error',
        const <Map<String, Object?>>[],
      );
      final recovery = settlement.recovery;
      if (recovery != null && transaction != null) {
        _turnRollbackRecoveries[recoveryToken] = recovery;
        _recoveryReceiptByCheckpoint[binding.checkpointRef] = recoveryToken;
        retainFence = true;
      }
      return settlement.result;
    } finally {
      if (!retainFence) {
        _turnRollbackAttempts.remove(binding.checkpointRef);
        if (transaction != null) {
          try {
            mutationPathFence.finishTransactionAll(transaction);
          } on StateError {
            // A store-wide reset may already have released this exact lease.
          }
        }
      }
      if (!attempt.initialSettlement.isCompleted) {
        attempt.initialSettlement.complete();
      }
    }
  }

  Future<_FileTurnRollbackSettlement> _executeTurnRollback(
    _FileTurnRollbackAttempt attempt,
  ) async {
    final binding = attempt.binding;
    if (!_isExactTurnRollbackAttempt(attempt)) {
      return _turnRollbackReleasedFailure(_noTurnCheckpointResult());
    }

    final executionSnapshots = <_FileTurnRollbackBoundSnapshot>[];
    for (var index = 0; index < binding.snapshots.length; index++) {
      final bound = binding.snapshots[index];
      final current = await _loadTurnRollbackSnapshot(bound.entry.path);
      if (!_sameTurnRollbackSnapshot(bound.snapshot, current)) {
        return _turnRollbackReleasedFailure(_changedTurnCheckpointResult());
      }
      executionSnapshots.add(
        _FileTurnRollbackBoundSnapshot(entry: bound.entry, snapshot: current),
      );
    }
    if (!_isExactTurnRollbackAttempt(attempt) ||
        _turnRollbackStateFingerprint(binding.checkpoint, executionSnapshots) !=
            binding.currentStateFingerprint) {
      return _turnRollbackReleasedFailure(_changedTurnCheckpointResult());
    }
    if (executionSnapshots.any(
      (bound) =>
          bound.snapshot.error != null ||
          bound.snapshot.isPathAlias ||
          (bound.snapshot.resolvedPathKey ??
                  FileMutationPathFence.lexicalPathKey(bound.snapshot.path)) !=
              bound.entry.pathKey,
    )) {
      return _turnRollbackReleasedFailure(_changedTurnCheckpointResult());
    }

    final restored = <Map<String, Object?>>[];
    for (final bound in executionSnapshots.reversed) {
      if (!_isExactTurnRollbackAttempt(attempt)) {
        return _settleTurnRollbackFailure(
          attempt,
          'The rollback owner expired before the next filesystem effect.',
          restored,
        );
      }
      final immediateCurrent = await _loadTurnRollbackSnapshot(
        bound.entry.path,
      );
      if (!_sameTurnRollbackSnapshot(bound.snapshot, immediateCurrent)) {
        return _settleTurnRollbackFailure(
          attempt,
          'A rollback target changed after preview.',
          restored,
        );
      }
      if (!_isExactTurnRollbackAttempt(attempt)) {
        return _settleTurnRollbackFailure(
          attempt,
          'The rollback owner expired before the next filesystem effect.',
          restored,
        );
      }

      final pathAttempt = _FileTurnRollbackPathAttempt(
        entry: bound.entry,
        preRollbackSnapshot: bound.snapshot,
      );
      attempt.attemptedPaths.add(pathAttempt);
      String? payload;
      Object? thrown;
      try {
        payload = await _snapshotRestorer(
          path: bound.entry.path,
          existedBefore: bound.entry.existedBefore,
          content: bound.entry.previousContent,
        );
      } catch (error) {
        thrown = error;
      }
      final postAttemptSnapshot = await _loadTurnRollbackSnapshot(
        bound.entry.path,
      );
      pathAttempt.expectedCurrentSnapshot = postAttemptSnapshot;
      final targetConfirmed = _turnRollbackTargetIsConfirmed(
        bound.entry,
        postAttemptSnapshot,
      );
      final payloadSucceeded =
          payload != null && _isFilesystemPayloadSuccess(payload);
      restored.add({
        'path': bound.entry.path,
        'ok': payloadSucceeded && targetConfirmed && thrown == null,
        if (payload != null) 'result': _tryDecodeJson(payload) ?? payload,
        if (thrown != null) 'error': '$thrown',
      });
      if (thrown != null || !payloadSucceeded || !targetConfirmed) {
        return _settleTurnRollbackFailure(
          attempt,
          'A filesystem restore did not settle exactly.',
          restored,
        );
      }
    }

    if (!_isExactTurnRollbackAttempt(attempt)) {
      return _settleTurnRollbackFailure(
        attempt,
        'The rollback owner expired before final settlement.',
        restored,
      );
    }
    attempt.state.turnCheckpoints.removeLast();
    _removeCheckpointReferences(attempt.checkpointRef);
    _removeStateIfEmpty(binding.owner);
    return _FileTurnRollbackSettlement(
      result: McpToolResult(
        toolName: 'rollback_last_turn_file_changes',
        result: jsonEncode({
          'ok': true,
          'turn_id': binding.checkpoint.turnId,
          'restored': restored.reversed.toList(growable: false),
        }),
        isSuccess: true,
      ),
      releaseFence: true,
    );
  }

  bool _isExactTurnCheckpoint(
    ChatTurnOwner owner,
    _OwnerRollbackState state,
    _FileTurnCheckpoint checkpoint,
  ) {
    final current = _states[owner];
    final completed = _completedByConversation[owner.conversationId];
    final checkpointRef = (owner: owner, token: checkpoint.token);
    return !_isRetired(owner) &&
        identical(current, state) &&
        state.turnCheckpoints.isNotEmpty &&
        identical(state.turnCheckpoints.last, checkpoint) &&
        completed != null &&
        completed.isNotEmpty &&
        completed.last == checkpointRef;
  }

  bool _isExactTurnRollbackAttempt(_FileTurnRollbackAttempt attempt) {
    return identical(_turnRollbackAttempts[attempt.checkpointRef], attempt) &&
        _isExactTurnCheckpoint(
          attempt.binding.owner,
          attempt.state,
          attempt.binding.checkpoint,
        );
  }
}
