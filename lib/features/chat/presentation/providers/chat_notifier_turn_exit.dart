// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// LL31 turn-exit instrumentation (slice 2a).
///
/// Records a structured reason for why each tool-calling turn ended so the
/// session-log triage tooling can see whether complex turns stop on a tool-call
/// abort, a user-confirmation pause, the iteration cap, an empty/partial answer,
/// or a normal completion. This is logging only — it does not alter the
/// response. The user-visible completion explainer is the separate LL31 slice 2b.
const ToolLoopExitClassifier _toolLoopExitClassifier = ToolLoopExitClassifier();

extension ChatNotifierTurnExit on ChatNotifier {
  /// Classify and log the exit reason for the just-finalized turn, then clear
  /// the per-turn hint the tool loop set. Called from `_finishStreaming` after
  /// finalization recovery has declined and before the messages are persisted.
  void _logTurnExitReason({
    required List<Message> finalizedMessages,
    required bool shouldDropLastAssistant,
  }) {
    final hint = _turnExitReasonHint;
    _turnExitReasonHint = null;

    final finalText = shouldDropLastAssistant || finalizedMessages.isEmpty
        ? ''
        : finalizedMessages.last.content;
    final reason = _toolLoopExitClassifier.classify(
      ToolLoopExitState(
        finalResponseText: finalText,
        explicitHint: hint,
        finishReason: _latestFinishReason(),
      ),
    );
    final token = _toolLoopExitClassifier.logToken(reason);
    if (shouldDropLastAssistant) {
      // Mid-work / empty terminal: the "agent appears to just stop" case the
      // session-log triage tooling looks for.
      appLog('[TurnExit][WARN] reason=$token (no visible final answer)');
    } else {
      appLog('[TurnExit] reason=$token');
    }
  }
}
