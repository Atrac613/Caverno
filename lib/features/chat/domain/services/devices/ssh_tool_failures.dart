part of 'ssh_tool_handler.dart';

/// How the SSH handler names its failures to the model.
///
/// These are the words the model actually plans against — an SSH turn that
/// aborts usually aborts because it could not tell from the message what to
/// do differently — so they are kept together rather than scattered through
/// the flow they interrupt.

const _identityChanged = 'SSH operation identity changed before completion';

const _effectsUncertain =
    'The SSH operation may have completed after its owner expired or its '
    'identity changed; inspect possible side effects before retrying';

McpToolResult _noActiveSession(String toolName) {
  return _failure(toolName, 'No active SSH session — call ssh_connect first');
}

McpToolResult _connectedPersistenceFailure(String toolName, String detail) {
  return _failure(
    toolName,
    'The SSH connection succeeded, but credential persistence failed '
    '($detail); the session may still be active. Inspect possible side '
    'effects before retrying',
  );
}

/// Reports a dialog edit that moved the approved destination.
///
/// Names the destination the user chose. The earlier wording said only that
/// the target had changed, which left the model nothing to change: it
/// resubmitted the identical call and the turn aborted on the repeat.
McpToolResult _targetChangedFailure(String toolName, SshCredentialKey edited) {
  return _failure(
    toolName,
    'SSH target changed after approval to '
    '${edited.username}@${edited.host}:${edited.port}; submit a new '
    'ssh_connect call with exactly those values to approve them',
  );
}

McpToolResult _identityFailure(String toolName) =>
    _failure(toolName, _identityChanged);

McpToolResult _effectsFailure(String toolName) =>
    _failure(toolName, _effectsUncertain);

McpToolResult _failure(String toolName, String message) {
  return McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}

McpToolResult _autoReviewDeniedResult(String toolName, String rationale) {
  return McpToolResult(
    toolName: toolName,
    result: 'Auto-review denied this action. Rationale: $rationale',
    isSuccess: false,
    errorMessage: 'Auto-review denied: $rationale',
  );
}
