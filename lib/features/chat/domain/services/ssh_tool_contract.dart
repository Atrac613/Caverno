import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/ssh_auth_credential.dart';
import 'immutable_json_snapshot.dart';

/// Re-exported because every port below speaks in credentials: an adapter can
/// implement this contract without separately importing the entity.
export '../entities/ssh_auth_credential.dart';

String _requiredIdentity(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}

Map<String, dynamic> _freezeArguments(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value);
}

enum SshToolKind {
  connect('ssh_connect'),
  executeCommand('ssh_execute_command'),
  disconnect('ssh_disconnect');

  const SshToolKind(this.toolName);

  final String toolName;
}

/// Opaque identity assigned to one connection attempt before dispatch.
final class SshConnectionIdentity {
  SshConnectionIdentity(String value)
    : value = _requiredIdentity(value, 'connectionIdentity');

  final String value;
}

/// Credential lookup key and approved SSH destination.
final class SshCredentialKey {
  const SshCredentialKey({
    required this.host,
    required this.port,
    required this.username,
  });

  final String host;
  final int port;
  final String username;

  bool hasSameTarget(SshCredentialKey other) {
    return host == other.host &&
        port == other.port &&
        username == other.username;
  }

  /// Whether [other] is this target with an omitted username filled in.
  ///
  /// `ssh_connect` declares username optional and documents that the dialog
  /// will ask for it, so a target approved with an empty username is partial,
  /// not final. Treating the dialog's answer as an edit is what rejected every
  /// call that let the user supply the username. Host and port must still
  /// match exactly, and a username that was already set may not change: those
  /// pick the destination, and the destination is what approval was for.
  bool isCompletedBy(SshCredentialKey other) {
    return host == other.host &&
        port == other.port &&
        (username == other.username ||
            (username.isEmpty && other.username.isNotEmpty));
  }
}

/// Immutable tool input captured for one exact owner and tool call.
final class SshToolRequest {
  SshToolRequest._({
    required this.owner,
    required String toolCallId,
    required this.kind,
    required Map<String, dynamic> arguments,
    this.connectionIdentity,
  }) : toolCallId = _requiredIdentity(toolCallId, 'toolCallId'),
       arguments = _freezeArguments(arguments);

  factory SshToolRequest.connect({
    required ChatTurnOwner owner,
    required String toolCallId,
    required SshConnectionIdentity connectionIdentity,
    required Map<String, dynamic> arguments,
  }) {
    return SshToolRequest._(
      owner: owner,
      toolCallId: toolCallId,
      kind: SshToolKind.connect,
      arguments: arguments,
      connectionIdentity: connectionIdentity,
    );
  }

  factory SshToolRequest.executeCommand({
    required ChatTurnOwner owner,
    required String toolCallId,
    required Map<String, dynamic> arguments,
  }) {
    return SshToolRequest._(
      owner: owner,
      toolCallId: toolCallId,
      kind: SshToolKind.executeCommand,
      arguments: arguments,
    );
  }

  factory SshToolRequest.disconnect({
    required ChatTurnOwner owner,
    required String toolCallId,
    Map<String, dynamic> arguments = const {},
  }) {
    return SshToolRequest._(
      owner: owner,
      toolCallId: toolCallId,
      kind: SshToolKind.disconnect,
      arguments: arguments,
    );
  }

  final ChatTurnOwner owner;
  final String toolCallId;
  final SshToolKind kind;
  final Map<String, dynamic> arguments;
  final SshConnectionIdentity? connectionIdentity;

  String get toolName => kind.toolName;
  String? get reason => arguments['reason'] as String?;

  bool hasSameCall(SshToolRequest other) {
    return owner == other.owner &&
        toolCallId == other.toolCallId &&
        kind == other.kind;
  }
}

/// Active connection facts returned by an exact-call lookup.
final class SshOwnedConnection {
  SshOwnedConnection({
    required this.owner,
    required String connectToolCallId,
    required this.identity,
    required this.key,
  }) : connectToolCallId = _requiredIdentity(
         connectToolCallId,
         'connectToolCallId',
       );

  final ChatTurnOwner owner;
  final String connectToolCallId;
  final SshConnectionIdentity identity;
  final SshCredentialKey key;
}

/// Exact call, connection attempt, and approved target for one side effect.
final class SshOperationIdentity {
  SshOperationIdentity({
    required this.request,
    required this.connectionIdentity,
    required String sessionToolCallId,
    required this.target,
  }) : sessionToolCallId = _requiredIdentity(
         sessionToolCallId,
         'sessionToolCallId',
       );

  final SshToolRequest request;
  final SshConnectionIdentity connectionIdentity;
  final String sessionToolCallId;
  final SshCredentialKey target;

  ChatTurnOwner get owner => request.owner;
  String get toolCallId => request.toolCallId;
  String get toolName => request.toolName;

  /// This identity retargeted at [target], which must complete the approved
  /// one. Returns `this` when nothing was filled in, so the ordinary path
  /// keeps the identity object every port completion is compared against.
  SshOperationIdentity completedWith(SshCredentialKey target) {
    if (this.target.hasSameTarget(target)) return this;
    return SshOperationIdentity(
      request: request,
      connectionIdentity: connectionIdentity,
      sessionToolCallId: sessionToolCallId,
      target: target,
    );
  }

  bool hasSameIdentity(SshOperationIdentity other) {
    return request.hasSameCall(other.request) &&
        connectionIdentity.value == other.connectionIdentity.value &&
        sessionToolCallId == other.sessionToolCallId &&
        target.hasSameTarget(other.target);
  }
}

/// Exact-call completion used before an active target is known.
final class SshCallCompletion<T> {
  const SshCallCompletion({required this.request, required this.value});

  final SshToolRequest request;
  final T value;

  bool belongsTo(SshToolRequest expected) => request.hasSameCall(expected);
}

/// Exact-operation completion returned by every asynchronous adapter boundary.
final class SshOperationCompletion<T> {
  const SshOperationCompletion({required this.operation, required this.value});

  final SshOperationIdentity operation;
  final T value;

  bool belongsTo(SshOperationIdentity expected) =>
      operation.hasSameIdentity(expected);
}

/// Immutable facts shown by the credential UI adapter.
final class SshConnectCredentialRequest {
  const SshConnectCredentialRequest({
    required this.operation,
    required this.savedCredential,
  });

  final SshOperationIdentity operation;
  final SshAuthCredential? savedCredential;
  SshCredentialKey get approvedTarget => operation.target;
}

/// Authentication chosen by the user or replayed from a saved credential.
final class SshConnectCredentialSelection {
  const SshConnectCredentialSelection({
    required this.key,
    required this.credential,
    required this.remember,
  });

  final SshCredentialKey key;
  final SshAuthCredential credential;
  final bool remember;
}

enum SshCredentialSelectionResultKind {
  selected,
  cancelled,
  reapprovalRequired,
}

/// Exact credential UI completion with target-change classification.
final class SshCredentialSelectionResult {
  SshCredentialSelectionResult.fromSelection({
    required this.operation,
    required SshConnectCredentialSelection selection,
  }) : kind = operation.target.isCompletedBy(selection.key)
           ? SshCredentialSelectionResultKind.selected
           : SshCredentialSelectionResultKind.reapprovalRequired,
       selection = selection;

  const SshCredentialSelectionResult.cancelled({required this.operation})
    : kind = SshCredentialSelectionResultKind.cancelled,
      selection = null;

  final SshOperationIdentity operation;
  final SshCredentialSelectionResultKind kind;
  final SshConnectCredentialSelection? selection;

  bool belongsTo(SshOperationIdentity expected) =>
      operation.hasSameIdentity(expected);
}

/// Immutable approval cache and policy identity.
final class SshApprovalRequest {
  SshApprovalRequest({
    required this.operation,
    required Map<String, dynamic> cacheArguments,
  }) : cacheArguments = _freezeArguments(cacheArguments);

  final SshOperationIdentity operation;
  final Map<String, dynamic> cacheArguments;

  ChatTurnOwner get owner => operation.owner;
  String get toolCallId => operation.toolCallId;
  String get toolName => operation.toolName;
}

abstract interface class SshCredentialPort {
  Future<SshOperationCompletion<SshAuthCredential?>> loadSavedCredential(
    SshOperationIdentity operation,
  );

  Future<SshCredentialSelectionResult> requestCredential(
    SshConnectCredentialRequest request,
  );

  Future<SshOperationCompletion<void>> saveCredential(
    SshOperationIdentity operation,
    SshAuthCredential credential,
  );

  Future<SshOperationCompletion<void>> deleteCredential(
    SshOperationIdentity operation,
  );
}

/// Exact-call connection lookup and exact-target lifecycle boundary.
abstract interface class SshConnectionPort {
  SshCallCompletion<SshOwnedConnection?> lookupActive(SshToolRequest request);

  /// Revalidates [operation] immediately before opening the transport.
  Future<SshOperationCompletion<void>> connect(
    SshOperationIdentity operation, {
    required SshAuthCredential credential,
  });

  /// Revalidates [operation] immediately before conditionally closing it.
  Future<SshOperationCompletion<void>> disconnect(
    SshOperationIdentity operation,
  );
}

/// Executes commands and direct disconnects against one exact target.
abstract interface class SshCommandExecutionPort {
  /// Revalidates [operation] immediately before command dispatch.
  Future<SshOperationCompletion<McpToolResult>> executeCommand(
    SshOperationIdentity operation, {
    required Map<String, dynamic> arguments,
  });

  /// Revalidates [operation] immediately before disconnect dispatch.
  Future<SshOperationCompletion<McpToolResult>> disconnect(
    SshOperationIdentity operation, {
    required Map<String, dynamic> arguments,
  });
}

/// Exact-operation approval cache, policy, UI, and expiration boundary.
abstract interface class SshCommandApprovalPort {
  SshOperationCompletion<McpToolResult?> lookupDenial(
    SshApprovalRequest request,
  );

  Future<SshOperationCompletion<ToolApprovalGateDecision>> resolveGate(
    SshApprovalRequest request, {
    required bool fullAccessEligible,
  });

  Future<SshOperationCompletion<bool>> requestCommandApproval(
    SshApprovalRequest request,
  );

  SshOperationCompletion<McpToolResult> rememberDenial(
    SshApprovalRequest request,
    McpToolResult result,
  );

  SshOperationCompletion<McpToolResult> rememberResult(
    SshApprovalRequest request,
    McpToolResult result,
  );

  SshOperationCompletion<McpToolResult?> expiredResult(
    SshOperationIdentity operation,
  );
}
