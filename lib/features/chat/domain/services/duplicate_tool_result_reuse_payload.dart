import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';

/// Builds the result handed back for a tool call the turn already executed.
///
/// Reuse saved the *execution*, not the *payload*: the structure survives and
/// only bulk is dropped, so callers parsing `job_id` / `status` / `exit_code`
/// off a reused result still find them. A long string shrinks to a pointer
/// only when the copy it names travels in the same request -- pointing at the
/// prior call assumed results accumulate in a turn, `StickyToolResultPolicy`
/// says they do not, and session 64bad560 lost a whole turn reading one.
final class DuplicateToolResultReusePayload {
  DuplicateToolResultReusePayload();

  /// Longest string value echoed verbatim into a reuse payload.
  static const int inlineLimit = 400;

  final Map<String, String> _inlinedValueOwners = <String, String>{};

  String build(
    ToolResultInfo previousResult, {
    required String currentToolCallId,
  }) {
    final markers = {
      'code': 'duplicate_tool_call_result_reused',
      ...ToolResultOrigin.harness.marker,
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
            currentToolCallId: currentToolCallId,
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
        currentToolCallId: currentToolCallId,
      ),
    });
  }

  Object? _compact(
    Object? value, {
    required String key,
    required String currentToolCallId,
  }) {
    if (value is! String || value.length <= inlineLimit) return value;
    final owner = _inlinedValueOwners[value];
    if (owner == null) {
      _inlinedValueOwners[value] = currentToolCallId;
      return value;
    }
    return 'Identical to "$key" in the result of tool call $owner in this '
        'request (${value.length} characters, omitted here rather than '
        'repeated).';
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
