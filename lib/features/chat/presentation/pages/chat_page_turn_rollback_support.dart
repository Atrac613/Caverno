// Same-library extension on [_ChatPageState]; see chat_page_empty_state_builders.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

extension _ChatPageTurnRollbackSupport on _ChatPageState {
  TurnDiff? _latestRevertableTurnDiff({
    required Conversation? currentConversation,
    required ChatState chatState,
  }) {
    if (chatState.isLoading) {
      return null;
    }
    final diff = currentConversation?.effectiveTurnDiffs.lastOrNull;
    if (diff == null || !_canRevertTurnDiff(diff)) {
      return null;
    }
    return diff;
  }

  FileWorkspaceViewerRequest _buildTurnDiffViewerRequest(TurnDiff diff) {
    return FileWorkspaceViewerRequest.diff(
      diff: diff,
      onRevertLastTurn: _canRevertTurnDiff(diff)
          ? _confirmAndRollbackLastFileTurn
          : null,
    );
  }

  bool _canRevertTurnDiff(TurnDiff diff) {
    if (!diff.hasChanges ||
        diff.source != TurnDiffSource.tool ||
        _rolledBackTurnDiffIds.contains(diff.id)) {
      return false;
    }
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final latestDiff = currentConversation?.effectiveTurnDiffs.lastOrNull;
    return latestDiff?.id == diff.id;
  }

  Future<void> _confirmAndRollbackLastFileTurn(
    BuildContext _,
    TurnDiff diff,
  ) async {
    final preview = await ref
        .read(chatNotifierProvider.notifier)
        .previewLastFileTurnRollback();
    if (!mounted) {
      return;
    }
    if (preview == null) {
      _showTurnRollbackSnackBar(
        'No recent turn checkpoint is available to revert.',
      );
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) =>
              _TurnRollbackConfirmationDialog(preview: preview),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }

    final result = await ref
        .read(chatNotifierProvider.notifier)
        .rollbackLastFileTurnChanges();
    if (!mounted) {
      return;
    }

    if (!result.isSuccess) {
      _showTurnRollbackSnackBar(
        result.errorMessage?.trim().isNotEmpty == true
            ? result.errorMessage!.trim()
            : 'Failed to revert the last turn file changes.',
      );
      return;
    }

    setState(() {
      _rolledBackTurnDiffIds.add(diff.id);
      final currentRequest = _fileWorkspaceViewerRequest;
      if (currentRequest?.diff?.id == diff.id) {
        _fileWorkspaceViewerRequest = _buildTurnDiffViewerRequest(diff);
      }
    });
    _refreshCodingEnvironmentSnapshot();

    final fileCount = preview.paths.length;
    _showTurnRollbackSnackBar(
      'Reverted $fileCount ${fileCount == 1 ? 'file' : 'files'} from the last agent turn.',
    );
  }

  void _refreshCodingEnvironmentSnapshot() {
    final project = ref.read(codingProjectsNotifierProvider).selectedProject;
    if (project == null) {
      return;
    }
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final effectiveProject = conversation == null
        ? project
        : _effectiveCodingProjectForConversation(
            currentConversation: conversation,
            activeProject: project,
          );
    final rootPath = effectiveProject.normalizedRootPath;
    if (rootPath.isEmpty) return;
    ref.invalidate(codingEnvironmentSnapshotProvider(rootPath));
    ref.invalidate(codingWorktreeDiffProvider(rootPath));
  }

  void _showTurnRollbackSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
