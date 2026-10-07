import '../../../../core/utils/logger.dart';
import 'execution_budget_policy.dart';

/// Owns one loop's limit and cumulative bounded extensions.
final class ToolLoopExecutionBudget {
  ToolLoopExecutionBudget(this.limit);
  int limit;
  int _totalExtensionGranted = 0;
  void request(
    ExecutionBudgetExtensionReason reason, {
    int requestedIterations = 2,
    bool madeProgress = true,
  }) {
    final decision = const ExecutionBudgetPolicy().requestExtension(
      totalExtensionGranted: _totalExtensionGranted,
      requestedIterations: requestedIterations,
      reason: reason,
      madeProgress: madeProgress,
    );
    limit += decision.grantedIterations;
    _totalExtensionGranted += decision.grantedIterations;
    appLog(
      '[ExecutionBudget] reason=${reason.name}; '
      'requested=$requestedIterations; granted=${decision.grantedIterations}; '
      'totalExtension=$_totalExtensionGranted; cap=$limit',
    );
  }
}
