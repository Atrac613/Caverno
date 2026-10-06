/// The Farm goal acknowledgement settles implementation before review/commit.
abstract final class ProjectTaskImplementationInstructions {
  static const completionScope =
      'This is the implementation or repair completion boundary. Here '
      'update_goal(completed: true) means the required implementation and '
      'verification are finished and review may begin. The later dedicated '
      'review, roadmap update and commit are not remaining implementation '
      'work. Keep completed: false for unfinished implementation, failed '
      'verification or a concrete blocker. Never report completion without '
      'captured change and successful verification evidence.';

  static const statusPrompt =
      'Before ending this project implementation turn, report its state by '
      'calling update_goal, the only tool offered in this request. '
      'Use completed as a JSON boolean. Report completed: true only after '
      'the required file changes and verification have succeeded. The harness '
      'checks the captured change and execution evidence. '
      '$completionScope '
      'Use completed: false with message when implementation work remains, or blocked_reason '
      'when a concrete blocker prevents further work. Prose does not settle '
      'the task state. Preserve completed work and reuse existing tool results. '
      'After accepted completion, end the visible response with the exact '
      'line PROJECT_TASK_READY_FOR_REVIEW; omit it while incomplete or blocked. '
      'Keep the visible response in the conversation language.';
}
