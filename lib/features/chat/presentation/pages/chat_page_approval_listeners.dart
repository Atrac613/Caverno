part of 'chat_page.dart';

extension _ChatPageApprovalListeners on _ChatPageState {
  void _showApprovalDialogOnce(String id, Future<void> Function() showDialog) {
    if (!_activeApprovalDialogIds.add(id)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _activeApprovalDialogIds.remove(id);
        return;
      }

      try {
        await showDialog();
      } finally {
        _activeApprovalDialogIds.remove(id);
      }
    });
  }

  void _registerApprovalDialogListeners(BuildContext context) {
    // SSH connect confirmation dialog. Dialogs are deferred to the next
    // frame so they don't fire during a build / InheritedElement
    // lifecycle transition (avoids `_dependents.isEmpty` assertions).
    ref.listen<PendingSshConnect?>(
      chatNotifierProvider.select((s) => s.pendingSshConnect),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showSshConnectDialog(context, next),
          );
        }
      },
    );

    // SSH per-command confirmation dialog.
    ref.listen<PendingSshCommand?>(
      chatNotifierProvider.select((s) => s.pendingSshCommand),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showSshCommandDialog(context, next),
          );
        }
      },
    );

    // Git write-command confirmation dialog.
    ref.listen<PendingGitCommand?>(
      chatNotifierProvider.select((s) => s.pendingGitCommand),
      (prev, next) {
        if (next != null &&
            shouldPresentDesktopApproval(next.origin) &&
            prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showGitCommandDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingLocalCommand?>(
      chatNotifierProvider.select((s) => s.pendingLocalCommand),
      (prev, next) {
        if (next != null &&
            shouldPresentDesktopApproval(next.origin) &&
            prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showLocalCommandDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingComputerUseAction?>(
      chatNotifierProvider.select((s) => s.pendingComputerUseAction),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showComputerUseActionDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingBrowserAction?>(
      chatNotifierProvider.select((s) => s.pendingBrowserAction),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showBrowserActionDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingFileOperation?>(
      chatNotifierProvider.select((s) => s.pendingFileOperation),
      (prev, next) {
        if (next != null &&
            shouldPresentDesktopApproval(next.origin) &&
            prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showFileOperationDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingWorkflowDecision?>(
      chatNotifierProvider.select((s) => s.pendingWorkflowDecision),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showWorkflowDecisionDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingAskUserQuestion?>(
      chatNotifierProvider.select((s) => s.pendingAskUserQuestion),
      (prev, next) {
        if (next != null &&
            shouldPresentDesktopQuestion(next.origin) &&
            prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showAskUserQuestionDialog(context, next),
          );
        }
      },
    );

    // BLE connect confirmation dialog.
    ref.listen<PendingBleConnect?>(
      chatNotifierProvider.select((s) => s.pendingBleConnect),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showBleConnectDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingSerialOpen?>(
      chatNotifierProvider.select((s) => s.pendingSerialOpen),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showSerialOpenDialog(context, next),
          );
        }
      },
    );

    ref.listen<PendingParticipantToolApproval?>(
      chatNotifierProvider.select((s) => s.pendingParticipantToolApproval),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          _showApprovalDialogOnce(
            next.id,
            () => _showParticipantToolApprovalDialog(context, next),
          );
        }
      },
    );
  }
}
