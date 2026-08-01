import '../../data/datasources/file_rollback_checkpoint_store.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';

// ChatNotifier decomposition collaborator: file-turn-rollback-service

/// Minimal checkpoint boundary required for whole-turn file rollback.
abstract interface class FileCheckpointPort {
  Future<FileTurnRollbackPreview?> previewLastFileTurn({
    required String? conversationId,
  });

  Future<McpToolResult> rollbackLastFileTurn({
    required ChatTurnOwner owner,
    required int checkpointToken,
  });
}

typedef FileTurnPreviewCallback =
    Future<FileTurnRollbackPreview?> Function(String? conversationId);

typedef FileTurnRollbackCallback =
    Future<McpToolResult> Function(ChatTurnOwner owner, int checkpointToken);

/// Adapts existing checkpoint operations to the narrow rollback boundary.
final class CallbackFileCheckpointPort implements FileCheckpointPort {
  const CallbackFileCheckpointPort({
    required FileTurnPreviewCallback preview,
    required FileTurnRollbackCallback rollback,
  }) : _preview = preview,
       _rollback = rollback;

  final FileTurnPreviewCallback _preview;
  final FileTurnRollbackCallback _rollback;

  @override
  Future<FileTurnRollbackPreview?> previewLastFileTurn({
    required String? conversationId,
  }) => _preview(conversationId);

  @override
  Future<McpToolResult> rollbackLastFileTurn({
    required ChatTurnOwner owner,
    required int checkpointToken,
  }) => _rollback(owner, checkpointToken);
}

/// Coordinates file-turn rollback without owning checkpoint lifecycle state.
final class FileTurnRollbackService {
  const FileTurnRollbackService({FileCheckpointPort? checkpointPort})
    : _checkpointPort = checkpointPort;

  factory FileTurnRollbackService.fromCallbacks(
    FileTurnPreviewCallback? preview,
    FileTurnRollbackCallback? rollback,
  ) {
    assert((preview == null) == (rollback == null));
    return FileTurnRollbackService(
      checkpointPort: preview == null
          ? null
          : CallbackFileCheckpointPort(preview: preview, rollback: rollback!),
    );
  }

  static const _unavailableResult = McpToolResult(
    toolName: 'rollback_last_turn_file_changes',
    result: '',
    isSuccess: false,
    errorMessage: 'No file checkpoint service is available',
  );

  final FileCheckpointPort? _checkpointPort;

  Future<FileTurnRollbackPreview?> preview({
    required String? conversationId,
  }) async {
    final checkpointPort = _checkpointPort;
    if (checkpointPort == null) {
      return null;
    }
    final preview = await checkpointPort.previewLastFileTurn(
      conversationId: conversationId,
    );
    if (preview == null) {
      return null;
    }
    return FileTurnRollbackPreview(
      owner: preview.owner,
      checkpointToken: preview.checkpointToken,
      turnId: preview.turnId,
      paths: List<String>.unmodifiable(preview.paths),
      preview: preview.preview,
      summary: preview.summary,
      currentStateFingerprint: preview.currentStateFingerprint,
    );
  }

  Future<McpToolResult> rollback({
    required ChatTurnOwner owner,
    required int checkpointToken,
  }) {
    final checkpointPort = _checkpointPort;
    if (checkpointPort == null) {
      return Future<McpToolResult>.value(_unavailableResult);
    }
    return checkpointPort.rollbackLastFileTurn(
      owner: owner,
      checkpointToken: checkpointToken,
    );
  }
}
