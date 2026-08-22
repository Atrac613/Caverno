import '../entities/tool_call_info.dart';

/// Builds the prompts that redirect a model repeating itself inside one turn.
///
/// Both prompts used to assert a saved task unconditionally. That framing only
/// holds when a saved task exists: session 96797b74 had none -- `update_goal`
/// had already answered "no active goal" -- yet the inspection prompt still
/// demanded the next reply "modify a saved target file or run the saved
/// validation command", a two-way choice with no reachable branch, during a
/// turn whose request was to commit. The lines that do the work in either case
/// (naming the repeated tools, refusing unbacked file-write claims) are kept
/// in both forms.
final class DuplicateRecoveryPromptBuilder {
  const DuplicateRecoveryPromptBuilder();

  /// Redirects a model that keeps re-inspecting instead of acting.
  String buildInspectionPrompt({
    required List<ToolCallInfo> toolCalls,
    required bool hasSavedTask,
    bool previousCommandValidationFailed = false,
    bool previousExactExitCodeExpectationFailed = false,
    Set<String> budgetReducedToolNames = const {},
  }) {
    final repeatedToolNames = _repeatedToolNames(toolCalls);
    final reduced = _reducedRepeatedToolNames(
      toolCalls,
      budgetReducedToolNames,
    );
    return [
      hasSavedTask
          ? 'You already inspected the same local files for the current saved task.'
          : 'You already inspected the same local files in this turn.',
      if (repeatedToolNames.isNotEmpty)
        'Do not repeat identical read-only inspection tools again in this turn: $repeatedToolNames.',
      if (reduced.isNotEmpty) ..._budgetReductionLines(reduced),
      if (previousCommandValidationFailed)
        'The latest validation command failed; use that failure output now instead of inspecting the directory again.',
      if (previousExactExitCodeExpectationFailed)
        'If the failure is only an exact non-zero exit-code mismatch, edit the verification target to accept any non-zero failure code before rerunning validation.',
      if (hasSavedTask) ...[
        'Take the next concrete saved-task action now.',
        'Your next reply must either modify a saved target file or run the saved validation command.',
        'Do not restate the plan, do not ask for confirmation, and do not switch to a future saved task.',
      ] else ...[
        'Take the next concrete action the user asked for now.',
        'Do not restate the plan and do not ask for confirmation.',
      ],
    ].join('\n');
  }

  /// Redirects a model that re-issues the same follow-up call.
  String buildFollowUpPrompt({
    required List<ToolCallInfo> toolCalls,
    required bool hasSavedTask,
    bool repeatedValidationTool = false,
    bool inspectedFailingFile = false,
    Set<String> budgetReducedToolNames = const {},
  }) {
    final repeatedToolNames = _repeatedToolNames(toolCalls);
    final reduced = _reducedRepeatedToolNames(
      toolCalls,
      budgetReducedToolNames,
    );
    return [
      'You already attempted the same follow-up tool call for the current task.',
      if (repeatedToolNames.isNotEmpty)
        'Do not repeat identical tool calls again in this turn: $repeatedToolNames.',
      if (reduced.isNotEmpty)
        ..._budgetReductionLines(reduced)
      else
        'Use the previous tool results and take the next concrete task step now.',
      'If the user requested local file creation or modification and no successful file mutation result is already provided, your next action must be write_file or edit_file, or a concise blocker that clearly says no files were created.',
      'Do not claim that files were created, edited, saved, moved, or deleted unless the provided tool results include the successful file operation.',
      if (hasSavedTask)
        'If the current saved task still needs work, create or edit the saved target file.',
      if (hasSavedTask && inspectedFailingFile && repeatedValidationTool)
        'If you just read a failing saved target file, your next action must modify that same file before rerunning the saved validation command.',
      if (hasSavedTask && repeatedValidationTool)
        'Do not rerun the same validation command until a saved target file edit changes the current task.',
      if (hasSavedTask)
        'If validation already succeeded, reply with a brief completion statement instead of repeating the same tool call.',
      hasSavedTask
          ? 'Do not restate the plan, do not ask for confirmation, and do not switch to a future saved task.'
          : 'Do not restate the plan and do not ask for confirmation.',
    ].join('\n');
  }

  /// The lines that replace "use the previous tool results" when the prompt
  /// does not actually carry them.
  ///
  /// Telling a model to reuse a result the budget cut is an instruction it
  /// cannot follow, and re-issuing the same call -- the only move left -- is
  /// the one this prompt forbids. Naming the range read gives it a way out that
  /// the duplicate check does not block, because the arguments differ.
  List<String> _budgetReductionLines(String reducedToolNames) => [
    'The earlier $reducedToolNames result was shortened to fit the prompt '
        'budget, so its full content is not available in this conversation.',
    'Do not repeat the same whole-file call. Call read_file with the path, an '
        'offset, and a small limit to fetch only the range you still need, or '
        'act on what you already have.',
  ];

  String _reducedRepeatedToolNames(
    List<ToolCallInfo> toolCalls,
    Set<String> budgetReducedToolNames,
  ) => toolCalls
      .map((toolCall) => toolCall.name.trim())
      .where(
        (name) => name.isNotEmpty && budgetReducedToolNames.contains(name),
      )
      .toSet()
      .join(', ');

  String _repeatedToolNames(List<ToolCallInfo> toolCalls) => toolCalls
      .map((toolCall) => toolCall.name.trim())
      .where((name) => name.isNotEmpty)
      .toSet()
      .join(', ');
}
