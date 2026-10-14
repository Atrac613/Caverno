import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/claims/final_answer_recovery_policy.dart';
import '../../domain/services/plan/proposal_parsing_text_utils.dart';
import '../../domain/services/tool_loop/tool_role_answer_acceptance.dart';
import '../../domain/services/tool_results/tool_result_prompt_builder.dart';
import 'primary_turn_route_runtime.dart';
import 'response_metadata_registry.dart';
import 'turn_finalization_state_registry.dart';

/// Applies [ToolRoleAnswerAcceptance] where the re-send would be built, on the
/// same tool results and completion evidence it uses.
///
/// Every decision is recorded as a `tool_role_answer_shadow_<decision>` turn
/// transform, and a kept answer also as `tool_role_answer_kept`. The answer
/// is kept only when [AppSettings.keepToolRoleFinalAnswer] is on (the
/// default); turning it off restores the unconditional re-send.
abstract final class ToolRoleAnswerShadow {
  /// Returns the tool loop's answer when [keep] is on and the policy accepts
  /// it, else null.
  static String? record({
    required bool keep,
    required TurnFinalizationStateRegistry turnEnd,
    required ResponseMetadataRegistry responseMetadata,
    required PrimaryTurnRouteRuntime routes,
    required ChatTurnOwner owner,
    required List<ToolResultInfo> toolResults,
    ToolResultCompletionEvidence? completionEvidence,
  }) {
    final answer = turnEnd.takeToolRoleAnswer(owner);
    if (answer == null) return null;
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
      hasImageResults: toolResults.any(_carriesImage),
    );
    appLog('[Tool] Tool-role final answer shadow decision: ${decision.name}');
    turnEnd.addTransform(owner, 'tool_role_answer_shadow_${decision.name}');
    if (!keep || decision != ToolRoleAnswerDecision.accept) return null;
    turnEnd.addTransform(owner, 'tool_role_answer_kept');
    return answer;
  }

  /// Mirrors what `ToolAnswerMessages` attaches to the re-send as an image.
  static bool _carriesImage(ToolResultInfo result) {
    final image = ProposalParsingTextUtils.tryDecodeMap(
      result.result,
    )?['imageBase64'];
    return image is String && image.isNotEmpty;
  }
}
