part of 'file_rollback_checkpoint_store.dart';

extension FileRollbackSingleCheckpointOperations
    on FileRollbackCheckpointStore {
  Future<FileRollbackPreview?> _previewLastFileRollbackChange(
    ChatTurnOwner owner,
  ) async {
    final checkpoint = await _previewFileRollbackCheckpoint(owner);
    if (checkpoint == null) return null;
    return FileRollbackPreview(
      path: checkpoint.path,
      preview: checkpoint.preview,
      summary: checkpoint.summary,
    );
  }

  Future<FileRollbackCheckpointPreview?> _previewFileRollbackCheckpoint(
    ChatTurnOwner owner,
  ) async {
    if (_isRetired(owner)) return null;
    final stack = _states[owner]?.singleChanges;
    final entry = stack == null || stack.isEmpty ? null : stack.last;
    if (entry == null) return null;

    final currentSnapshot = await _snapshotLoader(entry.path);
    final summary = entry.existedBefore
        ? 'Restore the previous contents of this file.'
        : 'Delete the newly created file.';
    final preview = currentSnapshot.error == null
        ? FilesystemTools.buildUnifiedDiff(
            path: entry.path,
            oldContent: currentSnapshot.exists ? currentSnapshot.content : null,
            newContent: entry.existedBefore
                ? (entry.previousContent ?? '')
                : null,
          )
        : 'Diff preview unavailable: ${currentSnapshot.error}\n\n'
              'Rollback target: ${entry.path}\n'
              '$summary';
    return FileRollbackCheckpointPreview(
      owner: owner,
      checkpointToken: _singleFileCheckpointToken(entry, currentSnapshot),
      path: entry.path,
      preview: preview,
      summary: summary,
    );
  }

  Future<McpToolResult> _rollbackLastFileChange({
    required ChatTurnOwner owner,
    required String toolName,
  }) async {
    final checkpoint = await _previewFileRollbackCheckpoint(owner);
    if (checkpoint == null) {
      return _noSingleFileRollbackResult(toolName);
    }
    final execution = await _rollbackFileCheckpoint(
      owner: owner,
      expectedCheckpointToken: checkpoint.checkpointToken,
      toolName: toolName,
    );
    return execution.result ??
        switch (execution.disposition) {
          FileRollbackCheckpointExecutionDisposition.ownerExpiredBeforeEffect =>
            _noSingleFileRollbackResult(toolName),
          FileRollbackCheckpointExecutionDisposition.ownerExpiredAfterEffect ||
          FileRollbackCheckpointExecutionDisposition.effectUncertain =>
            _singleFileRollbackUncertainResult(toolName),
          FileRollbackCheckpointExecutionDisposition.completed ||
          FileRollbackCheckpointExecutionDisposition.checkpointChanged =>
            throw StateError('A completed rollback must carry a result.'),
        };
  }

  Future<FileRollbackCheckpointExecutionResult> _rollbackFileCheckpoint({
    required ChatTurnOwner owner,
    required String expectedCheckpointToken,
    required String toolName,
  }) async {
    final checkpointToken = expectedCheckpointToken.trim();
    if (_isRetired(owner)) {
      return FileRollbackCheckpointExecutionResult(
        owner: owner,
        checkpointToken: checkpointToken,
        disposition:
            FileRollbackCheckpointExecutionDisposition.ownerExpiredBeforeEffect,
      );
    }
    final stack = _states[owner]?.singleChanges;
    final path = stack == null || stack.isEmpty ? null : stack.last.path;
    if (path == null) {
      return _changedSingleFileCheckpointResult(
        owner,
        checkpointToken,
        toolName,
      );
    }
    return mutationPathFence.runExclusive(
      path,
      () => _rollbackFileCheckpointFenced(
        owner: owner,
        expectedCheckpointToken: checkpointToken,
        toolName: toolName,
      ),
    );
  }

  Future<FileRollbackCheckpointExecutionResult> _rollbackFileCheckpointFenced({
    required ChatTurnOwner owner,
    required String expectedCheckpointToken,
    required String toolName,
  }) async {
    final checkpointToken = expectedCheckpointToken.trim();
    if (_isRetired(owner)) {
      return FileRollbackCheckpointExecutionResult(
        owner: owner,
        checkpointToken: checkpointToken,
        disposition:
            FileRollbackCheckpointExecutionDisposition.ownerExpiredBeforeEffect,
      );
    }
    final state = _states[owner];
    final stack = state?.singleChanges;
    final entry = stack == null || stack.isEmpty ? null : stack.last;
    if (entry == null) {
      return _changedSingleFileCheckpointResult(
        owner,
        checkpointToken,
        toolName,
      );
    }

    final TextFileSnapshot currentSnapshot;
    try {
      currentSnapshot = await _snapshotLoader(entry.path);
    } catch (_) {
      return _changedSingleFileCheckpointResult(
        owner,
        checkpointToken,
        toolName,
      );
    }
    if (_isRetired(owner)) {
      return FileRollbackCheckpointExecutionResult(
        owner: owner,
        checkpointToken: checkpointToken,
        disposition:
            FileRollbackCheckpointExecutionDisposition.ownerExpiredBeforeEffect,
      );
    }
    if (!identical(_states[owner], state) ||
        stack!.isEmpty ||
        !identical(stack.last, entry)) {
      return _changedSingleFileCheckpointResult(
        owner,
        checkpointToken,
        toolName,
      );
    }
    if (currentSnapshot.error != null ||
        currentSnapshot.isPathAlias ||
        (currentSnapshot.resolvedPathKey ??
                FileMutationPathFence.lexicalPathKey(currentSnapshot.path)) !=
            entry.pathKey ||
        _singleFileCheckpointToken(entry, currentSnapshot) != checkpointToken) {
      return _changedSingleFileCheckpointResult(
        owner,
        checkpointToken,
        toolName,
      );
    }

    final originalIndex = stack.length - 1;
    stack.removeAt(originalIndex);
    final String payload;
    try {
      payload = await _snapshotRestorer(
        path: entry.path,
        existedBefore: entry.existedBefore,
        content: entry.previousContent,
      );
    } catch (_) {
      _restoreSingleEntryForRetry(owner, state!, entry, originalIndex);
      return FileRollbackCheckpointExecutionResult(
        owner: owner,
        checkpointToken: checkpointToken,
        disposition: FileRollbackCheckpointExecutionDisposition.effectUncertain,
      );
    }
    if (!_isFilesystemPayloadSuccess(payload)) {
      _restoreSingleEntryForRetry(owner, state!, entry, originalIndex);
      return FileRollbackCheckpointExecutionResult(
        owner: owner,
        checkpointToken: checkpointToken,
        disposition: FileRollbackCheckpointExecutionDisposition.effectUncertain,
        result: McpToolResult(
          toolName: toolName,
          result: payload,
          isSuccess: false,
          errorMessage: 'Failed to roll back the last file change',
        ),
      );
    }
    if (_isRetired(owner) || !identical(_states[owner], state)) {
      return FileRollbackCheckpointExecutionResult(
        owner: owner,
        checkpointToken: checkpointToken,
        disposition:
            FileRollbackCheckpointExecutionDisposition.ownerExpiredAfterEffect,
      );
    }

    _removeStateIfEmpty(owner);
    return FileRollbackCheckpointExecutionResult(
      owner: owner,
      checkpointToken: checkpointToken,
      disposition: FileRollbackCheckpointExecutionDisposition.completed,
      result: McpToolResult(
        toolName: toolName,
        result: payload,
        isSuccess: true,
      ),
    );
  }

  McpToolResult _noSingleFileRollbackResult(String toolName) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: 'No recent file change is available to roll back',
    );
  }

  McpToolResult _singleFileRollbackUncertainResult(String toolName) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage:
          'The file change may have been rolled back; inspect the target '
          'before retrying',
    );
  }

  FileRollbackCheckpointExecutionResult _changedSingleFileCheckpointResult(
    ChatTurnOwner owner,
    String checkpointToken,
    String toolName,
  ) {
    return FileRollbackCheckpointExecutionResult(
      owner: owner,
      checkpointToken: checkpointToken,
      disposition: FileRollbackCheckpointExecutionDisposition.checkpointChanged,
      result: McpToolResult(
        toolName: toolName,
        result: '',
        isSuccess: false,
        errorMessage:
            'The file rollback checkpoint changed; preview it again before '
            'rollback',
      ),
    );
  }

  void _restoreSingleEntryForRetry(
    ChatTurnOwner owner,
    _OwnerRollbackState state,
    _FileRollbackEntry entry,
    int originalIndex,
  ) {
    if (_isRetired(owner) || !identical(_states[owner], state)) return;
    final stack = _states[owner]?.singleChanges;
    if (stack == null || stack.any((item) => item.token == entry.token)) return;
    final insertionIndex = originalIndex < stack.length
        ? originalIndex
        : stack.length;
    stack.insert(insertionIndex, entry);
  }

  String _singleFileCheckpointToken(
    _FileRollbackEntry entry,
    TextFileSnapshot currentSnapshot,
  ) {
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'entry': entry.token,
              'path': currentSnapshot.path,
              'exists': currentSnapshot.exists,
              'content': currentSnapshot.content,
              'error': currentSnapshot.error,
              'resolvedPath': currentSnapshot.resolvedPathKey,
              'pathAlias': currentSnapshot.isPathAlias,
            }),
          ),
        )
        .toString();
    return 'single-file-${entry.token}-$fingerprint';
  }
}
