import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';

/// Decides which earlier tool results a follow-up request has to carry again.
///
/// A follow-up otherwise carries only the batch that just ran, which is what
/// keeps the payload bounded: most results are acted on once and then named by
/// the context digest rather than repeated. For a few, the content *is* a
/// standing instruction the model has to keep reading, and dropping it does not
/// save anything -- the model asks for it again.
///
/// Session f3ec19ca spent 27.5% of its tokens on 16 requests whose only output
/// was a `load_skill` for a skill it had already been handed: dropped at every
/// step, re-requested, then supplied by duplicate-follow-up recovery one wasted
/// round trip later.
final class StickyToolResultPolicy {
  const StickyToolResultPolicy({
    ToolCallExecutionPolicy executionPolicy = const ToolCallExecutionPolicy(),
  }) : _executionPolicy = executionPolicy;

  final ToolCallExecutionPolicy _executionPolicy;

  static const Set<String> stickyToolNames = {'ask_user_question', 'load_skill'};

  List<ToolResultInfo> resolve({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolResultInfo> executedToolResults,
  }) {
    if (batchToolResults.isEmpty) {
      return batchToolResults;
    }
    // Superseded per name, not globally: a batch that just answered a question
    // replaces the older answer, and says nothing about a skill loaded before
    // it.
    final superseded = batchToolResults
        .map((toolResult) => toolResult.name)
        .where(stickyToolNames.contains)
        .toSet();
    final byKey = <String, ToolResultInfo>{};
    for (final toolResult in executedToolResults) {
      if (!stickyToolNames.contains(toolResult.name) ||
          superseded.contains(toolResult.name)) {
        continue;
      }
      // Latest wins per distinct call, so a skill reloaded during the turn is
      // carried once rather than once per reload.
      byKey[_executionPolicy.toolResultDedupKey(toolResult)] = toolResult;
    }
    if (byKey.isEmpty) {
      return batchToolResults;
    }
    return <ToolResultInfo>[...byKey.values, ...batchToolResults];
  }
}
