import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'file_mutation_path_fence.dart';
import 'filesystem_tools.dart';

part 'file_rollback_checkpoint_models.dart';
part 'file_rollback_single_checkpoint_operations.dart';
part 'file_rollback_store_lifecycle.dart';
part 'file_rollback_turn_checkpoint_operations.dart';
part 'file_rollback_turn_recovery_operations.dart';

class FileRollbackCheckpointStore {
  FileRollbackCheckpointStore({
    FileRollbackSnapshotLoader? snapshotLoader,
    FileRollbackSnapshotRestorer? snapshotRestorer,
  }) : _snapshotLoader = snapshotLoader ?? FilesystemTools.captureTextSnapshot,
       _snapshotRestorer =
           snapshotRestorer ?? FilesystemTools.restoreTextSnapshot;

  static const int _maxSingleChangeCount = 20;
  static const int _maxTurnCheckpointCount = 10;
  static const int _maxConversationCheckpointCount = 10;

  final FileRollbackSnapshotLoader _snapshotLoader;
  final FileRollbackSnapshotRestorer _snapshotRestorer;
  final FileMutationPathFence mutationPathFence = FileMutationPathFence();
  final Map<ChatTurnOwner, _OwnerRollbackState> _states = {};
  final Map<String, List<_CheckpointRef>> _completedByConversation = {};
  final Map<int, _FileTurnRollbackPreviewBinding> _turnPreviewBindings = {};
  final Map<_CheckpointRef, _FileTurnRollbackAttempt> _turnRollbackAttempts =
      {};
  final Map<String, _FileTurnRollbackRecovery> _turnRollbackRecoveries = {};
  final Map<_CheckpointRef, String> _recoveryReceiptByCheckpoint = {};
  final Set<ChatTurnOwner> _clearedOwners = {};
  final Set<String> _retiredConversationIds = {};
  Future<void>? _disposeFuture;
  var _disposed = false;
  int _nextCheckpointToken = 1;

  void push(ChatTurnOwner owner, TextFileSnapshot snapshot) {
    _push(owner, snapshot);
  }

  /// Records an idempotent runtime-owned mutation and returns its exact token.
  ///
  /// Legacy [push] calls remain append-only. Runtime callers supply a
  /// replacement-resistant compensation token so a retry cannot create a
  /// second checkpoint for the same effect.
  String? recordMutationSnapshot(
    ChatTurnOwner owner,
    TextFileSnapshot snapshot, {
    required String compensationToken,
  }) {
    final normalizedCompensationToken = compensationToken.trim();
    if (normalizedCompensationToken.isEmpty ||
        normalizedCompensationToken != compensationToken ||
        _isRetired(owner) ||
        snapshot.error != null) {
      return null;
    }
    final existing = _recordedEntryForCompensation(
      owner,
      normalizedCompensationToken,
    );
    if (existing != null) {
      return existing.recordToken;
    }
    return _push(
      owner,
      snapshot,
      compensationToken: normalizedCompensationToken,
    )?.recordToken;
  }

  /// Removes only the rollback record created for one exact runtime effect.
  bool removeRecordedMutation(
    ChatTurnOwner owner, {
    required String recordToken,
    required String compensationToken,
  }) {
    if (recordToken.trim().isEmpty ||
        recordToken != recordToken.trim() ||
        compensationToken.trim().isEmpty ||
        compensationToken != compensationToken.trim()) {
      return false;
    }
    final state = _states[owner];
    if (state == null) {
      return _isRetired(owner);
    }
    final entry = _recordedEntries(state)
        .cast<_FileRollbackEntry?>()
        .firstWhere(
          (candidate) =>
              candidate?.recordToken == recordToken &&
              candidate?.compensationToken == compensationToken,
          orElse: () => null,
        );
    if (entry == null) {
      return false;
    }

    state.singleChanges.removeWhere((candidate) => identical(candidate, entry));
    state.activeTurnCheckpoint?.entries.removeWhere(
      (candidate) => identical(candidate, entry),
    );
    for (var index = state.turnCheckpoints.length - 1; index >= 0; index--) {
      final checkpoint = state.turnCheckpoints[index];
      if (!checkpoint.entries.any((candidate) => identical(candidate, entry))) {
        continue;
      }
      final remaining = checkpoint.entries
          .where((candidate) => !identical(candidate, entry))
          .toList(growable: false);
      if (remaining.isEmpty) {
        state.turnCheckpoints.removeAt(index);
        _removeCheckpointReferences((owner: owner, token: checkpoint.token));
      } else {
        state.turnCheckpoints[index] = _FileTurnCheckpoint(
          token: checkpoint.token,
          turnId: checkpoint.turnId,
          entries: List<_FileRollbackEntry>.unmodifiable(remaining),
        );
      }
    }
    _removeStateIfEmpty(owner);
    return true;
  }

  _FileRollbackEntry? _push(
    ChatTurnOwner owner,
    TextFileSnapshot snapshot, {
    String? compensationToken,
  }) {
    if (_isRetired(owner) || snapshot.error != null) {
      return null;
    }

    final state = _stateFor(owner);
    final entry = _FileRollbackEntry(
      token: _nextCheckpointToken++,
      path: snapshot.path,
      pathKey:
          snapshot.resolvedPathKey ??
          FileMutationPathFence.lexicalPathKey(snapshot.path),
      existedBefore: snapshot.exists,
      previousContent: snapshot.content,
      compensationToken: compensationToken,
    );
    state.singleChanges.add(entry);
    state.activeTurnCheckpoint?.addFirstEntryForPath(entry);

    if (state.singleChanges.length > _maxSingleChangeCount) {
      state.singleChanges.removeAt(0);
    }
    return entry;
  }

  Future<FileRollbackPreview?> previewLastFileRollbackChange(
    ChatTurnOwner owner,
  ) => _previewLastFileRollbackChange(owner);

  Future<FileRollbackCheckpointPreview?> previewFileRollbackCheckpoint(
    ChatTurnOwner owner,
  ) => _previewFileRollbackCheckpoint(owner);

  Future<McpToolResult> rollbackLastFileChange({
    required ChatTurnOwner owner,
    required String toolName,
  }) => _rollbackLastFileChange(owner: owner, toolName: toolName);

  Future<FileRollbackCheckpointExecutionResult> rollbackFileCheckpoint({
    required ChatTurnOwner owner,
    required String expectedCheckpointToken,
    required String toolName,
  }) => _rollbackFileCheckpoint(
    owner: owner,
    expectedCheckpointToken: expectedCheckpointToken,
    toolName: toolName,
  );

  void beginFileTurnCheckpoint(ChatTurnOwner owner, String turnId) {
    final normalizedTurnId = turnId.trim();
    if (_isRetired(owner) || normalizedTurnId.isEmpty) {
      return;
    }
    final activeCheckpoint = _states[owner]?.activeTurnCheckpoint;
    if (activeCheckpoint?.turnId == normalizedTurnId) {
      return;
    }
    if (activeCheckpoint != null) {
      endFileTurnCheckpoint(owner);
    }
    _stateFor(owner).activeTurnCheckpoint = _FileTurnCheckpoint(
      token: _nextCheckpointToken++,
      turnId: normalizedTurnId,
      entries: <_FileRollbackEntry>[],
    );
  }

  bool endFileTurnCheckpoint(ChatTurnOwner owner) {
    if (_isRetired(owner)) {
      _states.remove(owner);
      return false;
    }
    final state = _states[owner];
    final checkpoint = state?.activeTurnCheckpoint;
    if (state != null) {
      state.activeTurnCheckpoint = null;
      state.singleChanges.clear();
    }
    if (checkpoint == null || checkpoint.entries.isEmpty) {
      _removeStateIfEmpty(owner);
      return false;
    }

    state!.turnCheckpoints.add(checkpoint.toImmutable());
    final reference = (owner: owner, token: checkpoint.token);
    final completed = _completedFor(owner.conversationId)..add(reference);
    if (state.turnCheckpoints.length > _maxTurnCheckpointCount) {
      _evictCheckpoint((
        owner: owner,
        token: state.turnCheckpoints.first.token,
      ));
    }
    if (completed.length > _maxConversationCheckpointCount) {
      _evictCheckpoint(completed.first);
    }
    return true;
  }

  ChatTurnOwner? latestCompletedCheckpointOwner(String conversationId) {
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty) {
      return null;
    }
    final completed = _completedByConversation[normalizedConversationId];
    return completed == null || completed.isEmpty ? null : completed.last.owner;
  }

  Future<FileTurnRollbackPreview?> previewLastFileTurnCheckpoint(
    ChatTurnOwner owner,
  ) => _previewLastFileTurnCheckpoint(owner);

  Future<McpToolResult> rollbackLastFileTurnCheckpoint(
    ChatTurnOwner owner,
    int expectedCheckpointToken,
  ) => _rollbackLastFileTurnCheckpoint(owner, expectedCheckpointToken);

  void clear(ChatTurnOwner owner) {
    _clearedOwners.add(owner);
    _states.remove(owner);
    _turnPreviewBindings.removeWhere((_, binding) => binding.owner == owner);
    final completed = _completedByConversation[owner.conversationId];
    if (completed == null) {
      return;
    }
    final removed = completed.where((item) => item.owner == owner).toSet();
    completed.removeWhere(removed.contains);
    if (completed.isEmpty) {
      _completedByConversation.remove(owner.conversationId);
    }
  }

  Future<void> retireConversation(String conversationId) async {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    _retiredConversationIds.add(normalizedId);
    _states.removeWhere((owner, _) => owner.conversationId == normalizedId);
    _turnPreviewBindings.removeWhere(
      (_, binding) => binding.owner.conversationId == normalizedId,
    );
    _clearedOwners.removeWhere((owner) => owner.conversationId == normalizedId);
    _completedByConversation.remove(normalizedId);

    final attempts = _turnRollbackAttempts.values
        .where(
          (attempt) => attempt.binding.owner.conversationId == normalizedId,
        )
        .toList(growable: false);
    await Future.wait(
      attempts.map((attempt) => attempt.initialSettlement.future),
    );
    final recoveries = _turnRollbackRecoveries.values
        .where(
          (recovery) =>
              recovery.attempt.binding.owner.conversationId == normalizedId,
        )
        .toList(growable: false);
    for (final recovery in recoveries) {
      await _retireTurnRollbackRecovery(recovery);
    }
  }

  _OwnerRollbackState _stateFor(ChatTurnOwner owner) {
    return _states.putIfAbsent(owner, _OwnerRollbackState.new);
  }

  List<_CheckpointRef> _completedFor(String conversationId) {
    return _completedByConversation.putIfAbsent(
      conversationId,
      () => <_CheckpointRef>[],
    );
  }

  void _evictCheckpoint(_CheckpointRef reference) {
    if (_turnRollbackAttempts.containsKey(reference)) {
      return;
    }
    _states[reference.owner]?.turnCheckpoints.removeWhere(
      (checkpoint) => checkpoint.token == reference.token,
    );
    _removeCheckpointReferences(reference);
    _removeStateIfEmpty(reference.owner);
  }

  void _removeCheckpointReferences(_CheckpointRef reference) {
    _turnPreviewBindings.removeWhere(
      (_, binding) => binding.checkpointRef == reference,
    );
    final completed = _completedByConversation[reference.owner.conversationId];
    completed?.remove(reference);
    if (completed?.isEmpty ?? false) {
      _completedByConversation.remove(reference.owner.conversationId);
    }
  }

  void _removeStateIfEmpty(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null ||
        state.singleChanges.isNotEmpty ||
        state.turnCheckpoints.isNotEmpty ||
        state.activeTurnCheckpoint != null) {
      return;
    }
    _states.remove(owner);
  }

  _FileRollbackEntry? _recordedEntryForCompensation(
    ChatTurnOwner owner,
    String compensationToken,
  ) {
    final state = _states[owner];
    if (state == null) return null;
    for (final entry in _recordedEntries(state)) {
      if (entry.compensationToken == compensationToken) {
        return entry;
      }
    }
    return null;
  }

  Iterable<_FileRollbackEntry> _recordedEntries(
    _OwnerRollbackState state,
  ) sync* {
    final seen = <_FileRollbackEntry>{};
    for (final entry in state.singleChanges) {
      if (entry.compensationToken != null && seen.add(entry)) {
        yield entry;
      }
    }
    final active = state.activeTurnCheckpoint;
    if (active != null) {
      for (final entry in active.entries) {
        if (entry.compensationToken != null && seen.add(entry)) {
          yield entry;
        }
      }
    }
    for (final checkpoint in state.turnCheckpoints) {
      for (final entry in checkpoint.entries) {
        if (entry.compensationToken != null && seen.add(entry)) {
          yield entry;
        }
      }
    }
  }

  bool _isFilesystemPayloadSuccess(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is! Map<String, dynamic> || decoded['error'] == null;
    } catch (_) {
      return true;
    }
  }

  Object? _tryDecodeJson(String payload) {
    try {
      return jsonDecode(payload);
    } catch (_) {
      return null;
    }
  }
}
