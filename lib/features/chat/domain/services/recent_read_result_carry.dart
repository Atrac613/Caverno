import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'sticky_tool_result_policy.dart';
import 'tool_call_execution_policy.dart';

/// Carries a bounded tail of recent read-only results into the next follow-up.
///
/// A follow-up otherwise holds the current batch and nothing else but
/// `ask_user_question` / `load_skill` (`StickyToolResultPolicy`), and
/// `ToolLoopContextDigest` names what an earlier call returned without its
/// output. One round trip therefore retains exactly one fact, so a step that
/// needs two at once can never assemble them.
///
/// Session 64bad560 is the failure: asked to bump a version, the model needed
/// the latest tag and the current `pubspec.yaml` together to decide the next
/// number. It read them alternately for 12 iterations and 9m29s, each fetch
/// evicting the one before it, and the turn ended without a version bumped.
/// Its own reasoning names the cause -- "the output wasn't carried over. Let
/// me run it again" -- which is the digest's instruction followed exactly. The
/// same prompt failed 3 of 3 runs on that model.
///
/// The two facts it needed were 522 B and 3.4 KB. The budget below is measured
/// against 1644 read-only results across 65 local session logs: an individual
/// result is 866 B at the median, 1.9 KB at p75 and 7.7 KB at p95, and a whole
/// log's distinct read-only results total 4.6 KB at the median. So 8 KB holds
/// nine median results, or four p75 ones, and covers the median turn entirely,
/// while the per-result cap stops one 41 KB outlier from evicting everything.
///
/// This costs prefill, not cache: in 64bad560 `cachedPromptTokens` was exactly
/// 8192 -- the system prompt -- on 10 of 12 requests, because the digest and
/// the tool results that follow it change every request anyway. The prefix is
/// already broken where this content lands.
final class RecentReadResultCarry {
  const RecentReadResultCarry({
    ToolCallExecutionPolicy executionPolicy = const ToolCallExecutionPolicy(),
    StickyToolResultPolicy stickyPolicy = const StickyToolResultPolicy(),
  }) : _executionPolicy = executionPolicy,
       _stickyPolicy = stickyPolicy;

  final ToolCallExecutionPolicy _executionPolicy;
  final StickyToolResultPolicy _stickyPolicy;

  /// Largest single result carried, at p95 of the measured corpus.
  static const int maxResultBytes = 8 * 1024;

  /// Total carried bytes, which covers the median turn's whole read-only set.
  static const int budgetBytes = 8 * 1024;

  /// Everything a follow-up request carries: the sticky results, the
  /// carryable tail, then the batch that just ran.
  List<ToolResultInfo> resolve({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolResultInfo> executedToolResults,
  }) => augment(
    // The sticky results are re-sent from earlier iterations too, so they are
    // marked the same way; only the batch that just ran is current.
    resolved: _stickyPolicy
        .resolve(
          batchToolResults: batchToolResults,
          executedToolResults: executedToolResults,
        )
        .map(
          (result) => batchToolResults.any((batch) => identical(batch, result))
              ? result
              : _asHistory(result),
        )
        .toList(growable: false),
    executedToolResults: executedToolResults,
  );

  /// Returns [resolved] with the carryable tail prepended.
  ///
  /// Newest first while the budget lasts, then restored to execution order so
  /// the model reads them the way they happened.
  List<ToolResultInfo> augment({
    required List<ToolResultInfo> resolved,
    required List<ToolResultInfo> executedToolResults,
  }) {
    if (resolved.isEmpty) return resolved;
    final present = resolved.map(_keyFor).toSet();
    final carried = <ToolResultInfo>[];
    var remaining = budgetBytes;
    for (var index = executedToolResults.length - 1; index >= 0; index--) {
      final result = executedToolResults[index];
      // A write invalidates everything read before it: those results describe
      // a workspace that no longer exists, and stating them as current is
      // worse than the digest line that merely names them. A mutating command
      // counts -- `isFileMutationToolCall` sees only the file-writing tools,
      // so a `local_execute_command` that moves a file would otherwise leave
      // every earlier read being carried as if it still held.
      if (_changesTheWorkspace(result)) break;
      if (!present.add(_keyFor(result))) continue;
      if (!_isCarryable(result)) continue;
      final bytes = utf8.encode(result.result).length;
      if (bytes > maxResultBytes) continue;
      if (bytes > remaining) break;
      remaining -= bytes;
      carried.add(result);
    }
    if (carried.isEmpty) return resolved;
    return <ToolResultInfo>[
      for (final result in carried.reversed) _asHistory(result),
      ...resolved,
    ];
  }

  /// Marks a result as re-sent rather than newly arrived, so the request
  /// formatter can place it as its own earlier exchange.
  ToolResultInfo _asHistory(ToolResultInfo result) => ToolResultInfo(
    id: result.id,
    name: result.name,
    arguments: result.arguments,
    result: result.result,
    outcome: result.outcome,
    fromEarlierLoop: true,
  );

  bool _changesTheWorkspace(ToolResultInfo result) {
    final call = _callFor(result);
    if (_executionPolicy.isFileMutationToolCall(call)) return true;
    return _executionPolicy.isCommandExecutionTool(result.name) &&
        !_executionPolicy.isReadOnlyCommandExecutionToolCall(call);
  }

  bool _isCarryable(ToolResultInfo result) {
    final call = _callFor(result);
    if (_executionPolicy.isReadOnlyCommandExecutionToolCall(call)) {
      // An absent exit status means the command never reached one, which is
      // not the same as success and must not be presented as output.
      return result.outcome?.exitCode == 0;
    }
    if (!_executionPolicy.isReadOnlyInspectionTool(result.name)) return false;
    // A reuse payload is a pointer to content, not the content.
    return !result.result.contains('"duplicate_tool_call_result_reused"');
  }

  ToolCallInfo _callFor(ToolResultInfo result) => ToolCallInfo(
    id: result.id,
    name: result.name,
    arguments: result.arguments,
  );

  String _keyFor(ToolResultInfo result) =>
      _executionPolicy.toolResultDedupKey(result);
}
