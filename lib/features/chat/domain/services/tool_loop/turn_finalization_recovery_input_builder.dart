import '../../entities/tool_call_info.dart';
import '../claims/final_answer_claim_detector.dart';
import '../file_mutation_evidence_policy.dart';
import 'turn_finalization_recovery_policy.dart';

/// Combines turn-owned validation facts with pure tool-result evidence.
abstract final class TurnFinalizationRecoveryInputBuilder {
  static TurnFinalizationRecoveryInput build(
    String response,
    String? streamedAnswer,
    List<ToolResultInfo> results, {
    required bool timedOut,
    required bool failedValidation,
    required bool savedValidation,
  }) {
    const claims = FinalAnswerClaimDetector();
    const mutations = FileMutationEvidencePolicy();
    return TurnFinalizationRecoveryInput(
      candidateResponse: response,
      streamedFinalAnswer: streamedAnswer,
      toolResults: results,
      hasTimedOutCommandResult: timedOut,
      hasFailedCommandValidation: failedValidation,
      hasSuccessfulCurrentSavedValidation: savedValidation,
      hasUnexecutedCommandActionResult: claims.hasUnexecutedCommandActionResult(
        results,
      ),
      hasUnexecutedFileSideEffectResult: claims
          .hasUnexecutedFileSideEffectResult(results),
      hasSuccessfulFileMutationEvidence: results.any(
        (result) =>
            mutations.isMutationToolName(result.name) &&
            mutations.isSuccessfulResult(result),
      ),
      hasSuccessfulCommandExecutionEvidence: claims
          .hasSuccessfulCommandExecutionResult(results),
    );
  }
}
