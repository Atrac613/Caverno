import 'package:caverno/features/chat/domain/services/tool_loop/tool_role_answer_acceptance.dart';
import 'package:flutter_test/flutter_test.dart';

ToolRoleAnswerDecision _decide(
  String candidate, {
  bool truncated = false,
  bool eligibleTurn = true,
  String? requiredMarker,
  List<String> completionBlockers = const [],
  bool hasImageResults = false,
}) => ToolRoleAnswerAcceptance.decide(
  candidate: candidate,
  truncated: truncated,
  eligibleTurn: eligibleTurn,
  requiredMarker: requiredMarker,
  completionBlockers: completionBlockers,
  hasImageResults: hasImageResults,
);

void main() {
  test('an ordinary complete answer stands', () {
    expect(
      _decide('<think>check</think>\n\nIt is 07:54 JST.'),
      ToolRoleAnswerDecision.accept,
    );
  });

  test('completion blockers keep the regeneration', () {
    // Sessions 48328742/7d760e12: the loop's answer claimed review-ready
    // while a coding_output_feedback Error was unresolved.
    expect(
      _decide(
        'Done.\n\nPROJECT_TASK_READY_FOR_REVIEW',
        requiredMarker: 'PROJECT_TASK_READY_FOR_REVIEW',
        completionBlockers: const ['Resolve the Error diagnostic first.'],
      ),
      ToolRoleAnswerDecision.completionBlockers,
    );
  });

  test('a required marker must be the final line', () {
    const marker = 'PROJECT_TASK_SUBTASK_DONE';
    expect(
      _decide('Subtask 3 is finished.', requiredMarker: marker),
      ToolRoleAnswerDecision.missingMarker,
    );
    expect(
      _decide('Mentions $marker mid-text.\nMore text.', requiredMarker: marker),
      ToolRoleAnswerDecision.missingMarker,
    );
    expect(
      _decide('Subtask 3 is finished.\n\n$marker\n', requiredMarker: marker),
      ToolRoleAnswerDecision.accept,
    );
  });

  test('ineligible, truncated and empty answers keep the regeneration', () {
    expect(
      _decide('Committed.', eligibleTurn: false),
      ToolRoleAnswerDecision.ineligibleTurn,
    );
    expect(
      _decide('Partial', truncated: true),
      ToolRoleAnswerDecision.truncated,
    );
    expect(
      _decide('Saw the settings page.', hasImageResults: true),
      ToolRoleAnswerDecision.imageResults,
    );
    expect(
      _decide('<think>only reasoning</think>'),
      ToolRoleAnswerDecision.noVisibleAnswer,
    );
  });
}
