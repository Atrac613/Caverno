import '../../chat/domain/services/pending_approval_summary.dart';
import '../../remote_coding/domain/remote_coding_models.dart';
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
    for (final request in pendingApprovalsByPriority(state)) {
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

  /// Projects a pending `ask_user_question` for the watch, applying the same
  /// remote-ownership exclusion as [map].
  ///
  /// Questions are not `PendingToolApproval`s — they carry an answer rather
  /// than a decision — so they are described here rather than in the shared
  /// approval describer.
  WatchQuestion? mapQuestion(ChatState state) {
    final pending = state.pendingAskUserQuestion;
    // Same gate as [map]: origin first, a missing owner counted against
    // resolving here rather than for it.
    if (pending == null ||
        pending.origin == ChatInteractionOrigin.remote ||
        (pending.remoteDeviceId?.trim().isNotEmpty ?? false)) {
      return null;
    }
    return WatchQuestion(
      id: pending.id,
      question: pending.question,
      options: pending.options
          .map(
            (option) => WatchQuestionOption(id: option.id, label: option.label),
          )
          .toList(growable: false),
      allowMultiple: pending.allowMultiple,
      allowOther: pending.allowOther,
    );
  }

  /// Projects a Remote Coding approval for the wrist.
  ///
  /// A second source, not a widening of the first. `isOwnedByRemoteDevice`
  /// above covers the desktop-as-server case and cannot fire on iOS, where
  /// `ChatState` never holds a remote-origin approval; loosening it to reach
  /// Remote Coding would quietly undo SEC4.5g on desktop instead (WATCH11).
  ///
  /// The wrist inherits exactly the phone's authority. The desktop already
  /// withholds a kind this device was not granted, so anything arriving here is
  /// answerable in principle; `isSimpleDecision` decides whether it is
  /// answerable *from a watch* (SA-26).
  WatchApproval? mapRemote(RemoteCodingApproval? approval, {String host = ''}) {
    if (approval == null || approval.id.isEmpty) return null;
    return WatchApproval(
      id: approval.id,
      kind: approval.kind,
      title: approval.title,
      subtitle: approval.subtitle,
      detail: approval.warningMessage?.trim().isNotEmpty == true
          ? approval.warningMessage!
          : approval.detail,
      canResolveOnWatch: approval.isSimpleDecision,
      source: WatchInteractionSource.remote,
      host: host,
    );
  }

  WatchQuestion? mapRemoteQuestion(
    RemoteCodingQuestion? question, {
    String host = '',
  }) {
    if (question == null || question.id.isEmpty) return null;
    return WatchQuestion(
      id: question.id,
      question: question.question,
      options: question.options
          .map(
            (option) => WatchQuestionOption(id: option.id, label: option.label),
          )
          .toList(growable: false),
      source: WatchInteractionSource.remote,
      host: host,
    );
  }

  /// The one approval the wrist should show when both sources have one.
  ///
  /// Ranked by consequence across sources, using the same order every compact
  /// surface uses, so the wrist does not ask about opening a serial port while
  /// something wants to change a machine. A tie goes to the local one: it
  /// belongs to the device the watch is paired to, and can be finished there
  /// when the wrist cannot answer it.
  WatchApproval? preferred(WatchApproval? local, WatchApproval? remote) {
    if (local == null) return remote;
    if (remote == null) return local;
    return pendingApprovalKindRank(remote.kind) <
            pendingApprovalKindRank(local.kind)
        ? remote
        : local;
  }

  /// The same rule for questions, which have no kind to rank: a question the
  /// user is being asked on this phone comes first.
  WatchQuestion? preferredQuestion(
    WatchQuestion? local,
    WatchQuestion? remote,
  ) => local ?? remote;
}
