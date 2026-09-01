part of 'chat_page.dart';

extension _ChatPageApprovalListeners on _ChatPageState {
  /// Wires one pending interaction to its dialog.
  ///
  /// Twelve of these used to be written out longhand, each repeating the
  /// "open when the id changes" shape and none of them closing anything. The
  /// dismissal half now lives in [ApprovalDialogPresenter]; see there for why
  /// the watch made it necessary.
  void _syncApprovalDialog<T extends Object>(
    BuildContext context,
    T? Function(ChatState) select,
    String Function(T) idOf,
    Future<void> Function(T) present, {
    bool Function(T)? shouldPresent,
  }) {
    ref.listen<T?>(
      chatNotifierProvider.select(select),
      (previous, next) => _approvalDialogs.sync<T>(
        context: context,
        previous: previous,
        next: next,
        idOf: idOf,
        present: present,
        isMounted: () => mounted,
        shouldPresent: shouldPresent,
      ),
    );
  }

  void _registerApprovalDialogListeners(BuildContext context) {
    _syncApprovalDialog<PendingSshConnect>(
      context,
      (s) => s.pendingSshConnect,
      (p) => p.id,
      (p) => _showSshConnectDialog(context, p),
    );

    _syncApprovalDialog<PendingSshCommand>(
      context,
      (s) => s.pendingSshCommand,
      (p) => p.id,
      (p) => _showSshCommandDialog(context, p),
    );

    _syncApprovalDialog<PendingGitCommand>(
      context,
      (s) => s.pendingGitCommand,
      (p) => p.id,
      (p) => _showGitCommandDialog(context, p),
      shouldPresent: (p) => shouldPresentDesktopApproval(p.origin),
    );

    _syncApprovalDialog<PendingLocalCommand>(
      context,
      (s) => s.pendingLocalCommand,
      (p) => p.id,
      (p) => _showLocalCommandDialog(context, p),
      shouldPresent: (p) => shouldPresentDesktopApproval(p.origin),
    );

    _syncApprovalDialog<PendingComputerUseAction>(
      context,
      (s) => s.pendingComputerUseAction,
      (p) => p.id,
      (p) => _showComputerUseActionDialog(context, p),
    );

    _syncApprovalDialog<PendingBrowserAction>(
      context,
      (s) => s.pendingBrowserAction,
      (p) => p.id,
      (p) => _showBrowserActionDialog(context, p),
    );

    _syncApprovalDialog<PendingFileOperation>(
      context,
      (s) => s.pendingFileOperation,
      (p) => p.id,
      (p) => _showFileOperationDialog(context, p),
      shouldPresent: (p) => shouldPresentDesktopApproval(p.origin),
    );

    _syncApprovalDialog<PendingWorkflowDecision>(
      context,
      (s) => s.pendingWorkflowDecision,
      (p) => p.id,
      (p) => _showWorkflowDecisionDialog(context, p),
    );

    _syncApprovalDialog<PendingAskUserQuestion>(
      context,
      (s) => s.pendingAskUserQuestion,
      (p) => p.id,
      (p) => _showAskUserQuestionDialog(context, p),
      shouldPresent: (p) => shouldPresentDesktopQuestion(p.origin),
    );

    _syncApprovalDialog<PendingBleConnect>(
      context,
      (s) => s.pendingBleConnect,
      (p) => p.id,
      (p) => _showBleConnectDialog(context, p),
    );

    _syncApprovalDialog<PendingSerialOpen>(
      context,
      (s) => s.pendingSerialOpen,
      (p) => p.id,
      (p) => _showSerialOpenDialog(context, p),
    );

    _syncApprovalDialog<PendingParticipantToolApproval>(
      context,
      (s) => s.pendingParticipantToolApproval,
      (p) => p.id,
      (p) => _showParticipantToolApprovalDialog(context, p),
    );
  }

  Future<void> _showWorkflowDecisionDialog(
    BuildContext context,
    PendingWorkflowDecision pending,
  ) async {
    final approvedAnswer =
        await showModalBottomSheet<WorkflowPlanningDecisionAnswer>(
          context: context,
          isDismissible: false,
          enableDrag: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          routeSettings: RouteSettings(
            name: approvalDialogRouteName(pending.id),
          ),
          builder: (sheetContext) => _WorkflowDecisionSheet(pending: pending),
        );

    if (!mounted) return;

    ref
        .read(chatNotifierProvider.notifier)
        .resolveWorkflowDecision(id: pending.id, answer: approvedAnswer);
  }

  Future<void> _showAskUserQuestionDialog(
    BuildContext context,
    PendingAskUserQuestion pending,
  ) async {
    final answer = await showModalBottomSheet<AskUserQuestionAnswer>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      routeSettings: RouteSettings(name: approvalDialogRouteName(pending.id)),
      builder: (sheetContext) => _AskUserQuestionSheet(pending: pending),
    );

    if (!mounted) return;

    ref
        .read(chatNotifierProvider.notifier)
        .resolveAskUserQuestion(id: pending.id, answer: answer);
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
