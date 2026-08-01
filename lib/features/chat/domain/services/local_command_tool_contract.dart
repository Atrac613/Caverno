import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'immutable_json_snapshot.dart';

const Duration localCommandDefaultTimeout = Duration(seconds: 60);

enum CommandPermissionRuleDecision { ask, allow, deny }

enum RememberedCommandPermissionAction { allow, deny }

enum RememberedCommandPermissionMatch { exact, prefix }

enum LocalCommandCompletionDisposition { completed, ownerExpired }

enum LocalCommandEffectDisposition {
  noEffect,
  settlementRequired,
  effectUncertain,
}

/// Exact owner, call, tool, and immutable argument identity for one execution.
final class LocalCommandOperationIdentity {
  LocalCommandOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _requiredLocalCommandValue(toolCallId, 'toolCallId'),
       toolName = _requiredLocalCommandValue(toolName, 'toolName'),
       argumentDigest = _requiredLocalCommandValue(
         argumentDigest,
         'argumentDigest',
       );

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;

  bool belongsTo(LocalCommandOperationIdentity expected) => this == expected;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalCommandOperationIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.argumentDigest == argumentDigest;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

/// Exact one-use settlement capability retained through final cache writes.
final class LocalCommandEffectSettlement {
  LocalCommandEffectSettlement({
    required this.identity,
    required bool Function() settle,
  }) : _settle = settle;

  final LocalCommandOperationIdentity identity;
  final bool Function() _settle;

  bool settle() => _settle();
}

final class LocalCommandCompletion<T> {
  const LocalCommandCompletion.completed({
    required this.owner,
    required this.toolCallId,
    required this.value,
    this.effectDisposition = LocalCommandEffectDisposition.noEffect,
    this.effectSettlement,
  }) : disposition = LocalCommandCompletionDisposition.completed;

  const LocalCommandCompletion.ownerExpired({
    required this.owner,
    required this.toolCallId,
  }) : disposition = LocalCommandCompletionDisposition.ownerExpired,
       value = null,
       effectDisposition = LocalCommandEffectDisposition.noEffect,
       effectSettlement = null;

  final ChatTurnOwner owner;
  final String toolCallId;
  final LocalCommandCompletionDisposition disposition;
  final T? value;
  final LocalCommandEffectDisposition effectDisposition;
  final LocalCommandEffectSettlement? effectSettlement;

  bool belongsTo(ChatTurnOwner expectedOwner, String expectedToolCallId) {
    return owner == expectedOwner && toolCallId == expectedToolCallId;
  }
}

final class CommandPermissionRuleRequest {
  const CommandPermissionRuleRequest({
    required this.command,
    required this.workingDirectory,
  });

  final String command;
  final String workingDirectory;
}

final class RememberedCommandPermissionRule {
  const RememberedCommandPermissionRule({
    required this.action,
    required this.match,
    required this.command,
    required this.workingDirectory,
  });

  final RememberedCommandPermissionAction action;
  final RememberedCommandPermissionMatch match;
  final String command;
  final String workingDirectory;
}

abstract interface class CommandPermissionRuleStorePort {
  CommandPermissionRuleDecision evaluate(
    ChatTurnOwner owner,
    CommandPermissionRuleRequest request,
  );

  /// ownerExpired guarantees the rule was not committed or was compensated.
  Future<LocalCommandCompletion<Object?>> remember(
    ChatTurnOwner owner,
    String toolCallId,
    RememberedCommandPermissionRule rule,
  );
}

final class LocalCommandExecutionRequest {
  LocalCommandExecutionRequest({
    required this.toolCallId,
    required this.toolName,
    required this.command,
    required this.workingDirectory,
    required Map<String, dynamic> arguments,
    this.timeout = localCommandDefaultTimeout,
  }) : arguments = freezeLocalCommandArguments(arguments),
       argumentDigest = localCommandExecutionArgumentDigest(
         command: command,
         workingDirectory: workingDirectory,
         arguments: arguments,
         timeout: timeout,
       ) {
    _requiredLocalCommandValue(toolCallId, 'toolCallId');
    _requiredLocalCommandValue(toolName, 'toolName');
    _requiredLocalCommandValue(command, 'command');
    _requiredLocalCommandValue(workingDirectory, 'workingDirectory');
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'timeout must be positive.',
      );
    }
  }

  final String toolCallId;
  final String toolName;
  final String command;
  final String workingDirectory;
  final Map<String, dynamic> arguments;
  final String argumentDigest;
  final Duration timeout;

  LocalCommandOperationIdentity identityFor(ChatTurnOwner owner) {
    return LocalCommandOperationIdentity(
      owner: owner,
      toolCallId: toolCallId,
      toolName: toolName,
      argumentDigest: argumentDigest,
    );
  }
}

abstract interface class LocalCommandExecutionPort {
  Future<LocalCommandCompletion<McpToolResult>> execute(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest request,
  );
}

final class LocalCommandApprovalRequest {
  const LocalCommandApprovalRequest({
    required this.toolCallId,
    required this.execution,
    required this.reason,
    required this.warningTitle,
    required this.warningMessage,
  });

  final String toolCallId;
  final LocalCommandExecutionRequest execution;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;
}

final class LocalCommandManualApproval {
  const LocalCommandManualApproval({
    required this.approved,
    this.rememberedAction,
    this.rememberedMatch,
  });

  final bool approved;
  final RememberedCommandPermissionAction? rememberedAction;
  final RememberedCommandPermissionMatch? rememberedMatch;

  bool get shouldRemember =>
      rememberedAction != null && rememberedMatch != null;
}

abstract interface class LocalCommandApprovalPort {
  LocalCommandCompletion<McpToolResult>? lookupDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  );

  Future<LocalCommandCompletion<ToolApprovalGateDecision>> resolveGate(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  );

  Future<LocalCommandCompletion<LocalCommandManualApproval>>
  requestManualApproval(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    ToolApprovalGateDecision gate,
  );

  bool isExpired(ChatTurnOwner owner, String toolCallId);

  LocalCommandCompletion<Object?> rememberDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  );

  LocalCommandCompletion<Object?> rememberResult(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  );
}

final class LocalCommandToolRequest {
  LocalCommandToolRequest({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required this.allowedWorkingDirectoryRoot,
    required Map<String, dynamic> arguments,
    this.defaultWorkingDirectory,
    this.isRemoteInteraction = false,
  }) : arguments = freezeLocalCommandArguments(arguments);

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String allowedWorkingDirectoryRoot;
  final String? defaultWorkingDirectory;
  final Map<String, dynamic> arguments;
  final bool isRemoteInteraction;
}

Map<String, dynamic> freezeLocalCommandArguments(Map<String, dynamic> source) {
  return ImmutableJsonSnapshot.freezeMap(source);
}

String localCommandArgumentDigest(Map<String, dynamic> source) {
  final frozen = freezeLocalCommandArguments(source);
  final canonical = _canonicalLocalCommandJson(frozen);
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

String localCommandExecutionArgumentDigest({
  required String command,
  required String workingDirectory,
  required Map<String, dynamic> arguments,
  required Duration timeout,
}) {
  return localCommandArgumentDigest({
    'command': command,
    'working_directory': workingDirectory,
    'timeout_microseconds': timeout.inMicroseconds,
    'arguments': arguments,
  });
}

Object? _canonicalLocalCommandJson(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList(growable: false)..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalLocalCommandJson(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalLocalCommandJson).toList(growable: false);
  }
  return value;
}

String _requiredLocalCommandValue(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return value;
}
