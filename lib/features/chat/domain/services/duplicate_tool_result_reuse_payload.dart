import 'dart:convert';

import '../entities/tool_call_info.dart';

/// Builds the result handed back for a tool call the turn already executed.
///
/// Reuse always saved the *execution*; what it did not save was the *payload*.
/// A repeated call re-sent the previous body in full, and because tool results
/// accumulate inside a turn, every later request in that turn then carried both
/// copies. Session a00b77ce shows the shape: one 1.7KB skill body re-sent on
/// each of three `load_skill` repeats per turn, on a turn whose requests were
/// already ~15k prompt tokens each.
///
/// So the payload keeps its structure and loses only its bulk. Small values
/// (`job_id`, `status`, `exit_code`, `ok`) pass through untouched, which is
/// what callers that parse structured fields off a reused result -- the
/// background-process follow-up policy above all -- depend on. Long strings are
/// replaced by a pointer to the identical copy already present earlier in the
/// same turn.
final class DuplicateToolResultReusePayload {
  const DuplicateToolResultReusePayload();

  /// Longest string value echoed verbatim into a reuse payload.
  static const int inlineLimit = 400;

  String build(
    ToolResultInfo previousResult, {
    required String currentToolCallId,
  }) {
    final markers = {
      'code': 'duplicate_tool_call_result_reused',
      'execution_reused': true,
      'prior_tool_call_id': previousResult.id,
      'current_tool_call_id': currentToolCallId,
    };
    final decoded = _tryDecodeMap(previousResult.result);
    if (decoded != null) {
      return jsonEncode({
        for (final entry in decoded.entries)
          entry.key: _compact(
            entry.value,
            key: entry.key,
            priorToolCallId: previousResult.id,
          ),
        ...markers,
      });
    }
    return jsonEncode({
      'ok': true,
      ...markers,
      'prior_result': _compact(
        previousResult.result,
        key: 'prior_result',
        priorToolCallId: previousResult.id,
      ),
    });
  }

  Object? _compact(
    Object? value, {
    required String key,
    required String priorToolCallId,
  }) {
    if (value is! String || value.length <= inlineLimit) return value;
    return 'Identical to "$key" in the result of tool call $priorToolCallId '
        'earlier in this turn (${value.length} characters, omitted here '
        'rather than repeated).';
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
