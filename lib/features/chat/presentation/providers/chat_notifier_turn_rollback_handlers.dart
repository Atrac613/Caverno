// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierTurnRollbackHandlers on ChatNotifier {
  Future<FileTurnRollbackPreview?> previewLastFileTurnRollback() async {
    return _mcpToolService?.previewLastFileTurnCheckpoint();
  }

  Future<McpToolResult> rollbackLastFileTurnChanges() async {
    final toolService = _mcpToolService;
    if (toolService == null) {
      return const McpToolResult(
        toolName: 'rollback_last_turn_file_changes',
        result: '',
        isSuccess: false,
        errorMessage: 'No file checkpoint service is available',
      );
    }
    return toolService.rollbackLastFileTurnCheckpoint();
  }
}
