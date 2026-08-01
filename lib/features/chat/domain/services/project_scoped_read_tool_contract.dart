import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'immutable_json_snapshot.dart';

Map<String, dynamic> freezeProjectScopedReadArguments(
  Map<String, dynamic> value,
) => ImmutableJsonSnapshot.freezeMap(value);

final class ProjectScopedReadOperationIdentity {
  ProjectScopedReadOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String requestDigest,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = requireCanonicalProjectScopedReadToolName(toolName),
       requestDigest = _requiredValue(requestDigest, 'requestDigest');

  final ChatTurnOwner owner;
  final String toolCallId, toolName, requestDigest;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProjectScopedReadOperationIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.requestDigest == requestDigest;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, requestDigest);
}

final class ProjectScopedReadToolRequest {
  factory ProjectScopedReadToolRequest({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required String? ownerProjectRoot,
    required Map<String, dynamic> arguments,
  }) {
    final frozen = freezeProjectScopedReadArguments(arguments);
    final canonicalName = requireCanonicalProjectScopedReadToolName(toolName);
    return ProjectScopedReadToolRequest._(
      identity: ProjectScopedReadOperationIdentity(
        owner: owner,
        toolCallId: toolCallId,
        toolName: canonicalName,
        requestDigest: _requestDigest(frozen, ownerProjectRoot),
      ),
      ownerProjectRoot: ownerProjectRoot,
      arguments: frozen,
    );
  }

  const ProjectScopedReadToolRequest._({
    required this.identity,
    required this.ownerProjectRoot,
    required this.arguments,
  });

  final ProjectScopedReadOperationIdentity identity;
  final String? ownerProjectRoot;
  final Map<String, dynamic> arguments;

  ChatTurnOwner get owner => identity.owner;
  String get toolCallId => identity.toolCallId;
  String get toolName => identity.toolName;
}

final class ProjectScopedReadCompletion {
  const ProjectScopedReadCompletion({
    required this.identity,
    required this.result,
  });

  final ProjectScopedReadOperationIdentity identity;
  final McpToolResult result;
}

String _requestDigest(Map<String, dynamic> arguments, String? projectRoot) =>
    sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'arguments': arguments,
              'ownerProjectRoot': projectRoot,
            }),
          ),
        )
        .toString();

abstract interface class ProjectScopedReadLifecyclePort {
  bool isCurrent(ProjectScopedReadOperationIdentity identity);
}

abstract interface class McpToolExecutionPort {
  Future<ProjectScopedReadCompletion> execute(
    ProjectScopedReadOperationIdentity identity,
    Map<String, dynamic> resolvedArguments,
  );
}

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}

String requireCanonicalProjectScopedReadToolName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized != value ||
      normalized != normalized.toLowerCase() ||
      !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'toolName',
      'A canonical project-scoped read tool name is required.',
    );
  }
  return normalized;
}
