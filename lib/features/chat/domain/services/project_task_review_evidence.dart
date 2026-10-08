import '../entities/tool_call_info.dart';
import 'claims/final_answer_claim_detector.dart';
import 'project_task_review_verdict.dart';
import 'tool_result_prompt_builder.dart';

/// Judges a review against current inspection and verification evidence.
abstract final class ProjectTaskReviewEvidence {
  static ProjectTaskReviewVerdict resolve({
    required String response,
    required String finishReason,
    required List<ToolResultInfo> results,
    required bool inspectionMissing,
  }) {
    var verdict = ProjectTaskReviewVerdict.fromResponse(response);

    if (inspectionMissing) {
      verdict = verdict.incomplete(
        FinalAnswerClaimDetector.unverifiedReadOnlyInspectionNotice,
      );
    } else if (finishReason == 'length') {
      verdict = verdict.incomplete('The review response was truncated.');
    } else if (verdict.disposition == ProjectTaskReviewDisposition.clean &&
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).hasBlockingEvidence) {
      verdict = verdict.incomplete(
        'The review has an unresolved verification failure.',
      );
    }
    return verdict;
  }
}
