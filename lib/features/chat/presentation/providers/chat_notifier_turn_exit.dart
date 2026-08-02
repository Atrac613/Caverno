// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// Persists structured, behavior-neutral tool-turn exit diagnostics.
/// The user-visible completion explainer remains a separate concern.
const ToolLoopExitClassifier _toolLoopExitClassifier = ToolLoopExitClassifier();

extension ChatNotifierTurnExit on ChatNotifier {
  /// Classify and persist the finalized turn after recovery declines.
  /// The persisted [LlmSessionLogStore.recordTurnExit] marker keeps release
  /// builds visible to `tool/triage_session_logs.py` without changing output.
  /// The per-turn tool-loop hint is consumed exactly once here.
  Future<void> _logTurnExitReason({
    required ChatTurnOwner owner,
    required List<Message> finalizedMessages,
    required bool shouldDropLastAssistant,
    required String? finishReason,
  }) async {
    final generation = owner.interactionGeneration;
    final hint = _turnEnd.takeHint(owner);
    _classifiedTurnExitGenerations.add(generation);

    final hasVisibleFinal =
        !shouldDropLastAssistant && finalizedMessages.isNotEmpty;
    final finalText = hasVisibleFinal ? finalizedMessages.last.content : '';
    // Turn-provenance correlation keys: the assistant message id ties this
    // record to the on-screen conversation message (which holds the final,
    // post-transform content); `generation` identifies the turn.
    final assistantMessageId = hasVisibleFinal
        ? finalizedMessages.last.id
        : null;
    final reason = _toolLoopExitClassifier.classify(
      ToolLoopExitState(
        finalResponseText: finalText,
        explicitHint: hint,
        finishReason: finishReason,
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

    if (!LlmSessionLogStore.isEnabled(
      settingsEnabled: _settings.enableLlmSessionLogs,
    )) {
      return;
    }
    await ref
        .read(llmSessionLogStoreProvider)
        .recordTurnExit(
          context: _llmSessionLogContextForGeneration(generation),
          reason: token,
          noVisibleAnswer: shouldDropLastAssistant,
          finalAnswerRecoveryDecision: _turnEnd
              .finalAnswerRecoveryDecisionLogValue(owner),
          at: DateTime.now(),
          turnId: 'gen-$generation',
          assistantMessageId: assistantMessageId,
          transforms: _turnEnd.transforms(owner),
        );
  }

  /// Plan drafting is not a tool-calling turn, so it has no tool-loop exit
  /// reason to give. Saying so keeps `unknown` meaning "nobody classified this
  /// and nobody knows why" — which is then worth looking at, rather than
  /// something to explain away each time.
  static const String planDraftedExitReason = 'plan_drafted';

  /// Records [reason], or `unknown(<outcome>)` when the caller has none, for a
  /// turn nothing classified — and reports whether it had been. Only
  /// [_finishStreaming] and the detached path classify, so the rest ended in
  /// silence: four of six live turns on 2026-07-27, including the two that did
  /// the most work. A turn that ends is a turn that reports. [outcome] names
  /// the terminal, because which call site skipped classification was not
  /// derivable by reading — the record has to identify itself.
  bool _recordTurnExitIfUnclassified(
    int generation, {
    required String outcome,
    String? reason,
  }) {
    if (_classifiedTurnExitGenerations.remove(generation)) return true;
    final owner = _turnOwnerForGeneration(generation);
    if (!LlmSessionLogStore.isEnabled(
      settingsEnabled: _settings.enableLlmSessionLogs,
    )) {
      return false;
    }
    unawaited(
      ref
          .read(llmSessionLogStoreProvider)
          .recordTurnExit(
            context: _llmSessionLogContextForGeneration(generation),
            reason: reason ?? 'unknown($outcome)',
            noVisibleAnswer: false,
            finalAnswerRecoveryDecision: _turnEnd
                .finalAnswerRecoveryDecisionLogValue(owner),
            at: DateTime.now(),
            turnId: 'gen-$generation',
          ),
    );
    return false;
  }
}
