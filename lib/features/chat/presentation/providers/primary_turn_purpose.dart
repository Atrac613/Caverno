/// What a primary turn is for. It picks the turn's route and which recoveries
/// apply. One value rather than flags, because a turn is at most one of these.
enum PrimaryTurnPurpose {
  conversation,

  /// A read-only `/review` turn on the dedicated review route.
  codeReview,

  /// A project-task subtask turn before the last. Like the implementation
  /// turn its outcome is settled by a structured marker, not by prose
  /// recovery, but it must not be pushed to report goal completion. Without
  /// its own value it got prose recovery, which read a finished subtask
  /// ending in its marker as an unexecuted continuation and forced another
  /// tool call (session 80dc7079).
  projectTaskStep,

  /// The project-task implementation turn, settled by goal completion.
  projectTaskImplementation;

  static PrimaryTurnPurpose of({
    bool codeReview = false,
    bool projectTaskImplementation = false,
    bool projectTaskStep = false,
  }) => codeReview
      ? PrimaryTurnPurpose.codeReview
      : projectTaskImplementation
      ? PrimaryTurnPurpose.projectTaskImplementation
      : projectTaskStep
      ? PrimaryTurnPurpose.projectTaskStep
      : PrimaryTurnPurpose.conversation;
}
