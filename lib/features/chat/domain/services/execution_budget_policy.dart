enum ExecutionBudgetExtensionReason {
  toolLoopExhaustion,
  editMismatchRecovery,
  backgroundProcessMonitoring,
  verificationRepair,
  codingContinuation,
  lengthTruncation,
  proseOnlyStall,
}

class ExecutionBudgetDecision {
  const ExecutionBudgetDecision({
    required this.grantedIterations,
    required this.reason,
  });

  final int grantedIterations;
  final ExecutionBudgetExtensionReason reason;

  bool get granted => grantedIterations > 0;
}

class ExecutionBudgetPolicy {
  const ExecutionBudgetPolicy({this.maxTotalExtension = 12});

  final int maxTotalExtension;

  ExecutionBudgetDecision requestExtension({
    required int totalExtensionGranted,
    required int requestedIterations,
    required ExecutionBudgetExtensionReason reason,
    required bool madeProgress,
  }) {
    if (!madeProgress || requestedIterations <= 0) {
      return ExecutionBudgetDecision(grantedIterations: 0, reason: reason);
    }
    final remaining = maxTotalExtension - totalExtensionGranted;
    final granted = remaining <= 0
        ? 0
        : requestedIterations.clamp(0, remaining);
    return ExecutionBudgetDecision(grantedIterations: granted, reason: reason);
  }
}
