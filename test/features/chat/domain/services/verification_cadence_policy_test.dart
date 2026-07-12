import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/verification_cadence_policy.dart';

void main() {
  const policy = VerificationCadencePolicy();

  test('requires verification after mutation makes evidence stale', () {
    final result = policy.decide(
      mutationGeneration: 3,
      verificationGeneration: 2,
      taskRequiresValidation: true,
      taskCompleted: false,
      validationFailed: false,
    );

    expect(result, VerificationCadence.required);
  });

  test('does not require verification when evidence is current', () {
    final result = policy.decide(
      mutationGeneration: 3,
      verificationGeneration: 3,
      taskRequiresValidation: true,
      taskCompleted: true,
      validationFailed: false,
    );

    expect(result, VerificationCadence.notDue);
  });

  test('marks an unverified active task as due before completion', () {
    final result = policy.decide(
      mutationGeneration: 0,
      verificationGeneration: -1,
      taskRequiresValidation: true,
      taskCompleted: false,
      validationFailed: false,
    );

    expect(result, VerificationCadence.due);
  });
}
