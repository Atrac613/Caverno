import 'tool_result_prompt_builder.dart';
import 'verification_cadence_policy.dart';

/// Builds the redacted `goal_auto_continue` evidence marker written to the
/// session log.
///
/// The shape is a contract read by `tool/triage_session_logs.py`, so it lives
/// beside the policy rather than inside the notifier: a field added here is a
/// field the triage tooling can rely on, and the assembly needs nothing from
/// the notifier but values.
abstract final class GoalAutoContinueEvidenceMarker {
  static Map<String, dynamic> build({
    required ToolResultCompletionEvidence evidence,
    required VerificationCadence verificationCadence,
    required int? mutationGeneration,
    required int? verificationGeneration,
    required String? safeBoundaryVeto,
    required int noProgressStreak,
    required int diagnosticRepairContinuations,
    required int consecutiveValidationMisses,
    required bool diagnosticRepairExtensionUsed,
    required int? previousUnresolvedErrorCount,
    required int identicalDiagnosticSignatureStreak,
  }) {
    return {
      'summary': evidence.summary,
      'hasIncompleteEvidence': evidence.hasIncompleteEvidence,
      // The cadence is the other half of the continuation gate, and its
      // absence made a skip undiagnosable from the log alone: a real session
      // showed cadence `required` in the prompt one second before
      // auto-continue skipped, with no way to tell what the policy received.
      // See docs/session_cfaa8297_cadence_not_observable_2026-07-22.md.
      'verificationCadence': verificationCadence.name,
      'mutationGeneration': mutationGeneration,
      'verificationGeneration': verificationGeneration,
      'hasBlockingEvidence': evidence.hasBlockingEvidence,
      'hasUnexecutedActionClaim': evidence.hasUnexecutedActionClaim,
      'safeBoundaryVeto': safeBoundaryVeto,
      'noProgressStreak': noProgressStreak,
      'diagnosticRepairContinuations': diagnosticRepairContinuations,
      'consecutiveValidationMisses': consecutiveValidationMisses,
      'diagnosticRepairExtensionUsed': diagnosticRepairExtensionUsed,
      'previousUnresolvedErrorCount': previousUnresolvedErrorCount,
      'diagnosticSignaturePresent': evidence.diagnosticSignature.isNotEmpty,
      'identicalDiagnosticSignatureStreak': identicalDiagnosticSignatureStreak,
      'boundedToolLoopExhausted': evidence.boundedToolLoopExhausted,
      'unexecutedToolNames': evidence.unexecutedToolNames,
      'unresolvedErrorCount': evidence.unresolvedErrorCount,
      'unresolvedErrorPaths': evidence.unresolvedErrorPaths,
      'unverifiedChangePaths': evidence.unverifiedChangePaths,
      'mutatedWithoutExecution': evidence.mutatedWithoutExecutionVerification,
    };
  }
}
