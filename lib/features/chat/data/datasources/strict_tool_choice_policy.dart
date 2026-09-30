import 'dart:convert';

import '../../domain/entities/tool_call_info.dart';

/// Selects the small set of control tools that are safe to force when they
/// are the only advertised function.
///
/// A strict tool is never forced from the ordinary multi-tool catalog. That
/// keeps normal model-directed tool selection unchanged while allowing a
/// purpose-built control turn to state its intent on the wire.
abstract final class StrictToolChoicePolicy {
  static const Set<String> forcedFunctionNames = {'update_goal'};

  static String? forcedFunctionName(List<Map<String, dynamic>>? tools) {
    if (tools == null || tools.length != 1) return null;
    final function = tools.single['function'];
    if (function is! Map) return null;
    final name = function['name'];
    if (name is! String || !forcedFunctionNames.contains(name)) return null;
    return name;
  }

  static Map<String, dynamic>? openAiToolChoice(
    List<Map<String, dynamic>>? tools, {
    List<ToolResultInfo>? toolResults,
  }) {
    final name = forcedFunctionName(tools);
    if (name == null) return null;
    if (toolResults != null && !isStatusRecovery(toolResults)) return null;
    return {
      'type': 'function',
      'function': {'name': name},
    };
  }

  /// Force the status elicitation only, never its acknowledgement follow-up.
  static bool isStatusRecovery(List<ToolResultInfo> results) {
    if (results.isEmpty ||
        results.last.name != 'coding_continuation_recovery') {
      return false;
    }
    try {
      final payload = jsonDecode(results.last.result);
      return payload is Map &&
          payload['code'] == 'structured_coding_task_status';
    } on FormatException {
      return false;
    }
  }
}
