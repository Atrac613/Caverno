import 'chat_state.dart';

/// Removes an answered approval from the state that was showing it.
///
/// Extracted from `ThreadScopedChatState`, which sat at its ratchet ceiling
/// with no margin, so ANA0's assumption-confirmation slot could not be added
/// without either raising that budget or extracting. The seam is real: that
/// class decides what a thread stashes across a switch, while this one is a
/// per-type dispatch over the pending hierarchy and grows once per approval
/// type. Re-exported from `chat_state.dart`, which every caller already
/// imports.
abstract final class PendingToolApprovalProjection {
  /// Clears [pending] from [current], and only if it is still the one shown.
  ///
  /// The identity check is what makes this safe to call late: a stale answer
  /// for an approval that has already been replaced must not blank the slot
  /// its successor is using.
  static ChatState clear(
    ChatState current,
    PendingToolApproval<dynamic> pending,
  ) {
    return switch (pending) {
      PendingSshConnect() when identical(current.pendingSshConnect, pending) =>
        current.copyWith(pendingSshConnect: null),
      PendingSshCommand() when identical(current.pendingSshCommand, pending) =>
        current.copyWith(pendingSshCommand: null),
      PendingGitCommand() when identical(current.pendingGitCommand, pending) =>
        current.copyWith(pendingGitCommand: null),
      PendingLocalCommand()
          when identical(current.pendingLocalCommand, pending) =>
        current.copyWith(pendingLocalCommand: null),
      PendingFileOperation()
          when identical(current.pendingFileOperation, pending) =>
        current.copyWith(pendingFileOperation: null),
      PendingComputerUseAction()
          when identical(current.pendingComputerUseAction, pending) =>
        current.copyWith(pendingComputerUseAction: null),
      PendingBrowserAction()
          when identical(current.pendingBrowserAction, pending) =>
        current.copyWith(pendingBrowserAction: null),
      PendingBleConnect() when identical(current.pendingBleConnect, pending) =>
        current.copyWith(pendingBleConnect: null),
      PendingSerialOpen() when identical(current.pendingSerialOpen, pending) =>
        current.copyWith(pendingSerialOpen: null),
      PendingParticipantToolApproval()
          when identical(current.pendingParticipantToolApproval, pending) =>
        current.copyWith(pendingParticipantToolApproval: null),
      PendingAssumptionConfirmation()
          when identical(current.pendingAssumptionConfirmation, pending) =>
        current.copyWith(pendingAssumptionConfirmation: null),
      _ => current,
    };
  }
}
