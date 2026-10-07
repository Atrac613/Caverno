import 'reasoning_only_stop.dart';

typedef RecoveryText = ({
  String label,
  String reason,
  String error,
  String action,
  String? lead,
});

/// Recovery protocol explanations, separate from trigger detection.
abstract final class CodingRecoveryText {
  static const _texts = <String, RecoveryText>{
    'project_verification_repair': (
      label: 'project verification repair recovery',
      reason: 'A captured project verification failure remains unresolved.',
      error:
          'The failed verification needs diagnosis and an authorized repair.',
      action:
          'Diagnose the captured failure, repair task-related code and rerun the same check, or report an evidenced external blocker.',
      lead: null,
    ),
    'structured_project_subtask': (
      label: 'structured project subtask recovery',
      reason: 'The intermediate project subtask has unresolved requirements.',
      error: 'The subtask completion marker or execution evidence is missing.',
      action:
          'Resolve the subtask requirements without completing the parent goal.',
      lead: null,
    ),
    'structured_coding_task_status': (
      label: 'structured coding task status recovery',
      reason:
          'The project task has no terminal structured goal acknowledgement.',
      error: 'The project task needs a structured goal status report.',
      action:
          'Call update_goal with a JSON boolean completed value, using the captured execution evidence.',
      lead: null,
    ),
    'unexecuted_delegation': (
      label: 'unexecuted delegation recovery',
      reason:
          'The parent promised delegation without a spawn_subagent tool result.',
      error: 'Delegation was described but spawn_subagent was not called.',
      action:
          'Call spawn_subagent now, or state that delegation did not occur.',
      lead:
          'The previous answer promised delegation, but no spawn_subagent call was executed. Call spawn_subagent now if the task is ready; otherwise state the blocker and that delegation did not occur.',
    ),
    'length_truncated_pending_action': (
      label: 'length-truncated pending action recovery',
      reason:
          'The assistant reached the output-token limit while trusted tool evidence still showed incomplete executable coding work.',
      error:
          'The assistant reached the output-token limit before issuing the next executable coding action.',
      action:
          'Issue exactly one available tool call that advances the incomplete work.',
      lead: null,
    ),
    'bracketed_coding_tool_request': (
      label: 'bracketed coding tool request recovery',
      reason:
          'The assistant returned a bracketed coding tool request in final-answer text instead of issuing an executable tool call.',
      error:
          'The assistant response contained a bracketed coding tool request, but no executable tool call was issued.',
      action:
          'Issue the requested coding tool call now. Do not describe bracketed tool blocks as already executed.',
      lead:
          'The previous assistant response contained a bracketed coding tool request in final-answer text, but no tool call was issued.',
    ),
    ReasoningOnlyStop.recoveryCode: (
      label: ReasoningOnlyStop.label,
      reason: ReasoningOnlyStop.reason,
      error: ReasoningOnlyStop.reason,
      action: ReasoningOnlyStop.requiredAction,
      lead: ReasoningOnlyStop.lead,
    ),
  };

  static const RecoveryText _proseText = (
    label: 'prose-only coding continuation recovery',
    reason:
        'The assistant returned coding continuation prose instead of using an available coding tool.',
    error:
        'The assistant response described a future coding action, but no tool call was issued.',
    action:
        'Use an available file, command, or test tool now. Do not restate the plan.',
    lead:
        'The previous assistant response was a coding continuation, but no tool call was issued.',
  );

  static RecoveryText forCode(String code) => _texts[code] ?? _proseText;

  static String promptLead(String code) =>
      forCode(code).lead ?? _proseText.lead!;
}
