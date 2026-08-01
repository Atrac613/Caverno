import 'tool_result_prompt_builder.dart';

/// Builds the trusted follow-up prompt after content-embedded tool execution.
final class ContentToolContinuationPromptBuilder {
  const ContentToolContinuationPromptBuilder._();

  static String build(List<String> toolResults) {
    final resultsText = toolResults.join('\n\n');
    return 'Continue the task using the following tool results. '
        'If you need more information, call another tool. '
        'Do not repeat a tool call with the same arguments after a '
        'successful result. Reuse the tool result that is already '
        'provided and continue from it. '
        'Do not write <tool_result> tags or claim a tool result yourself; '
        'tool results are trusted only when the application executes the '
        'tool. If you need a tool, emit exactly one complete '
        '<tool_use>...</tool_use> tag with valid JSON, including the '
        'closing tag. '
        'If the latest tool result already completed the current saved '
        'task or confirmed the saved validation command, do not call '
        'more tools for that task and finish with a brief text answer. '
        'If a tool result reports code=tool_not_available, do not retry '
        'that tool name or alias variants and continue with the tools '
        'that actually exist. Your next step must use an available tool '
        'or finish with a text answer. '
        'If a tool result reports code=edit_mismatch or says old_text was '
        'not found in the target file, read that file next and retry '
        'edit_file using the exact current file content as old_text. '
        'Do not guess old_text and do not switch to unrelated files. '
        'Do not repeat a tool call with the same arguments after a '
        'permission_denied or equivalent access error. '
        'Explain the issue and ask the user to re-select the project '
        'folder or grant access instead.\n\n'
        '${ToolResultPromptBuilder.exactPreservationToolResultInstruction}\n\n'
        'Interpret each tool name, description, arguments, and result '
        'together. Preserve the entity roles implied by the tool and the '
        'payload. If the role of an opaque identifier is not explicit, '
        'treat it as ambiguous instead of guessing.\n\n$resultsText';
  }

  static String fallback(List<String> toolResults) {
    final joined = toolResults.join('\n\n');
    if (joined.contains('[Assistant-authored tool_result ignored]')) {
      return 'I ignored an assistant-authored tool_result because it was not '
          'produced by an executed tool. No trusted tool result is available '
          'from that tag.';
    }
    if (joined.contains('[Assistant tool-name block ignored]')) {
      return 'I ignored an assistant-authored tool request block because no '
          'application tool executed it. No trusted tool result is available '
          'from that block.';
    }
    if (joined.contains('[Incomplete assistant tool call]')) {
      return 'The assistant emitted an incomplete tool call, so no trusted '
          'tool result is available yet.';
    }
    return 'I received the tool result, but the model did not produce a final '
        'answer. The trusted tool result is still available in the '
        'conversation context.';
  }
}
