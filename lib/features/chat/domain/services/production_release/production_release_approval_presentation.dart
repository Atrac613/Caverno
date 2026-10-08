import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Compact machine binding for the exact pending execution.
String productionReleaseApprovalOptionLabel({
  required String executionIdentity,
  required String approvalToken,
}) {
  // ask_user_question clips labels at 120 characters.
  final fingerprint = sha256
      .convert(utf8.encode(executionIdentity))
      .toString()
      .substring(0, 32);
  return 'Approve exact production release [id:$fingerprint] '
      '[$approvalToken]';
}

/// Harness-authored text that makes the authorized execution human-readable.
String productionReleaseApprovalQuestion({
  required String toolName,
  required String command,
  required String? workingDirectory,
  required bool background,
}) {
  final directory = workingDirectory?.trim();
  return 'Caverno blocked this production release. Approve exactly the '
      'execution below?\n\n'
      'Tool: ${jsonEncode(toolName.trim())}\n'
      'Command: ${jsonEncode(command)}\n'
      'Working directory: '
      '${jsonEncode(directory == null || directory.isEmpty ? '(tool default)' : directory)}\n'
      'Background: $background';
}

String productionReleaseApprovalRequiredActionFor(
  String approvalToken, {
  String? expectedOptionLabel,
}) {
  final exactLabel = expectedOptionLabel?.trim();
  if (exactLabel != null && exactLabel.isNotEmpty) {
    return 'Call ask_user_question with exactly one option whose label is '
        'exactly "$exactLabel". Do not alter the command identity or token in '
        'that label. Retry the release only after the user selects that exact '
        'option. A plain-text reply is not recorded as release approval, and '
        'neither is a free-text answer.';
  }
  return 'Call ask_user_question with exactly one option whose label contains '
      'the approval token $approvalToken, and no other option carrying that '
      'token. Retry the release only after the user selects that option. A '
      'plain-text reply is not recorded as release approval, and neither is a '
      'free-text answer -- the user has to select the token-bearing option.';
}

const int productionReleaseApprovalTokenLength = 16;
