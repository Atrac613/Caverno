final class ProductionReleaseApprovalEvidenceSnapshot {
  const ProductionReleaseApprovalEvidenceSnapshot({
    required this.conversationId,
    required this.approved,
    this.proseWouldApprove = false,
  });

  final String? conversationId;

  /// Whether a production release may run. Decided by the issued approval
  /// token alone.
  final bool approved;

  /// What the retired wording predicates would have decided, recorded so the
  /// two can be compared before those predicates are deleted.
  ///
  /// Never grants anything. A `true` here beside a `false` [approved] is the
  /// interesting case: prose that reads as approval without the user having
  /// selected the token-bearing option.
  final bool proseWouldApprove;

  /// One log line when the two verdicts disagree, else null.
  String? get shadowDivergenceLogLine => proseWouldApprove == approved
      ? null
      : '[ProductionRelease] Shadow divergence: token=$approved '
            'prose=$proseWouldApprove';
}
