part of 'file_rollback_checkpoint_store.dart';

extension FileRollbackTurnRecoveryOperations on FileRollbackCheckpointStore {
  /// Reconciles only the recovery attempt identified by an exact receipt.
  ///
  /// All checkpoint paths remain fenced until this method confirms every
  /// attempted path is back at its exact pre-rollback snapshot.
  Future<McpToolResult> reconcileFileTurnRollbackRecovery({
    required ChatTurnOwner owner,
    required String recoveryReceipt,
  }) async {
    final normalizedReceipt = recoveryReceipt.trim();
    if (normalizedReceipt.isEmpty || normalizedReceipt != recoveryReceipt) {
      return _unknownTurnRollbackRecoveryResult();
    }
    final recovery = _turnRollbackRecoveries[normalizedReceipt];
    if (recovery == null ||
        recovery.attempt.binding.owner != owner ||
        recovery.attempt.recoveryReceipt != normalizedReceipt) {
      return _unknownTurnRollbackRecoveryResult();
    }

    FileMutationPathTransactionSettlement<_FileTurnRollbackSettlement>?
    settlement;
    try {
      settlement = await mutationPathFence.settleTransactionAll(
        transactionToken: recovery.attempt.transactionToken,
        operation: () => _reconcileTurnRollbackRecovery(recovery),
        releaseWhen: (value) => value.releaseFence,
      );
    } catch (_) {
      settlement = null;
    }
    if (settlement == null) {
      return _turnRollbackRecoveryRequiredResult(
        recovery.attempt.binding.checkpoint.turnId,
        normalizedReceipt,
        'The exact filesystem recovery lease is unavailable.',
      );
    }
    return settlement.value.result;
  }

  Future<_FileTurnRollbackSettlement> _reconcileTurnRollbackRecovery(
    _FileTurnRollbackRecovery recovery,
  ) async {
    final attempt = recovery.attempt;
    final compensation = await _compensateTurnRollbackAttempt(attempt);
    if (!compensation.confirmed) {
      final updated = _FileTurnRollbackRecovery(
        attempt: attempt,
        lastFailure: compensation.failure,
      );
      _turnRollbackRecoveries[attempt.recoveryReceipt] = updated;
      return _FileTurnRollbackSettlement(
        result: _turnRollbackRecoveryRequiredResult(
          attempt.binding.checkpoint.turnId,
          attempt.recoveryReceipt,
          compensation.failure,
          paths: compensation.paths,
        ),
        releaseFence: false,
        recovery: updated,
      );
    }

    _turnRollbackRecoveries.remove(attempt.recoveryReceipt);
    _recoveryReceiptByCheckpoint.remove(attempt.checkpointRef);
    _turnRollbackAttempts.remove(attempt.checkpointRef);
    return _FileTurnRollbackSettlement(
      result: McpToolResult(
        toolName: 'rollback_last_turn_file_changes',
        result: jsonEncode({
          'ok': true,
          'reconciled': true,
          'turn_id': attempt.binding.checkpoint.turnId,
          'checkpoint_retained': _isExactTurnCheckpoint(
            attempt.binding.owner,
            attempt.state,
            attempt.binding.checkpoint,
          ),
          'compensated': compensation.paths,
        }),
        isSuccess: true,
      ),
      releaseFence: true,
    );
  }

  Future<_FileTurnRollbackSettlement> _settleTurnRollbackFailure(
    _FileTurnRollbackAttempt attempt,
    String failure,
    List<Map<String, Object?>> restored,
  ) async {
    if (attempt.attemptedPaths.isEmpty) {
      return _turnRollbackReleasedFailure(
        McpToolResult(
          toolName: 'rollback_last_turn_file_changes',
          result: jsonEncode({
            'ok': false,
            'turn_id': attempt.binding.checkpoint.turnId,
            'restored': restored.reversed.toList(growable: false),
            'effects_started': false,
          }),
          isSuccess: false,
          errorMessage: failure,
        ),
      );
    }

    final compensation = await _compensateTurnRollbackAttempt(attempt);
    if (compensation.confirmed) {
      return _turnRollbackReleasedFailure(
        McpToolResult(
          toolName: 'rollback_last_turn_file_changes',
          result: jsonEncode({
            'ok': false,
            'turn_id': attempt.binding.checkpoint.turnId,
            'restored': restored.reversed.toList(growable: false),
            'compensated': true,
            'compensation': compensation.paths,
          }),
          isSuccess: false,
          errorMessage:
              '$failure Every attempted path was restored to its exact '
              'pre-rollback state.',
        ),
      );
    }

    final recovery = _FileTurnRollbackRecovery(
      attempt: attempt,
      lastFailure: compensation.failure,
    );
    return _FileTurnRollbackSettlement(
      result: _turnRollbackRecoveryRequiredResult(
        attempt.binding.checkpoint.turnId,
        attempt.recoveryReceipt,
        compensation.failure,
        paths: compensation.paths,
      ),
      releaseFence: false,
      recovery: recovery,
    );
  }

  Future<_FileTurnRollbackCompensation> _compensateTurnRollbackAttempt(
    _FileTurnRollbackAttempt attempt,
  ) async {
    final results = <Map<String, Object?>>[];
    final failures = <String>[];
    for (final attempted in attempt.attemptedPaths.reversed) {
      final beforeCompensation = await _loadTurnRollbackSnapshot(
        attempted.entry.path,
      );
      if (_sameTurnRollbackSnapshot(
        attempted.preRollbackSnapshot,
        beforeCompensation,
      )) {
        attempted.expectedCurrentSnapshot = beforeCompensation;
        results.add({
          'path': attempted.entry.path,
          'confirmed': true,
          'already_compensated': true,
        });
        continue;
      }

      final expectedCurrent = attempted.expectedCurrentSnapshot;
      if (expectedCurrent == null ||
          !_sameTurnRollbackSnapshot(expectedCurrent, beforeCompensation)) {
        failures.add(attempted.entry.path);
        results.add({
          'path': attempted.entry.path,
          'confirmed': false,
          'conflict': true,
        });
        continue;
      }

      String? payload;
      Object? thrown;
      try {
        payload = await _snapshotRestorer(
          path: attempted.entry.path,
          existedBefore: attempted.preRollbackSnapshot.exists,
          content: attempted.preRollbackSnapshot.content,
        );
      } catch (error) {
        thrown = error;
      }
      final current = await _loadTurnRollbackSnapshot(attempted.entry.path);
      attempted.expectedCurrentSnapshot = current;
      final confirmed = _sameTurnRollbackSnapshot(
        attempted.preRollbackSnapshot,
        current,
      );
      if (!confirmed) {
        failures.add(attempted.entry.path);
      }
      results.add({
        'path': attempted.entry.path,
        'confirmed': confirmed,
        if (payload != null) 'result': _tryDecodeJson(payload) ?? payload,
        if (thrown != null) 'error': '$thrown',
      });
    }
    return _FileTurnRollbackCompensation(
      confirmed: failures.isEmpty,
      paths: List<Map<String, Object?>>.unmodifiable(results),
      failure: failures.isEmpty
          ? ''
          : 'Conditional compensation remains unconfirmed for: '
                '${failures.join(', ')}',
    );
  }

  bool _turnRollbackTargetIsConfirmed(
    _FileRollbackEntry entry,
    TextFileSnapshot current,
  ) {
    return current.error == null &&
        !current.isPathAlias &&
        (current.resolvedPathKey ??
                FileMutationPathFence.lexicalPathKey(current.path)) ==
            entry.pathKey &&
        current.exists == entry.existedBefore &&
        (!entry.existedBefore ||
            current.content == (entry.previousContent ?? ''));
  }

  Future<TextFileSnapshot> _loadTurnRollbackSnapshot(String path) async {
    try {
      return await _snapshotLoader(path);
    } catch (error) {
      return TextFileSnapshot(
        path: path,
        exists: false,
        error: 'Snapshot capture failed: $error',
      );
    }
  }

  bool _sameTurnRollbackSnapshot(
    TextFileSnapshot expected,
    TextFileSnapshot actual,
  ) {
    return expected.path == actual.path &&
        expected.exists == actual.exists &&
        expected.content == actual.content &&
        expected.error == actual.error &&
        expected.resolvedPathKey == actual.resolvedPathKey &&
        expected.isPathAlias == actual.isPathAlias;
  }

  String _turnRollbackStateFingerprint(
    _FileTurnCheckpoint checkpoint,
    List<_FileTurnRollbackBoundSnapshot> snapshots,
  ) {
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'checkpoint': checkpoint.token,
              'turnId': checkpoint.turnId,
              'snapshots': [
                for (final bound in snapshots)
                  {
                    'entry': bound.entry.token,
                    'path': bound.entry.path,
                    'currentPath': bound.snapshot.path,
                    'exists': bound.snapshot.exists,
                    'content': bound.snapshot.content,
                    'error': bound.snapshot.error,
                    'resolvedPath': bound.snapshot.resolvedPathKey,
                    'pathAlias': bound.snapshot.isPathAlias,
                  },
              ],
            }),
          ),
        )
        .toString();
  }

  String _turnRollbackExactToken(
    String prefix,
    _FileTurnRollbackPreviewBinding binding,
  ) {
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'owner': {
                'conversationId': binding.owner.conversationId,
                'interactionGeneration': binding.owner.interactionGeneration,
              },
              'previewToken': binding.previewToken,
              'checkpoint': binding.checkpoint.token,
              'state': binding.currentStateFingerprint,
            }),
          ),
        )
        .toString();
    return '$prefix-$digest';
  }

  String _buildTurnRollbackPreview(
    _FileRollbackEntry entry,
    TextFileSnapshot currentSnapshot,
  ) {
    final summary = entry.existedBefore
        ? 'Restore the previous contents of this file.'
        : 'Delete the newly created file.';
    if (currentSnapshot.error != null) {
      return 'Diff preview unavailable: ${currentSnapshot.error}\n\n'
          'Rollback target: ${entry.path}\n'
          '$summary';
    }
    return FilesystemTools.buildUnifiedDiff(
      path: entry.path,
      oldContent: currentSnapshot.exists ? currentSnapshot.content : null,
      newContent: entry.existedBefore ? (entry.previousContent ?? '') : null,
    );
  }

  _FileTurnRollbackSettlement _turnRollbackReleasedFailure(
    McpToolResult result,
  ) {
    return _FileTurnRollbackSettlement(result: result, releaseFence: true);
  }

  McpToolResult _noTurnCheckpointResult() {
    return const McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: '',
      isSuccess: false,
      errorMessage: 'No recent turn file checkpoint is available to roll back',
    );
  }

  McpToolResult _changedTurnCheckpointResult() {
    return const McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: '',
      isSuccess: false,
      errorMessage:
          'The turn file checkpoint changed; preview it again before rollback',
    );
  }

  McpToolResult _unknownTurnRollbackRecoveryResult() {
    return const McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: '',
      isSuccess: false,
      errorMessage: 'No exact turn rollback recovery matches this receipt',
    );
  }

  McpToolResult _turnRollbackRecoveryRequiredResult(
    String turnId,
    String recoveryReceipt,
    String failure, {
    List<Map<String, Object?>> paths = const [],
  }) {
    return McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: jsonEncode({
        'ok': false,
        'turn_id': turnId,
        'recovery_required': true,
        'recovery_receipt': recoveryReceipt,
        if (paths.isNotEmpty) 'compensation': paths,
      }),
      isSuccess: false,
      errorMessage:
          '$failure The affected paths remain fenced until exact '
          'reconciliation.',
    );
  }

  Future<void> _retireTurnRollbackRecovery(
    _FileTurnRollbackRecovery recovery,
  ) async {
    final attempt = recovery.attempt;
    try {
      final settlement = await mutationPathFence.settleTransactionAll<void>(
        transactionToken: attempt.transactionToken,
        operation: () async {
          await _compensateTurnRollbackAttempt(attempt);
          _forgetTurnRollbackRecovery(attempt);
        },
        releaseWhen: (_) => true,
      );
      if (settlement != null) {
        return;
      }
    } catch (_) {
      // A concurrent exact reconciliation or store reset may own settlement.
    }
    _forgetTurnRollbackRecovery(attempt);
    try {
      mutationPathFence.finishTransactionAllByToken(attempt.transactionToken);
    } on ArgumentError {
      // The internally generated token is exact; tolerate defensive resets.
    }
  }

  void _forgetTurnRollbackRecovery(_FileTurnRollbackAttempt attempt) {
    _turnRollbackRecoveries.remove(attempt.recoveryReceipt);
    _recoveryReceiptByCheckpoint.remove(attempt.checkpointRef);
    _turnRollbackAttempts.remove(attempt.checkpointRef);
  }
}
