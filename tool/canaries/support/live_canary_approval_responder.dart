import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

/// Plays the human at the local-command approval prompt for a live canary.
///
/// Why this exists
/// ---------------
/// SEC4.4g (`9626b025`, 2026-08-24) made every shell command that reaches the
/// native shell require a *fresh* manual approval: `fullAccess` and remembered
/// allow-rules no longer bypass it. That is correct for the product and must
/// not be weakened. But a canary has no UI, so
/// `ChatNotifier.requestLocalCommand` parks on a `Completer` nobody completes,
/// and the turn stops dead — no result, no `turn_exit`, no log line after the
/// tool's `started` lifecycle event.
///
/// The first live coding canary run after that change (2026-08-31,
/// `coding_markdown_toc_exact_short_live_canary_1788142984`) burned its full
/// 30-minute test timeout that way, on a verifier command that completes in
/// seconds when run by hand. No live coding canary had been run in the six
/// weeks between the change and that run, so nothing caught it.
///
/// What this deliberately does not do
/// ----------------------------------
/// It never remembers a permission rule. Approving with a remembered `allow`
/// would cache the decision and let every later command through unasked, which
/// is exactly the gate SEC4.4g added — a canary that silences the gate stops
/// testing the path it runs on. Each command is approved on its own, the same
/// way a person answering each prompt would.
///
/// It also records what it approved. An auto-approver that leaves no trace is
/// the harness-blindness failure in miniature: the run would go green while
/// nobody could say what had been permitted.
final class LiveCanaryApprovalResponder {
  LiveCanaryApprovalResponder._(this._removeListener);

  final void Function() _removeListener;
  final List<ApprovedLocalCommand> _approvals = [];

  /// Every command this responder approved, in the order it answered them.
  List<ApprovedLocalCommand> get approvals => List.unmodifiable(_approvals);

  /// Containers already answered for, so a canary may call [attach] at every
  /// send site without stacking duplicate listeners.
  static final Expando<LiveCanaryApprovalResponder> _attached = Expando();

  /// Starts answering local-command approvals raised on [container].
  ///
  /// **Call this after the conversation and goal are set up, not from the
  /// container builder.** `container.listen` initialises the provider it
  /// watches, so attaching at construction builds `ChatNotifier` before the
  /// canary has created its conversation — the notifier then starts with no
  /// active goal, and `coding_goal_live_edit` fails every case on a missing
  /// "Active coding goal for this thread:" block. Attaching at the send site
  /// costs nothing: the notifier is being read there anyway.
  ///
  /// Answers only the prompt kind a coding canary actually raises. The other
  /// eleven `pending*` slots on [ChatState] are left alone on purpose: adding
  /// handlers for prompts no canary reaches would be untested code that
  /// silently approves something later.
  static LiveCanaryApprovalResponder attach(ProviderContainer container) {
    final existing = _attached[container];
    if (existing != null) {
      return existing;
    }
    late final LiveCanaryApprovalResponder responder;
    final removeListener = container.listen<ChatState>(chatNotifierProvider, (
      previous,
      next,
    ) {
      final pending = next.pendingLocalCommand;
      if (pending == null || pending.id == previous?.pendingLocalCommand?.id) {
        return;
      }
      final approved = ApprovedLocalCommand(
        command: pending.command,
        workingDirectory: pending.workingDirectory,
        reason: pending.reason,
      );
      responder._approvals.add(approved);
      // Printed, not just collected: this lands in the run's
      // `flutter_test.jsonl` beside the tool lifecycle events, so the evidence
      // of what a run was allowed to execute survives without every canary
      // having to plumb the responder through to an assertion.
      // ignore: avoid_print
      print('[CanaryApproval] approved ${approved.command}');
      container
          .read(chatNotifierProvider.notifier)
          .resolveLocalCommand(
            id: pending.id,
            // No remembered rule: see the class comment.
            approval: const LocalCommandApproval(approved: true),
          );
    }).close;
    responder = LiveCanaryApprovalResponder._(removeListener);
    _attached[container] = responder;
    return responder;
  }

  void detach() => _removeListener();
}

/// One command this responder let through.
final class ApprovedLocalCommand {
  const ApprovedLocalCommand({
    required this.command,
    required this.workingDirectory,
    this.reason,
  });

  final String command;
  final String workingDirectory;
  final String? reason;

  @override
  String toString() =>
      'ApprovedLocalCommand($command, cwd: $workingDirectory'
      '${reason == null ? '' : ', reason: $reason'})';
}
