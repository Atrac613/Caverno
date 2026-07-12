import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/execution_budget_policy.dart';

void main() {
  const policy = ExecutionBudgetPolicy(maxTotalExtension: 6);

  test('grants a progress-backed extension within the ceiling', () {
    final decision = policy.requestExtension(
      totalExtensionGranted: 2,
      requestedIterations: 3,
      reason: ExecutionBudgetExtensionReason.verificationRepair,
      madeProgress: true,
    );

    expect(decision.grantedIterations, 3);
  });

  test('clips extensions at the total ceiling', () {
    final decision = policy.requestExtension(
      totalExtensionGranted: 5,
      requestedIterations: 4,
      reason: ExecutionBudgetExtensionReason.editMismatchRecovery,
      madeProgress: true,
    );

    expect(decision.grantedIterations, 1);
  });

  test('rejects no-progress extension requests', () {
    final decision = policy.requestExtension(
      totalExtensionGranted: 0,
      requestedIterations: 2,
      reason: ExecutionBudgetExtensionReason.proseOnlyStall,
      madeProgress: false,
    );

    expect(decision.granted, isFalse);
  });
}
