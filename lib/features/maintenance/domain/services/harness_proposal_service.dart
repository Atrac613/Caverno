import '../../../settings/domain/entities/app_settings.dart';
import 'failure_trace_miner.dart';

/// A minimal, mechanism-grounded edit to a model's [ModelHarnessConfig],
/// proposed by LL17 to address a mined weakness cluster.
class HarnessConfigProposal {
  const HarnessConfigProposal({
    required this.mechanism,
    required this.surface,
    required this.rationale,
    required this.proposedConfig,
  });

  /// The mined mechanism this edit addresses (the proposal is grounded in it).
  final String mechanism;

  /// The single harness surface the edit touches (kept minimal).
  final String surface;

  final String rationale;

  /// The base config with the one minimal edit applied.
  final ModelHarnessConfig proposedConfig;
}

/// LL17 harness proposer: turns the top weakness cluster into one minimal,
/// grounded edit to the model's declared harness config (LL23).
///
/// Rule-based and deterministic: each known mechanism maps to a single surface
/// edit, and the proposal is skipped (null) when no rule matches or the target
/// surface is already set — so a proposal is always Grounded, Distinct, and
/// Minimal (it never clobbers existing configuration). The LLM-driven
/// K-candidate generation is a later refinement.
class HarnessProposalService {
  const HarnessProposalService();

  HarnessConfigProposal? propose({
    required FailureCluster cluster,
    required ModelHarnessConfig base,
  }) {
    switch (cluster.signature.mechanism) {
      case 'stale_old_text':
        if (base.failureRecoveryInstruction.trim().isNotEmpty) {
          return null;
        }
        return HarnessConfigProposal(
          mechanism: 'stale_old_text',
          surface: 'failureRecoveryInstruction',
          rationale:
              'Edits failed on stale old_text; instruct a re-read before retry.',
          proposedConfig: base.copyWith(
            failureRecoveryInstruction:
                'Before retrying a failed edit, re-read the file to refresh '
                'old_text, then verify each successful edit with read_file.',
          ),
        );
      case 'malformed_json':
      case 'malformed_tool_call':
        if (base.recoveryMiddlewareEnabled) {
          return null;
        }
        return HarnessConfigProposal(
          mechanism: cluster.signature.mechanism,
          surface: 'recoveryMiddlewareEnabled',
          rationale:
              'Tool calls were malformed; enable recovery middleware to '
              're-prompt on tool errors.',
          proposedConfig: base.copyWith(recoveryMiddlewareEnabled: true),
        );
      default:
        return null;
    }
  }
}
