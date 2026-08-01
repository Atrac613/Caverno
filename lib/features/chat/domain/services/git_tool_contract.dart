import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'git_process_execution_coordinator.dart';
import 'immutable_json_snapshot.dart';

String _requiredGitValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}

Map<String, dynamic> freezeGitToolMap(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value);
}

String gitToolArgumentDigest(Map<String, dynamic> arguments) {
  final canonical = _canonicalGitValue(
    ImmutableJsonSnapshot.freezeMap(arguments),
  );
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

Object? _canonicalGitValue(Object? value) {
  if (value is Map) {
    final entries = value.entries
        .map(
          (entry) => [
            _canonicalGitValue(entry.key),
            _canonicalGitValue(entry.value),
          ],
        )
        .toList();
    entries.sort((left, right) {
      return jsonEncode(left.first).compareTo(jsonEncode(right.first));
    });
    return {'type': 'map', 'entries': entries};
  }
  if (value is List) {
    return {'type': 'list', 'values': value.map(_canonicalGitValue).toList()};
  }
  return {'type': value.runtimeType.toString(), 'value': value};
}

/// Immutable tool call and owner-scoped path facts captured before dispatch.
final class GitToolCallInput {
  GitToolCallInput({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String? ownerRepositoryPath,
    required String? ownerWorktreePath,
  }) : toolCallId = _requiredGitValue(toolCallId, 'toolCallId'),
       toolName = _requiredGitValue(toolName, 'toolName'),
       arguments = freezeGitToolMap(arguments),
       ownerRepositoryPath = _normalizedPath(ownerRepositoryPath),
       ownerWorktreePath = _normalizedPath(ownerWorktreePath);

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? ownerRepositoryPath;
  final String? ownerWorktreePath;
}

/// One normalized Git command ready for execution.
final class GitCommandExecutionRequest {
  GitCommandExecutionRequest({
    required this.source,
    required Map<String, dynamic> arguments,
    required this.command,
    required this.workingDirectory,
  }) : arguments = freezeGitToolMap(arguments);

  final GitToolCallInput source;
  final Map<String, dynamic> arguments;
  final String command;
  final String workingDirectory;
  String? get reason => source.arguments['reason'] as String?;
}

/// One normalized worktree-session completion request.
final class GitWorktreeSessionRequest {
  GitWorktreeSessionRequest({
    required this.source,
    required Map<String, dynamic> arguments,
    required this.worktreePath,
    required this.baseBranch,
    required this.removeWorktree,
    required this.mergeMessage,
  }) : arguments = freezeGitToolMap(arguments);

  final GitToolCallInput source;
  final Map<String, dynamic> arguments;
  final String worktreePath;
  final String baseBranch;
  final bool removeWorktree;
  final String? mergeMessage;
  String? get reason => source.arguments['reason'] as String?;

  String get commandSummary => removeWorktree
      ? 'finish worktree session: merge into $baseBranch and remove $worktreePath'
      : 'finish worktree session: merge into $baseBranch';
}

/// Immutable facts used by cache, policy, and manual approval adapters.
final class GitApprovalRequest {
  GitApprovalRequest({
    required this.source,
    required this.actionKind,
    required Map<String, dynamic> arguments,
    required this.commandSummary,
    required this.workingDirectory,
    required this.manualDenialMessage,
  }) : arguments = freezeGitToolMap(arguments);

  final GitToolCallInput source;
  final String actionKind;
  final Map<String, dynamic> arguments;
  final String commandSummary;
  final String workingDirectory;
  final String manualDenialMessage;
  String get toolCallId => source.toolCallId;
  String get toolName => source.toolName;
  String? get reason => source.arguments['reason'] as String?;
}

/// Starts one exact reserved process at the raw launch handoff.
final class GitProcessStartAuthorization {
  GitProcessStartAuthorization({
    required this.identity,
    required GitProcessStartDisposition Function() start,
  }) : _start = start;

  final GitProcessExecutionIdentity identity;
  final GitProcessStartDisposition Function() _start;
  GitProcessStartDisposition? _disposition;

  GitProcessStartDisposition? get disposition => _disposition;
  bool get started => _disposition == GitProcessStartDisposition.started;

  bool beginProcessHandoff() {
    if (_disposition != null) {
      throw StateError('Git process handoff was attempted more than once.');
    }
    _disposition = _start();
    return started;
  }
}

/// Exact repository state confirmation collected after an uncertain effect.
final class GitProcessReconciliationConfirmation {
  GitProcessReconciliationConfirmation({
    required this.identity,
    required Map<String, dynamic> details,
  }) : details = freezeGitToolMap(details);

  final GitProcessExecutionIdentity identity;
  final Map<String, dynamic> details;
}

/// Exact raw-process completion and adapter-classified effect.
final class GitRawProcessCompletion {
  GitRawProcessCompletion({
    required this.identity,
    required this.result,
    required this.effectKind,
    Map<String, dynamic> effectDetails = const {},
    this.reconciliation,
  }) : effectDetails = freezeGitToolMap(effectDetails);

  final GitProcessExecutionIdentity identity;
  final McpToolResult result;
  final GitProcessEffectKind effectKind;
  final Map<String, dynamic> effectDetails;
  final GitProcessReconciliationConfirmation? reconciliation;
}

/// A raw process launch failure that guarantees no process was created.
final class GitProcessLaunchFailure implements Exception {
  const GitProcessLaunchFailure({required this.identity, required this.result});

  final GitProcessExecutionIdentity identity;
  final McpToolResult result;
}

/// Owner-bound Git command execution boundary.
abstract interface class GitExecutionPort {
  Future<GitRawProcessCompletion> execute(
    GitCommandExecutionRequest request,
    GitProcessStartAuthorization authorization,
  );
}

/// Owner-bound worktree-session completion boundary.
abstract interface class GitWorktreeSessionPort {
  Future<GitRawProcessCompletion> finish(
    GitWorktreeSessionRequest request,
    GitProcessStartAuthorization authorization,
  );
}

/// Owner-scoped approval cache, policy, UI, and expiration boundary.
abstract interface class GitApprovalPort {
  McpToolResult? lookupDenial(ChatTurnOwner owner, GitApprovalRequest request);

  Future<ToolApprovalGateDecision> resolveGate(
    ChatTurnOwner owner,
    GitApprovalRequest request,
  );

  Future<bool> requestManualApproval(
    ChatTurnOwner owner,
    GitApprovalRequest request,
  );

  McpToolResult rememberDenial(
    ChatTurnOwner owner,
    GitApprovalRequest request,
    McpToolResult result,
  );

  McpToolResult rememberResult(
    ChatTurnOwner owner,
    GitApprovalRequest request,
    McpToolResult result,
  );

  McpToolResult? expiredResult(ChatTurnOwner owner, GitApprovalRequest request);
}

/// Frozen goal and evidence snapshot for one exact turn owner.
final class GitLifecycleInput {
  GitLifecycleInput({
    required this.owner,
    required this.goalIsActive,
    required String? goalObjective,
    required List<ToolResultInfo> toolResults,
  }) : goalObjective = goalObjective?.trim(),
       toolResults = List<ToolResultInfo>.unmodifiable(
         toolResults.map(
           (result) => ToolResultInfo(
             id: result.id,
             name: result.name,
             arguments: freezeGitToolMap(result.arguments),
             result: result.result,
           ),
         ),
       );

  final ChatTurnOwner owner;
  final bool goalIsActive;
  final String? goalObjective;
  final List<ToolResultInfo> toolResults;
}

String? _normalizedPath(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
