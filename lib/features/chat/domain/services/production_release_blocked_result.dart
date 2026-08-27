import 'dart:convert';

import '../entities/mcp_tool_entity.dart';

/// Instruction handed back with a blocked release.
///
/// It names a token because the harness must not decide approval by reading
/// words. A token the harness issued and can compare by equality is
/// language-independent, and the model stays free to write the human half of
/// the label in whatever language the user speaks.
String productionReleaseApprovalRequiredActionFor(String approvalToken) =>
    'Call ask_user_question with exactly one option whose label contains the '
    'approval token $approvalToken, and no other option carrying that token. '
    'Write the rest of that label, and the question, in the language the user '
    'is speaking. Retry the release only after the user selects that option. '
    'A plain-text reply is not recorded as release approval, and neither is a '
    'free-text answer -- the user has to select the token-bearing option.';

/// Length of an issued approval token, in hex characters.
const int productionReleaseApprovalTokenLength = 16;

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
}) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': 'production_release_explicit_approval_required',
      'error':
          'A production release command was blocked because the latest user '
          'message or ask_user_question answer did not explicitly approve '
          'production release execution.',
      'command': command,
      if (assistantIntent.trim().isNotEmpty)
        'assistant_intent': _clipForDiagnostic(assistantIntent.trim()),
      'required_action': productionReleaseApprovalRequiredActionFor(
        approvalToken,
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
