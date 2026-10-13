import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/claims/final_answer_recovery_policy.dart';
import '../../domain/services/tool_loop/tool_role_answer_acceptance.dart';
import '../../domain/services/tool_results/tool_result_prompt_builder.dart';
import 'primary_turn_route_runtime.dart';
import 'response_metadata_registry.dart';
import 'turn_finalization_state_registry.dart';

/// Shadow of [ToolRoleAnswerAcceptance]: records, as a turn transform,
/// whether the tool loop's own complete answer would have stood, while the
/// regeneration still runs.
///
/// Keeping the answer for real needs every final-answer guard re-proven on
/// it: 23 guard tests script a different answer for the re-send than for the
/// tool loop. Until then this measures how often the policy would accept, on
/// the same tool results and completion evidence the re-send uses.
abstract final class ToolRoleAnswerShadow {
  static void record({
    required TurnFinalizationStateRegistry turnEnd,
    required ResponseMetadataRegistry responseMetadata,
    required PrimaryTurnRouteRuntime routes,
    required ChatTurnOwner owner,
    required List<ToolResultInfo> toolResults,
    ToolResultCompletionEvidence? completionEvidence,
  }) {
    final answer = turnEnd.takeToolRoleAnswer(owner);
    if (answer == null) return;
    final g = owner.interactionGeneration;
    final decision = ToolRoleAnswerAcceptance.decide(
      candidate: answer,
      // An answer the concise-retry policy would repair is not kept.
      truncated:
          const FinalAnswerRecoveryPolicy().recoveryReason(
            content: ContentParser.stripToolArtifacts(answer),
            finishReason: responseMetadata.finishReasonFor(owner),
          ) !=
          null,
      eligibleTurn:
          !routes.isProjectTaskCommit(g) &&
          !routes.isProjectTaskCommitPreparation(g) &&
          !routes.isCodeReview(g),
      requiredMarker: ToolRoleAnswerAcceptance.requiredMarkerFor(
        projectTaskStep: routes.isProjectTaskStep(g),
        projectTaskImplementation: routes.isProjectTaskImplementation(g),
      ),
      completionBlockers: ToolResultPromptBuilder.completionBlockerInstructions(
        toolResults,
        completionEvidence: completionEvidence,
      ),
    );
    appLog('[Tool] Tool-role final answer shadow decision: ${decision.name}');
    turnEnd.addTransform(owner, 'tool_role_answer_shadow_${decision.name}');
  }
}
