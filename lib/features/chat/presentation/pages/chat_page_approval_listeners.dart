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

  Future<void> _showSshConnectDialog(
    BuildContext context,
    PendingSshConnect pending,
  ) async {
    final approval = await SshConnectApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveSshConnect(id: pending.id, approval: approval);
  }

  Future<void> _showSshCommandDialog(
    BuildContext context,
    PendingSshCommand pending,
  ) async {
    final approved = await SshCommandApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveSshCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showGitCommandDialog(
    BuildContext context,
    PendingGitCommand pending,
  ) async {
    final approved = await GitCommandApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveGitCommand(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showLocalCommandDialog(
    BuildContext context,
    PendingLocalCommand pending,
  ) async {
    final approval = await LocalCommandApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveLocalCommand(
          id: pending.id,
          approval: approval ?? const LocalCommandApproval(approved: false),
        );
  }

  Future<void> _showComputerUseActionDialog(
    BuildContext context,
    PendingComputerUseAction pending,
  ) async {
    final decision = await ComputerUseActionApprovalSheet.show(
      context,
      pending,
      stopHelperWork: () =>
          ref.read(macosComputerUseServiceProvider).stopHelperWork(),
    );

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveComputerUseAction(
          id: pending.id,
          approved: decision?.approved ?? false,
          armed: decision?.armed ?? !pending.requiresSmokeArming,
        );
  }

  Future<void> _showFileOperationDialog(
    BuildContext context,
    PendingFileOperation pending,
  ) async {
    final approved = await FileOperationApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveFileOperation(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showParticipantToolApprovalDialog(
    BuildContext context,
    PendingParticipantToolApproval pending,
  ) async {
    final approved = await ParticipantToolApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveParticipantToolApproval(
          id: pending.id,
          approved: approved ?? false,
        );
  }

  Future<void> _showBleConnectDialog(
    BuildContext context,
    PendingBleConnect pending,
  ) async {
    final approved = await BleConnectApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveBleConnect(id: pending.id, approved: approved ?? false);
  }

  Future<void> _showSerialOpenDialog(
    BuildContext context,
    PendingSerialOpen pending,
  ) async {
    final approved = await SerialOpenApprovalSheet.show(context, pending);

    if (!mounted) return;
    ref
        .read(chatNotifierProvider.notifier)
        .resolveSerialOpen(id: pending.id, approved: approved ?? false);
  }
}
