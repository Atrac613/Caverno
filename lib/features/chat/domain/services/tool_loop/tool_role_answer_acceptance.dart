import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../project_task/project_task_status_contract.dart';

/// Whether a turn may keep the complete answer its tool loop already produced
/// instead of regenerating it from a user-role re-send of the tool results.
enum ToolRoleAnswerDecision {
  accept,

  /// The re-send states completion blockers the tool-role turn never saw, so
  /// it can withhold a completion the loop's answer claimed.
  completionBlockers,

  /// The turn is settled by a marker line the loop's answer does not end with.
  missingMarker,

  /// A turn whose answer has a contract this policy does not model.
  ineligibleTurn,
  noVisibleAnswer,
  truncated,
}

/// Decides when the tool-role answer can stand.
///
/// The regeneration costs a median 42 s and 17.9k prompt tokens prefilled
/// without the loop's cache (391 occurrences by 2026-10-14). In 20 random
/// pairs it was never worse and was better 3 times: twice it withheld a
/// review-ready marker an unresolved blocker contradicted, once it restored a
/// required marker. Across all 391, every such case had completion blockers
/// or a missing required marker, which is where this keeps the regeneration.
/// See docs/worklog/tool_role_answer_regeneration_2026-10-14.md.
abstract final class ToolRoleAnswerAcceptance {
  /// The final line a project-task turn's protocol requires, if any.
  static String? requiredMarkerFor({
    required bool projectTaskStep,
    required bool projectTaskImplementation,
  }) => projectTaskStep
      ? projectTaskSubtaskDoneMarker
      : projectTaskImplementation
      ? projectTaskReadyForReviewMarker
      : null;

  /// [requiredMarker] is the exact final line the turn's protocol requires,
  /// or null when it requires none. [eligibleTurn] is false for turns whose
  /// answer carries a contract this policy does not check.
  static ToolRoleAnswerDecision decide({
    required String candidate,
    required bool truncated,
    required bool eligibleTurn,
    required String? requiredMarker,
    required List<String> completionBlockers,
  }) {
    if (!eligibleTurn) return ToolRoleAnswerDecision.ineligibleTurn;
    if (truncated) return ToolRoleAnswerDecision.truncated;
    final visible = ContentParser.stripModelHistoryArtifacts(candidate).trim();
    if (visible.isEmpty) return ToolRoleAnswerDecision.noVisibleAnswer;
    if (completionBlockers.isNotEmpty) {
      return ToolRoleAnswerDecision.completionBlockers;
    }
    if (requiredMarker != null &&
        visible.split('\n').last.trim() != requiredMarker) {
      return ToolRoleAnswerDecision.missingMarker;
    }
    return ToolRoleAnswerDecision.accept;
  }
}
