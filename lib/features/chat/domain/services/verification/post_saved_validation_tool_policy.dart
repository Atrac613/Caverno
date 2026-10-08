import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../entities/tool_call_info.dart';

/// Keeps evidence checks and the parent's acceptance available after validation.
class PostSavedValidationToolPolicy {
  const PostSavedValidationToolPolicy();

  List<Map<String, dynamic>> followUpDefinitions(
    List<Map<String, dynamic>> definitions, {
    required bool isParentTurn,
  }) {
    if (!isParentTurn) return const [];
    return definitions
        .where((definition) {
          final function = definition['function'];
          return function is Map && function['name'] == 'accept_task';
        })
        .toList(growable: false);
  }

  bool allows(
    ToolCallInfo toolCall, {
    required bool isParentTurn,
    List<ToolResultInfo> latestResults = const [],
  }) {
    if (toolCall.name == 'accept_task' && isParentTurn) return true;
    if (toolCall.name == 'spawn_subagent' &&
        isParentTurn &&
        latestResults.any(_acceptanceRequiresDelegation)) {
      return true;
    }
    final effect = const ToolCapabilityClassifier()
        .classify(toolCall.name, arguments: toolCall.arguments)
        .commandEffect;
    return effect == ToolCommandEffect.inspection ||
        effect == ToolCommandEffect.verification;
  }

  bool _acceptanceRequiresDelegation(ToolResultInfo result) {
    if (result.name != 'accept_task') return false;
    try {
      final payload = jsonDecode(result.result);
      return payload is Map &&
          payload['code'] == 'acceptance_no_delegated_result';
    } on FormatException {
      return false;
    }
  }
}
