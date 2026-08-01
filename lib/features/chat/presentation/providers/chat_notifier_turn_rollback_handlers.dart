// Same-library extension; the ignore matches sibling handler parts.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierTurnRollbackHandlers on ChatNotifier {
  Future<FileTurnRollbackPreview?> previewLastFileTurnRollback() =>
      _fileTurnRollbackService.preview(conversationId: conversationId);
  Future<McpToolResult> rollbackLastFileTurnChanges(
    ChatTurnOwner owner,
    int checkpointToken,
  ) => _fileTurnRollbackService.rollback(
    owner: owner,
    checkpointToken: checkpointToken,
  );

  FileTurnRollbackService get _fileTurnRollbackService =>
      FileTurnRollbackService.fromCallbacks(
        _mcpToolService?.previewFsTurn,
        _mcpToolService?.rollbackLastFileTurnCheckpoint,
      );
}
