import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/conversation_goal.dart';
import '../entities/tool_call_info.dart';
import 'goal_update_ack.dart';
import 'project_task_terminal_status.dart';
import 'tool_definition_search_service.dart';
import 'tool_result_prompt_builder.dart';
import 'unresolved_verification_failure.dart';

/// Settles an intermediate subtask without completing its parent goal.
final class ProjectTaskStepCompletionPolicy {
  const ProjectTaskStepCompletionPolicy();

  static const doneMarker = 'PROJECT_TASK_SUBTASK_DONE';
  static const recoveryCode = 'structured_project_subtask';

  bool applies({required ConversationGoal? goal, required bool stepTurn}) =>
      stepTurn && goal?.projectTaskAutoReview == true;

  ProjectTaskTerminalStatus status({
    required String response,
    required List<ToolResultInfo> results,
    required ConversationGoal? goal,
    String? taskId,
  }) {
    final evidence = ToolResultPromptBuilder.completionEvidence(results);
    final lastChange = results.lastIndexWhere(
      (result) =>
          result.outcome?.fileMutations.any(
            (mutation) => mutation.changed == true,
          ) ==
          true,
    );
    final changed = lastChange >= 0;
    final freshVerification = lastChange < 0
        ? evidence.hasSuccessfulExecutionVerification
        : evidence.hasSuccessfulExecutionVerification &&
              ToolResultPromptBuilder.completionEvidence(
                results.skip(lastChange + 1).toList(),
              ).hasSuccessfulExecutionVerification;
    final failure = const UnresolvedVerificationFailure().describe(results);
    final gaps = <String>[
      if (ContentParser.stripModelHistoryArtifacts(
            response,
          ).trimRight().split('\n').last.trim() !=
          doneMarker)
        'The subtask has no terminal $doneMarker line.',
      if (failure != null || evidence.hasFailedExecutionVerification)
        failure ??
            'Subtask execution verification failed and has not passed since.',
      if (evidence.unresolvedErrorCount > 0)
        'Subtask verification has ${evidence.unresolvedErrorCount} unresolved errors.',
      if ((changed ||
              evidence.mutatedWithoutExecutionVerification ||
              evidence.unverifiedChangePaths.isNotEmpty ||
              evidence.hasExecutionVerification) &&
          !freshVerification)
        changed
            ? 'The subtask needs successful execution verification after its latest change.'
            : 'The subtask needs successful terminal execution verification.',
      if (evidence.hasUnexecutedActionClaim ||
          evidence.unexecutedToolNames.any(
            (name) =>
                const ToolCapabilityClassifier()
                    .classify(name)
                    .capabilityClass !=
                ToolCapabilityClass.readOnlyInspection,
          ))
        'Required subtask tool actions remain unexecuted.',
      if (goal?.status == ConversationGoalStatus.blocked)
        goal?.blockedReason ?? 'The project task is blocked.',
    ];
    return ProjectTaskTerminalStatus.subtask(
      taskId: taskId,
      accepted: gaps.isEmpty,
      gaps: gaps,
    );
  }

  bool shouldRecover({
    required ProjectTaskTerminalStatus status,
    required ConversationGoal? goal,
    required bool boundarySafe,
    required GoalUpdateAckOutcome? acknowledgement,
  }) =>
      !status.completionAccepted &&
      boundarySafe &&
      goal?.isActive == true &&
      goal!.status == ConversationGoalStatus.active &&
      !goal.budgetExceeded &&
      acknowledgement != GoalUpdateAckOutcome.blockerLogged;

  bool acceptsCalls(
    List<ToolCallInfo> calls,
    List<Map<String, dynamic>> offered,
  ) {
    final names = ToolDefinitionSearchService.toolNamesFromDefinitions(offered);
    return calls.isNotEmpty &&
        calls.every(
          (call) =>
              names.contains(call.name) &&
              (call.name != 'update_goal' ||
                  GoalUpdateInput.fromArguments(call.arguments).isValid &&
                      call.arguments['completed'] == false),
        );
  }

  String prompt(ProjectTaskTerminalStatus status) =>
      'This is an intermediate project subtask. Its recorded requirements '
      'are still open:\n${status.gaps.map((gap) => '- $gap').join('\n')}\n'
      'Use the existing tool evidence and perform only the missing subtask '
      'work through the offered tools and normal approval gates. If a '
      'verification failed, inspect its output and rerun that verification '
      'until it passes; prose declaring a false positive does not settle it. '
      'When verification is already complete and only the final marker is '
      'missing, return the final report with $doneMarker on its own last '
      'line without repeating tools. Omit that marker while any requirement '
      'remains. Reuse the interpreter and working directory of '
      'captured successful checks. A failed combined check needs a successful '
      'rerun of the entire verification chain; keep its prerequisite checks '
      'when using the working runtime. Report a concrete blocker with '
      'update_goal(completed: false, '
      'blocked_reason: ...). Never mark the overall goal complete or start '
      'later subtasks. Keep the response in the conversation language.';
}
