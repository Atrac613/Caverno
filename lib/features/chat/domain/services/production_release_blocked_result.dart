import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import 'production_release_approval_presentation.dart';

export 'production_release_approval_presentation.dart';

/// The refusal a blocked production release reports to the model.
///
/// The policy and the coordinator both block releases -- the policy for a
/// single evaluated call, the coordinator across the turn -- and the model has
/// to read one wording either way, so the payload is built once here.
McpToolResult buildProductionReleaseBlockedResult({
  required String toolName,
  required String command,
  required String assistantIntent,
  required String approvalToken,
  String? approvalOptionLabel,
}) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': 'production_release_explicit_approval_required',
      ...ToolResultOrigin.refusal.marker,
      'error':
          'A production release command was blocked because the latest user '
          'message or ask_user_question answer did not explicitly approve '
          'production release execution.',
      'command': command,
      if (assistantIntent.trim().isNotEmpty)
        'assistant_intent': _clipForDiagnostic(assistantIntent.trim()),
      if (approvalOptionLabel != null && approvalOptionLabel.trim().isNotEmpty)
        'approval_option_label': approvalOptionLabel.trim(),
      'required_action': productionReleaseApprovalRequiredActionFor(
        approvalToken,
        expectedOptionLabel: approvalOptionLabel,
      ),
    }),
    isSuccess: true,
  );
}

String _clipForDiagnostic(String value, {int maxLength = 240}) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return '${normalized.substring(0, maxLength)}...';
}
