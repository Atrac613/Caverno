import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

// ChatNotifier decomposition collaborator: goal-validation-probe-guard

/// Blocks non-verification actions during a validation-only continuation.
final class GoalValidationProbeGuard {
  const GoalValidationProbeGuard();

  static const blockedCode = 'goal_validation_probe_requires_verifier';
  static const _capabilityClassifier = ToolCapabilityClassifier();

  McpToolResult? evaluate(
    ToolCallInfo toolCall, {
    required bool verifierOnlyContinuation,
  }) {
    if (!verifierOnlyContinuation) {
      return null;
    }
    final effect = _capabilityClassifier
        .classify(toolCall.name, arguments: toolCall.arguments)
        .commandEffect;
    if (effect == ToolCommandEffect.verification) {
      return null;
    }
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': blockedCode,
        'error':
            'A validation-only continuation rejected a non-verification tool call.',
        'attempted_effect': effect.name,
        'required_action':
            'Run one project verification command now. If it fails, report the concrete failure and end this turn so the next continuation can repair it.',
      }),
      isSuccess: true,
    );
  }

  bool matches(McpToolResult result) {
    try {
      final decoded = jsonDecode(result.result);
      return decoded is Map<String, dynamic> && decoded['code'] == blockedCode;
    } on FormatException {
      return false;
    }
  }
}
