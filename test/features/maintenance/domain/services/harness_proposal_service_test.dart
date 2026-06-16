import 'package:caverno/features/maintenance/domain/services/failure_trace_miner.dart';
import 'package:caverno/features/maintenance/domain/services/harness_proposal_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = HarnessProposalService();
  const base = ModelHarnessConfig(id: 'p', model: 'm');

  FailureCluster cluster(String mechanism) => FailureCluster(
    signature: FailureSignature(
      terminalCause: 'edit_apply_failed',
      causalStatus: 'tests_failed',
      mechanism: mechanism,
    ),
    traces: const [],
    actionability: 1,
  );

  test('stale_old_text proposes a failure-recovery instruction', () {
    final proposal = service.propose(
      cluster: cluster('stale_old_text'),
      base: base,
    );
    expect(proposal, isNotNull);
    expect(proposal!.surface, 'failureRecoveryInstruction');
    expect(
      proposal.proposedConfig.failureRecoveryInstruction,
      contains('re-read'),
    );
    // Minimal: no other surface is touched.
    expect(proposal.proposedConfig.recoveryMiddlewareEnabled, isFalse);
    expect(proposal.proposedConfig.executionInstruction, isEmpty);
  });

  test('malformed_json proposes enabling recovery middleware', () {
    final proposal = service.propose(
      cluster: cluster('malformed_json'),
      base: base,
    );
    expect(proposal!.surface, 'recoveryMiddlewareEnabled');
    expect(proposal.proposedConfig.recoveryMiddlewareEnabled, isTrue);
  });

  test('does not clobber a surface that is already set', () {
    final proposal = service.propose(
      cluster: cluster('stale_old_text'),
      base: base.copyWith(failureRecoveryInstruction: 'existing guidance'),
    );
    expect(proposal, isNull);
  });

  test('returns null for an unrecognized mechanism', () {
    expect(
      service.propose(cluster: cluster('mystery_failure'), base: base),
      isNull,
    );
  });
}
