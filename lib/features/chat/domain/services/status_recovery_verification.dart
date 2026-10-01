import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/conversation_goal.dart';
import '../entities/tool_call_info.dart';
import 'goal_update_ack.dart';
import 'project_task_completion_evidence.dart';
import 'structured_coding_task_recovery_policy.dart';
import 'tool_definition_search_service.dart';
import 'tool_result_prompt_builder.dart';

/// Lets a project-task status recovery run the verification that the
/// completion gate itself demands.
///
/// The recovery offered and accepted only update_goal, while the gate refuses
/// completed: true until a successful execution verification follows the
/// latest change. In session 02fec5c8 the model answered both status requests
/// with exactly that verification command; both were refused, no completion
/// was recorded, and the farm task stopped with its work done. While that gap
/// is open the recovery also offers the execution tools and accepts one call
/// the capability classifier rates as verification, never an edit.
final class StatusRecoveryVerification {
  const StatusRecoveryVerification();

  static const _executionTools = {'local_execute_command', 'run_tests'};

  /// Whether the completion gate would report the verification gap.
  bool gapOpen(List<ToolResultInfo> results, ConversationGoal? goal) =>
      const ProjectTaskCompletionEvidence()
          .gaps(
            toolResults: results,
            evidence: ToolResultPromptBuilder.completionEvidence(results),
            inheritedChanges:
                goal?.projectTaskInheritedPaths.isNotEmpty ?? false,
          )
          // The gate's own wording; pinned by the test of this class.
          .any((gap) => gap.contains('execution verification'));

  /// The tools and prompt of a status request for a turn with [results].
  ({List<Map<String, dynamic>> tools, String prompt}) request(
    List<Map<String, dynamic>> allTools,
    List<ToolResultInfo> results,
    ConversationGoal? goal,
    StructuredCodingTaskRecoveryPolicy taskPolicy,
  ) {
    final gap = gapOpen(results, goal);
    return (
      tools: tools(allTools, verificationGap: gap),
      prompt: prompt(taskPolicy.prompt, verificationGap: gap),
    );
  }

  /// Every call an update_goal, as before, or [accepts].
  bool acceptsStatus(
    List<ToolCallInfo> calls,
    List<Map<String, dynamic>> offered,
  ) =>
      (calls.isNotEmpty && calls.every((call) => call.name == 'update_goal')) ||
      accepts(calls, offered);

  /// update_goal, plus the execution tools while [verificationGap] is open.
  List<Map<String, dynamic>> tools(
    List<Map<String, dynamic>> allTools, {
    required bool verificationGap,
  }) => allTools
      .where((tool) {
        final name = ToolDefinitionSearchService.toolNameFromDefinition(tool);
        return name == 'update_goal' ||
            (verificationGap && _executionTools.contains(name));
      })
      .toList(growable: false);

  /// One valid update_goal, or one verification call among [offered].
  bool accepts(List<ToolCallInfo> calls, List<Map<String, dynamic>> offered) {
    if (calls.length != 1) return false;
    final call = calls.single;
    if (call.name == 'update_goal') {
      return GoalUpdateInput.fromArguments(call.arguments).isValid;
    }
    return offered.any(
          (tool) =>
              ToolDefinitionSearchService.toolNameFromDefinition(tool) ==
              call.name,
        ) &&
        const ToolCapabilityClassifier()
                .classify(call.name, arguments: call.arguments)
                .commandEffect ==
            ToolCommandEffect.verification;
  }

  String prompt(String statusPrompt, {required bool verificationGap}) =>
      verificationGap ? _verificationPrompt : statusPrompt;

  static const _verificationPrompt =
      'Before ending this project implementation turn, report its state with '
      'update_goal. The latest change has no successful execution '
      'verification yet, and completed: true will not be recorded without '
      'one. If the work is otherwise done, run exactly one verification '
      'command now with local_execute_command or run_tests, then report with '
      'update_goal. Otherwise call update_goal with completed: false and a '
      'message when work remains, or blocked_reason when a concrete blocker '
      'prevents further work. Prose does not settle the task state. Preserve '
      'completed work and reuse existing tool results. Keep the visible '
      'response in the conversation language.';
}
