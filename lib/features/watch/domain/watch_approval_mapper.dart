import '../../chat/domain/services/pending_approval_summary.dart';
import '../../chat/presentation/providers/chat_state.dart';
import 'watch_snapshot.dart';

/// Picks the one pending approval the watch should show, and projects it onto
/// the wire model.
///
/// The per-kind flattening lives in [describePendingApproval] so the watch and
/// the actionable notification cannot drift apart in what they cover. What is
/// watch-specific, and stays here, is two things:
///
/// 1. **Priority.** Only one approval fits on a watch screen, so when several
///    threads block at once the mutating, highest-consequence kinds come first:
///    the watch should ask about the command that changes the machine, not the
///    one that opens a serial port.
///
/// 2. **The trust model.** SEC4.5g scoped Remote Coding so that only the paired
///    device which started a turn may see or resolve its approvals
///    (`RemoteCodingServerNotifier._canResolveInteraction`). Reusing that gate
///    verbatim would hide every iPhone-initiated approval from the watch, which
///    is the whole point of the companion. The watch is a peripheral of *this*
///    device, so it sees local-origin approvals — and never one owned by some
///    other paired device.
class WatchApprovalMapper {
  const WatchApprovalMapper();

  static const String kindFile = PendingApprovalKinds.file;
  static const String kindLocalCommand = PendingApprovalKinds.localCommand;
  static const String kindGitCommand = PendingApprovalKinds.gitCommand;
  static const String kindSshCommand = PendingApprovalKinds.sshCommand;
  static const String kindSshConnect = PendingApprovalKinds.sshConnect;
  static const String kindBleConnect = PendingApprovalKinds.bleConnect;
  static const String kindSerialOpen = PendingApprovalKinds.serialOpen;
  static const String kindBrowserAction = PendingApprovalKinds.browserAction;
  static const String kindComputerUse = PendingApprovalKinds.computerUse;
  static const String kindParticipantTool =
      PendingApprovalKinds.participantTool;

  /// The first pending approval the watch should show, or null when none is
  /// eligible.
  WatchApproval? map(ChatState state) {
    for (final request in _byPriority(state)) {
      final summary = describePendingApproval(request);
      if (summary.isOwnedByRemoteDevice) continue;
      return WatchApproval(
        id: summary.id,
        kind: summary.kind,
        title: summary.title,
        subtitle: summary.subtitle,
        detail: summary.detail,
        canResolveOnWatch: summary.isSimpleDecision,
      );
    }
    return null;
  }

  /// Highest-consequence first; the last two need input the watch cannot
  /// collect and are surfaced read-only.
  Iterable<PendingToolApproval<dynamic>> _byPriority(ChatState state) => [
    state.pendingFileOperation,
    state.pendingLocalCommand,
    state.pendingGitCommand,
    state.pendingSshCommand,
    state.pendingBrowserAction,
    state.pendingBleConnect,
    state.pendingSerialOpen,
    state.pendingParticipantToolApproval,
    state.pendingComputerUseAction,
    state.pendingSshConnect,
  ].whereType<PendingToolApproval<dynamic>>();

  /// Projects a pending `ask_user_question` for the watch, applying the same
  /// remote-ownership exclusion as [map].
  ///
  /// Questions are not `PendingToolApproval`s — they carry an answer rather
  /// than a decision — so they are described here rather than in the shared
  /// approval describer.
  WatchQuestion? mapQuestion(ChatState state) {
    final pending = state.pendingAskUserQuestion;
    if (pending == null ||
        (pending.remoteDeviceId?.trim().isNotEmpty ?? false)) {
      return null;
    }
    return WatchQuestion(
      id: pending.id,
      question: pending.question,
      options: pending.options
          .map(
            (option) =>
                WatchQuestionOption(id: option.id, label: option.label),
          )
          .toList(growable: false),
      allowMultiple: pending.allowMultiple,
      allowOther: pending.allowOther,
    );
  }
}
