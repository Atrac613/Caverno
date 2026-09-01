import '../../../../core/services/notification_service.dart';
import '../../domain/services/pending_approval_summary.dart';
import 'chat_notifier.dart';
import 'chat_state.dart';

/// Reading and answering pending approvals from outside the chat UI.
///
/// Lives beside `ChatNotifier` rather than inside its part-file library on
/// purpose: none of this touches notifier state, and the library is under a
/// line ratchet that exists to push exactly this kind of code out
/// (`test/quality/file_size_ratchet_test.dart`).
///
/// Callers are the compact surfaces — the Apple Watch companion and actionable
/// notifications — which show an approval the user cannot fully inspect and so
/// must be precise about which request they are answering.

/// The approval a compact surface should present for [conversationId], or null
/// when that thread is not blocked on one this device may answer.
///
/// Reads the cross-thread registry rather than any `ChatState`: the whole point
/// is to describe a thread the user is *not* looking at.
PendingApprovalSummary? findPendingApprovalSummary(
  PendingToolApprovalRegistry registry, {
  required String conversationId,
}) {
  for (final request in registry.pendingOfType<PendingToolApproval<dynamic>>()) {
    if (request.owner.conversationId != conversationId) continue;
    final summary = describePendingApproval(request);
    // SEC4.5g: an approval owned by a paired Remote Coding device is that
    // device's to answer, not this one's.
    if (summary.isOwnedByRemoteDevice) continue;
    return summary;
  }
  return null;
}

/// Applies a bare approve/deny to the pending approval [id], whatever kind it
/// is.
///
/// `ChatNotifier.resolveRemoteApproval` covers only the three kinds Remote
/// Coding surfaces. Compact surfaces — the Apple Watch companion and actionable
/// notifications — show more than that, so they need one entry point instead of
/// each caller re-deriving the kind and drifting from the others.
///
/// Chained rather than switched because each resolver is keyed by id *and*
/// type: a mismatch is a clean no-op, so at most one link can fire. This is the
/// same shape `resolveRemoteApproval` already uses.
///
/// Two kinds are deliberately absent. Computer-use needs smoke arming and SSH
/// connect needs credentials; neither can be answered honestly with a single
/// yes/no, which is why [describePendingApproval] reports them as
/// `isSimpleDecision: false`. That switch is exhaustive over the sealed
/// `PendingToolApproval`, so a new kind surfaces there as a compile error and
/// its decision about this list has to be made consciously.
///
/// Returns false when [id] is unknown, already resolved, or of one of those two
/// kinds.
bool resolveApprovalById(
  ChatNotifier notifier, {
  required String id,
  required bool approved,
}) =>
    notifier.resolveFileOperation(id: id, approved: approved) ||
    notifier.resolveGitCommand(id: id, approved: approved) ||
    notifier.resolveLocalCommand(
      id: id,
      approval: LocalCommandApproval(approved: approved),
    ) ||
    notifier.resolveSshCommand(id: id, approved: approved) ||
    notifier.resolveBrowserAction(id: id, approved: approved) ||
    notifier.resolveBleConnect(id: id, approved: approved) ||
    notifier.resolveSerialOpen(id: id, approved: approved) ||
    notifier.resolveParticipantToolApproval(id: id, approved: approved);

/// Raises the "a background thread is waiting" notification.
///
/// The notification carries Approve and Deny actions, and iOS forwards both to
/// a paired Apple Watch, so the body names what is actually being approved. A
/// generic "a thread is waiting" would be asking the user to approve a command
/// they cannot see.
Future<void> showPendingApprovalNotification(
  NotificationService notifications, {
  required String conversationId,
  required String threadTitle,
  required PendingApprovalSummary? summary,
}) {
  final subject = summary == null
      ? 'is waiting for your approval'
      : 'wants to run: ${summary.title}';
  return notifications.showApprovalRequiredNotification(
    conversationId: conversationId,
    title: threadTitle.isEmpty ? 'Caverno' : threadTitle,
    body: threadTitle.isEmpty
        ? 'A thread $subject.'
        : '$threadTitle $subject.',
    approvalId: summary?.id,
    // Actions are only offered when a bare yes/no is a truthful answer.
    allowsDirectDecision: summary?.isSimpleDecision ?? false,
  );
}
