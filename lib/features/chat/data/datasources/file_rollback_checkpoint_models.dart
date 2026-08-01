part of 'file_rollback_checkpoint_store.dart';

class FileRollbackPreview {
  const FileRollbackPreview({
    required this.path,
    required this.preview,
    required this.summary,
  });

  final String path, preview, summary;
}

/// Exact single-file rollback preview bound to one owner and file state.
class FileRollbackCheckpointPreview {
  const FileRollbackCheckpointPreview({
    required this.owner,
    required this.checkpointToken,
    required this.path,
    required this.preview,
    required this.summary,
  });

  final ChatTurnOwner owner;
  final String checkpointToken;
  final String path, preview, summary;
}

enum FileRollbackCheckpointExecutionDisposition {
  completed,
  checkpointChanged,
  ownerExpiredBeforeEffect,
  ownerExpiredAfterEffect,
  effectUncertain,
}

/// Exact completion from a conditional single-file rollback.
class FileRollbackCheckpointExecutionResult {
  const FileRollbackCheckpointExecutionResult({
    required this.owner,
    required this.checkpointToken,
    required this.disposition,
    this.result,
  });

  final ChatTurnOwner owner;
  final String checkpointToken;
  final FileRollbackCheckpointExecutionDisposition disposition;
  final McpToolResult? result;
}

class FileTurnRollbackPreview {
  const FileTurnRollbackPreview({
    required this.owner,
    required this.checkpointToken,
    required this.turnId,
    required this.paths,
    required this.preview,
    required this.summary,
    this.currentStateFingerprint = '',
  });

  final ChatTurnOwner owner;
  final int checkpointToken;
  final String turnId, preview, summary;
  final String currentStateFingerprint;
  final List<String> paths;
}

typedef FileRollbackSnapshotLoader =
    Future<TextFileSnapshot> Function(String path);
typedef FileRollbackSnapshotRestorer =
    Future<String> Function({
      required String path,
      required bool existedBefore,
      String? content,
    });
typedef _CheckpointRef = ({ChatTurnOwner owner, int token});

class _OwnerRollbackState {
  final List<_FileRollbackEntry> singleChanges = [];
  final List<_FileTurnCheckpoint> turnCheckpoints = [];
  _FileTurnCheckpoint? activeTurnCheckpoint;
}

class _FileRollbackEntry {
  const _FileRollbackEntry({
    required this.token,
    required this.path,
    required this.pathKey,
    required this.existedBefore,
    this.previousContent,
    this.compensationToken,
  });

  final int token;
  final String path;
  final String pathKey;
  final bool existedBefore;
  final String? previousContent;
  final String? compensationToken;

  String? get recordToken => compensationToken == null
      ? null
      : 'file-mutation-rollback-$token-${sha256.convert(utf8.encode(jsonEncode({'path': path, 'compensationToken': compensationToken})))}';
}

class _FileTurnCheckpoint {
  _FileTurnCheckpoint({
    required this.token,
    required this.turnId,
    required this.entries,
  });

  final int token;
  final String turnId;
  final List<_FileRollbackEntry> entries;

  void addFirstEntryForPath(_FileRollbackEntry entry) {
    if (entries.any((existing) => existing.pathKey == entry.pathKey)) {
      return;
    }
    entries.add(entry);
  }

  _FileTurnCheckpoint toImmutable() {
    return _FileTurnCheckpoint(
      token: token,
      turnId: turnId,
      entries: List<_FileRollbackEntry>.unmodifiable(entries),
    );
  }
}

class _FileTurnRollbackBoundSnapshot {
  const _FileTurnRollbackBoundSnapshot({
    required this.entry,
    required this.snapshot,
  });

  final _FileRollbackEntry entry;
  final TextFileSnapshot snapshot;
}

class _FileTurnRollbackPreviewBinding {
  const _FileTurnRollbackPreviewBinding({
    required this.owner,
    required this.previewToken,
    required this.checkpoint,
    required this.currentStateFingerprint,
    required this.snapshots,
  });

  final ChatTurnOwner owner;
  final int previewToken;
  final _FileTurnCheckpoint checkpoint;
  final String currentStateFingerprint;
  final List<_FileTurnRollbackBoundSnapshot> snapshots;

  _CheckpointRef get checkpointRef => (owner: owner, token: checkpoint.token);
}

class _FileTurnRollbackPathAttempt {
  _FileTurnRollbackPathAttempt({
    required this.entry,
    required this.preRollbackSnapshot,
  });

  final _FileRollbackEntry entry;
  final TextFileSnapshot preRollbackSnapshot;
  TextFileSnapshot? expectedCurrentSnapshot;
}

class _FileTurnRollbackAttempt {
  _FileTurnRollbackAttempt({
    required this.binding,
    required this.state,
    required this.transactionToken,
    required this.recoveryReceipt,
  });

  final _FileTurnRollbackPreviewBinding binding;
  final _OwnerRollbackState state;
  final String transactionToken;
  final String recoveryReceipt;
  final List<_FileTurnRollbackPathAttempt> attemptedPaths = [];
  final Completer<void> initialSettlement = Completer<void>();

  _CheckpointRef get checkpointRef => binding.checkpointRef;
}

class _FileTurnRollbackRecovery {
  const _FileTurnRollbackRecovery({
    required this.attempt,
    required this.lastFailure,
  });

  final _FileTurnRollbackAttempt attempt;
  final String lastFailure;
}

class _FileTurnRollbackSettlement {
  const _FileTurnRollbackSettlement({
    required this.result,
    required this.releaseFence,
    this.recovery,
  });

  final McpToolResult result;
  final bool releaseFence;
  final _FileTurnRollbackRecovery? recovery;
}

class _FileTurnRollbackCompensation {
  const _FileTurnRollbackCompensation({
    required this.confirmed,
    required this.paths,
    required this.failure,
  });

  final bool confirmed;
  final List<Map<String, Object?>> paths;
  final String failure;
}
