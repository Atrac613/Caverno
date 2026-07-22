/// The one-shot prompt that asks a model to settle a goal that has run dry.
///
/// Fired when goal auto-continue stops with `noRemainingWork`: no incomplete
/// evidence, no outstanding validation, nothing scheduled. The harness cannot
/// close the goal itself — the absence of evidence of incompleteness is not
/// evidence that the objective was met — and it will not ask the user, so it
/// asks the model.
///
/// The wording is explicit on purpose. Two live CMVP-1 runs showed the model
/// never calling `update_goal` on its own even when it was offered, while the
/// goal live canary showed it calling the tool reliably when the instruction
/// said to. The missing ingredient was the instruction, not the capability.
///
/// Reporting *incomplete* work is a first-class answer here. An elicitation
/// that only offered "confirm completion" would be leading, and a false
/// completion is the expensive direction: it ends the run.
abstract final class GoalCompletionElicitationPrompt {
  static String build({required String languageCode}) {
    final normalized = languageCode.trim().isEmpty ? 'en' : languageCode.trim();
    return [
      'The harness has nothing left to schedule for the active goal: no '
          'unresolved errors, no unverified changes, and verification has '
          'caught up with the latest change. It cannot tell from that whether '
          'the objective was actually met.',
      '',
      'Report the goal state now by calling update_goal, the only tool '
          'available this turn:',
      '- completed: true — the objective is met and you can say how it was '
          'checked.',
      '- message — work remains; name the concrete next step.',
      '- blocked_reason — you are genuinely stuck; name the blocker.',
      '',
      'Answering in prose instead of calling the tool leaves the goal '
          'unresolved. Do not claim completion you did not verify: a claim '
          'contradicted by the run\'s own tool results is rejected, and saying '
          'what remains is the more useful answer.',
      '',
      'Keep any visible text to one short sentence.',
      '',
      'Keep the visible response language aligned with language code '
          '"$normalized".',
    ].join('\n');
  }
}
