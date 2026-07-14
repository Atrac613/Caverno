import 'package:caverno/features/chat/domain/services/command_diagnostic_verifier_replay_policy.dart';
import 'package:caverno/features/chat/domain/services/stalled_diagnostic_repair_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = CommandDiagnosticVerifierReplayPolicy();
  const pathBackedFocus = CommandDiagnosticRepairFocus(
    commandKey: 'verify-key',
    streak: 1,
    diagnosticSummary: 'lib/main.dart: [compile_error] Build failed.',
    hasPathBackedDiagnostic: true,
  );

  test('blocks the unchanged path-backed verifier before mutation', () {
    expect(
      policy.shouldBlock(
        focus: pathBackedFocus,
        attemptedCommandKey: 'verify-key',
        isVerification: true,
        hasPrecedingMutation: false,
      ),
      isTrue,
    );
  });

  test('allows a verifier requested after a mutation', () {
    expect(
      policy.shouldBlock(
        focus: pathBackedFocus,
        attemptedCommandKey: 'verify-key',
        isVerification: true,
        hasPrecedingMutation: true,
      ),
      isFalse,
    );
  });

  test('allows pathless diagnostic recovery commands', () {
    const pathlessFocus = CommandDiagnosticRepairFocus(
      commandKey: 'verify-key',
      streak: 1,
      diagnosticSummary: '[dependency_error] Resolve the dependency.',
      hasPathBackedDiagnostic: false,
    );

    expect(
      policy.shouldBlock(
        focus: pathlessFocus,
        attemptedCommandKey: 'verify-key',
        isVerification: true,
        hasPrecedingMutation: false,
      ),
      isFalse,
    );
  });

  test('allows a different verifier command', () {
    expect(
      policy.shouldBlock(
        focus: pathBackedFocus,
        attemptedCommandKey: 'different-key',
        isVerification: true,
        hasPrecedingMutation: false,
      ),
      isFalse,
    );
  });

  test('allows a non-verification corrective command', () {
    expect(
      policy.shouldBlock(
        focus: pathBackedFocus,
        attemptedCommandKey: 'verify-key',
        isVerification: false,
        hasPrecedingMutation: false,
      ),
      isFalse,
    );
  });
}
