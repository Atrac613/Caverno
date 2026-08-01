import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/immutable_json_snapshot.dart';
import '../../domain/services/project_scoped_read_tool_contract.dart';

const Set<String> projectScopedLocalReadToolNames = {
  'list_directory',
  'read_file',
  'inspect_file',
  'find_files',
  'search_files',
};

typedef ProjectScopedReadRootCallback =
    ProjectScopedReadRootAcknowledgement Function(
      ProjectScopedReadInvocationIdentity identity,
    );
typedef ProjectScopedReadLifecycleCallback =
    ProjectScopedReadLifecycleAcknowledgement Function(
      ProjectScopedReadRuntimeIdentity identity,
    );
typedef ProjectScopedReadExecutionCallback =
    Future<ProjectScopedReadExecutionAcknowledgement> Function(
      ProjectScopedReadExecutionRequest request,
    );

final class ProjectScopedReadInvocationIdentity {
  ProjectScopedReadInvocationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _required(toolCallId, 'toolCallId'),
       toolName = requireCanonicalProjectScopedReadToolName(toolName),
       argumentDigest = _required(argumentDigest, 'argumentDigest');

  final ChatTurnOwner owner;
  final String toolCallId, toolName, argumentDigest;

  @override
  bool operator ==(Object other) =>
      other is ProjectScopedReadInvocationIdentity &&
      other.owner == owner &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      other.argumentDigest == argumentDigest;

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

final class ProjectScopedReadRootIdentity {
  ProjectScopedReadRootIdentity(String? projectRoot)
    : projectRoot = _normalizeRoot(projectRoot),
      digest = _digest(<String, Object?>{
        'projectRoot': _normalizeRoot(projectRoot),
      });

  final String? projectRoot;
  final String digest;

  @override
  bool operator ==(Object other) =>
      other is ProjectScopedReadRootIdentity &&
      other.projectRoot == projectRoot &&
      other.digest == digest;

  @override
  int get hashCode => Object.hash(projectRoot, digest);
}

enum ProjectScopedReadRootDisposition { resolved, rejected, effectUncertain }

final class ProjectScopedReadRootAcknowledgement {
  ProjectScopedReadRootAcknowledgement({
    required this.identity,
    required String? projectRoot,
    required this.disposition,
  }) : rootIdentity = ProjectScopedReadRootIdentity(projectRoot);

  final ProjectScopedReadInvocationIdentity identity;
  final ProjectScopedReadRootIdentity rootIdentity;
  final ProjectScopedReadRootDisposition disposition;
}

final class ProjectScopedReadRuntimeInput {
  factory ProjectScopedReadRuntimeInput({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) {
    final arguments = _freezeStrict(toolCall.arguments);
    return ProjectScopedReadRuntimeInput._(
      identity: ProjectScopedReadInvocationIdentity(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        argumentDigest: _digest(arguments),
      ),
      arguments: arguments,
    );
  }

  const ProjectScopedReadRuntimeInput._({
    required this.identity,
    required this.arguments,
  });

  final ProjectScopedReadInvocationIdentity identity;
  final Map<String, dynamic> arguments;

  ProjectScopedReadToolRequest toToolRequest(String? projectRoot) =>
      ProjectScopedReadToolRequest(
        owner: identity.owner,
        toolCallId: identity.toolCallId,
        toolName: identity.toolName,
        ownerProjectRoot: projectRoot,
        arguments: arguments,
      );
}

final class ProjectScopedReadRuntimeIdentity {
  const ProjectScopedReadRuntimeIdentity({
    required this.invocation,
    required this.root,
    required this.toolRequestIdentity,
  });

  final ProjectScopedReadInvocationIdentity invocation;
  final ProjectScopedReadRootIdentity root;
  final ProjectScopedReadOperationIdentity toolRequestIdentity;

  ChatTurnOwner get owner => invocation.owner;
  String get toolName => invocation.toolName;

  @override
  bool operator ==(Object other) =>
      other is ProjectScopedReadRuntimeIdentity &&
      other.invocation == invocation &&
      other.root == root &&
      other.toolRequestIdentity == toolRequestIdentity;

  @override
  int get hashCode => Object.hash(invocation, root, toolRequestIdentity);
}

enum ProjectScopedReadLifecycleDisposition {
  current,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class ProjectScopedReadLifecycleAcknowledgement {
  const ProjectScopedReadLifecycleAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final ProjectScopedReadRuntimeIdentity identity;
  final ProjectScopedReadLifecycleDisposition disposition;
}

final class ProjectScopedReadExecutionIdentity {
  ProjectScopedReadExecutionIdentity({
    required this.runtime,
    required String resolvedArgumentDigest,
  }) : resolvedArgumentDigest = _required(
         resolvedArgumentDigest,
         'resolvedArgumentDigest',
       );

  final ProjectScopedReadRuntimeIdentity runtime;
  final String resolvedArgumentDigest;

  @override
  bool operator ==(Object other) =>
      other is ProjectScopedReadExecutionIdentity &&
      other.runtime == runtime &&
      other.resolvedArgumentDigest == resolvedArgumentDigest;

  @override
  int get hashCode => Object.hash(runtime, resolvedArgumentDigest);
}

final class ProjectScopedReadExecutionRequest {
  ProjectScopedReadExecutionRequest({
    required this.identity,
    required Map<String, dynamic> arguments,
  }) : arguments = _freezeStrict(arguments);

  final ProjectScopedReadExecutionIdentity identity;
  final Map<String, dynamic> arguments;

  String get toolName => identity.runtime.toolName;
}

enum ProjectScopedReadExecutionDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class ProjectScopedReadExecutionAcknowledgement {
  const ProjectScopedReadExecutionAcknowledgement({
    required this.identity,
    required this.disposition,
    this.result,
    this.message,
  });

  final ProjectScopedReadExecutionIdentity identity;
  final ProjectScopedReadExecutionDisposition disposition;
  final McpToolResult? result;
  final String? message;
}

enum ProjectScopedReadRuntimeDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
  boundaryMismatch,
}

final class ProjectScopedReadRuntimeCompletion {
  const ProjectScopedReadRuntimeCompletion({
    required this.identity,
    required this.disposition,
    required this.result,
  });

  final ProjectScopedReadRuntimeIdentity identity;
  final ProjectScopedReadRuntimeDisposition disposition;
  final McpToolResult result;
}

Map<String, dynamic> freezeStrictProjectScopedReadArguments(
  Map<String, dynamic> arguments,
) => _freezeStrict(arguments);

String projectScopedReadArgumentDigest(Map<String, dynamic> arguments) =>
    _digest(_freezeStrict(arguments));

Map<String, dynamic> _freezeStrict(Map<String, dynamic> arguments) {
  final frozen = ImmutableJsonSnapshot.freezeMap(arguments);
  _canonicalJson(frozen);
  return frozen;
}

String _digest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonicalJson(value)))).toString();

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalJson).toList(growable: false);
  if (value is double && !value.isFinite) {
    throw ArgumentError.value(value, 'arguments', 'Numbers must be finite.');
  }
  return value;
}

String? _normalizeRoot(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _required(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}
