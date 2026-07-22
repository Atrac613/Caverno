import '../entities/conversation_goal.dart';
import 'conversation_goal_auto_continue_policy.dart';
import 'execution_snapshot_projector.dart';
import 'tool_result_prompt_builder.dart';

/// Builds the prompt that drives one automatic goal continuation.
///
/// Pure: every input is a parameter and the output is a string, so the wording
/// that steers a continuation can be read and tested without standing up a
/// notifier. Extracted from the chat-notifier library, where it was the
/// largest block of logic that needed nothing from it.
abstract final class GoalAutoContinuePromptBuilder {
  static String build({
    required ConversationGoal goal,
    required ToolResultCompletionEvidence evidence,
    required ExecutionSnapshot executionSnapshot,
    required String? repairContract,
    required bool repairNoMutationRetry,
    required GoalAutoContinueCapabilityProfile capabilityProfile,
    required int nextTurnNumber,
    required int effectiveTurnBudget,
    required String languageCode,
  }) {
    final normalizedLanguageCode = languageCode.trim().isEmpty
        ? 'en'
        : languageCode.trim();
    return [
      'Automatic goal continuation $nextTurnNumber/$effectiveTurnBudget.',
      '',
      'Goal objective:',
      goal.objective.trim(),
      '',
      'Concrete incomplete evidence from the previous turn:',
      evidence.summary,
      if (executionSnapshot.hasContract) ...[
        '',
        'Current execution snapshot:',
        '<execution_snapshot>',
        executionSnapshot.toPromptContext(),
        '</execution_snapshot>',
      ],
      if (repairContract != null) ...['', repairContract],
      if (repairNoMutationRetry) ...[
        '',
        'The previous constrained repair turn ended without a file mutation. '
            'This is the only retry. Do not narrate another future action. '
            'Use read_file only if essential, then call exactly one available '
            'write, edit, or delete tool in this turn. If no safe mutation is '
            'possible, state the concrete blocker instead.',
      ],
      '',
      if (capabilityProfile == GoalAutoContinueCapabilityProfile.repair) ...[
        'This is a repair-only continuation. Use the available file tools to '
            'make the contract repair now. Do not run a verification command; '
            'the harness will replay the saved verifier after a mutation.',
      ] else if (capabilityProfile ==
          GoalAutoContinueCapabilityProfile.validation) ...[
        'This is a validation-only continuation. Only verification-effect '
            'commands are accepted; inspection, setup, and shell-based file '
            'mutation will be rejected. Run the available project verifier '
            'now. A verifier request that was '
            'left unexecuted by the previous tool-loop boundary must be '
            'retried before any other work. Finish immediately if it succeeds. '
            'If it fails, report the concrete failure and finish this turn; '
            'the next bounded continuation will provide repair tools.',
      ] else if (evidence.hasUnexecutedActionClaim) ...[
        'The previous answer claimed file or command actions without tool '
            'evidence. Do not repeat or summarize those claims. Use the '
            'available file and command tools now to perform the requested '
            'work, then verify it with execution evidence.',
      ] else
        'Continue the work now. Use the available diagnostics and tools to '
            'make progress, then verify the result when a verification path '
            'is available. If you are genuinely blocked, state the blocking '
            'condition clearly instead of retrying the same action.',
      'Do not end this turn by saying you will inspect, edit, or verify later; '
          'call an available tool now unless you are already at a concrete '
          'blocking condition.',
      '',
      'Keep the visible response language aligned with language code '
          '"$normalizedLanguageCode".',
    ].join('\n');
  }
}
