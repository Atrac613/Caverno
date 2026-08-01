import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/file_mutation_tool_handler.dart';
import '../../domain/services/immutable_json_snapshot.dart';

part 'file_mutation_effect_runtime_contract.dart';

typedef FileMutationLifecycleCallback =
    FileMutationRuntimeAcknowledgement<Object?> Function(
      FileMutationRuntimeIdentity identity,
    );
typedef FileMutationPreflightCallback =
    Future<FileMutationRuntimeAcknowledgement<String?>> Function(
      FileMutationRuntimeOperationRequest request,
    );
typedef FileMutationFingerprintCallback =
    Future<FileMutationRuntimeAcknowledgement<String>> Function(
      FileMutationRuntimeIdentity identity,
    );
typedef FileMutationRegularFileCallback =
    Future<FileMutationRuntimeAcknowledgement<bool>> Function(
      FileMutationRuntimeIdentity identity,
    );
typedef FileMutationDeleteSnapshotCallback =
    Future<FileMutationRuntimeAcknowledgement<FileMutationDeleteSnapshot>>
    Function(FileMutationRuntimeIdentity identity);
typedef FileMutationPreviewCallback =
    Future<FileMutationRuntimeAcknowledgement<String>> Function(
      FileMutationRuntimePreviewRequest request,
    );
typedef FileMutationDenialLookupCallback =
    FileMutationRuntimeAcknowledgement<McpToolResult?> Function(
      FileMutationRuntimeApprovalRequest request,
    );
typedef FileMutationGateCallback =
    Future<FileMutationRuntimeAcknowledgement<ToolApprovalGateDecision>>
    Function(
      FileMutationRuntimeApprovalRequest request, {
      required FileMutationPreviewLoader buildPreview,
    });
typedef FileMutationManualApprovalCallback =
    Future<FileMutationRuntimeAcknowledgement<bool>> Function(
      FileMutationRuntimeApprovalRequest request, {
      required String preview,
    });
typedef FileMutationCacheWriteCallback =
    FileMutationRuntimeAcknowledgement<Object?> Function(
      FileMutationRuntimeCacheWriteRequest request,
    );
typedef FileMutationRollbackCaptureCallback<Snapshot extends Object> =
    Future<
      FileMutationRuntimeAcknowledgement<FileMutationRollbackCapture<Snapshot>>
    >
    Function(FileMutationRuntimeIdentity identity);
typedef FileMutationRollbackRecordCallback<Snapshot extends Object> =
    Future<
      FileMutationRuntimeAcknowledgement<FileMutationRollbackRecordReceipt>
    >
    Function(FileMutationRollbackRecordRequest<Snapshot> request);
typedef FileMutationExecutionCallback<Snapshot extends Object> =
    Future<FileMutationExecutionAcknowledgement> Function(
      FileMutationEffectRequest<Snapshot> request,
      FileMutationEffectAuthorization authorization,
    );
typedef FileMutationCompensationCallback<Snapshot extends Object> =
    Future<FileMutationCompensationAcknowledgement> Function(
      FileMutationCompensationRequest<Snapshot> request,
    );

/// Exact immutable identity for one resolved filesystem mutation invocation.
final class FileMutationRuntimeIdentity {
  FileMutationRuntimeIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
    required String resolvedArgumentDigest,
    required this.projectRoot,
    required this.canonicalPath,
    required String approvalContextDigest,
  }) : toolCallId = _requiredExact(toolCallId, 'toolCallId'),
       toolName = _canonicalToolName(toolName),
       argumentDigest = _requiredExact(argumentDigest, 'argumentDigest'),
       resolvedArgumentDigest = _requiredExact(
         resolvedArgumentDigest,
         'resolvedArgumentDigest',
       ),
       approvalContextDigest = _requiredExact(
         approvalContextDigest,
         'approvalContextDigest',
       );

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;
  final String resolvedArgumentDigest;
  final String? projectRoot;
  final String canonicalPath;
  final String approvalContextDigest;

  @override
  bool operator ==(Object other) =>
      other is FileMutationRuntimeIdentity &&
      other.owner == owner &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      other.argumentDigest == argumentDigest &&
      other.resolvedArgumentDigest == resolvedArgumentDigest &&
      other.projectRoot == projectRoot &&
      other.canonicalPath == canonicalPath &&
      other.approvalContextDigest == approvalContextDigest;

  @override
  int get hashCode => Object.hash(
    owner,
    toolCallId,
    toolName,
    argumentDigest,
    resolvedArgumentDigest,
    projectRoot,
    canonicalPath,
    approvalContextDigest,
  );
}

/// Strict input snapshot captured before the first asynchronous callback.
final class FileMutationRuntimeInput {
  factory FileMutationRuntimeInput({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required ToolApprovalMode approvalMode,
    required String? projectRoot,
    required Map<String, dynamic> resolvedArguments,
    required List<Message> conversationMessages,
    required bool hasUntrustedInfluence,
  }) {
    final rawArguments = ImmutableJsonSnapshot.freezeMap(toolCall.arguments);
    final resolved = ImmutableJsonSnapshot.freezeMap(resolvedArguments);
    final root = _canonicalRoot(projectRoot);
    final path = (resolved['path'] as String?)?.trim() ?? '';
    // With a project root the resolver must already have made the path
    // absolute, and a relative one means dispatch ran before resolution.
    // Without a root there is nothing to resolve against: the handlers this
    // runtime replaced passed such a path through, and throwing here instead
    // failed every file mutation outside a coding project.
    if (path.isNotEmpty &&
        root != null &&
        !DartProjectPath.isAbsolutePath(path)) {
      throw ArgumentError.value(
        path,
        'resolvedArguments',
        'File mutation paths must be resolved before runtime dispatch.',
      );
    }
    final canonicalPath = path.isEmpty ? '' : DartProjectPath.pathKey(path);
    final messages = List<Message>.unmodifiable(conversationMessages);
    final identity = FileMutationRuntimeIdentity(
      owner: owner,
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      argumentDigest: fileMutationJsonDigest(rawArguments),
      resolvedArgumentDigest: fileMutationJsonDigest(resolved),
      projectRoot: root,
      canonicalPath: canonicalPath,
      approvalContextDigest: _approvalContextDigest(
        approvalMode,
        messages,
        hasUntrustedInfluence,
      ),
    );
    return FileMutationRuntimeInput._(
      identity: identity,
      approvalMode: approvalMode,
      rawArguments: rawArguments,
      resolvedArguments: resolved,
      conversationMessages: messages,
      hasUntrustedInfluence: hasUntrustedInfluence,
    );
  }

  const FileMutationRuntimeInput._({
    required this.identity,
    required this.approvalMode,
    required this.rawArguments,
    required this.resolvedArguments,
    required this.conversationMessages,
    required this.hasUntrustedInfluence,
  });

  final FileMutationRuntimeIdentity identity;
  final ToolApprovalMode approvalMode;
  final Map<String, dynamic> rawArguments;
  final Map<String, dynamic> resolvedArguments;
  final List<Message> conversationMessages;
  final bool hasUntrustedInfluence;

  FileMutationOperation get operation => FileMutationOperation(
    kind: _kindFor(identity.toolName),
    arguments: resolvedArguments,
    reason: rawArguments['reason'] is String
        ? rawArguments['reason'] as String
        : null,
  );

  FileMutationToolRequest toToolRequest() => FileMutationToolRequest(
    owner: identity.owner,
    toolCallId: identity.toolCallId,
    approvalMode: approvalMode,
    projectRoot: identity.projectRoot,
    operation: operation,
    toolArguments: rawArguments,
    conversationMessages: conversationMessages,
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
}

enum FileMutationRuntimeAcknowledgementDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
}

/// Exact callback receipt used at every notifier or filesystem boundary.
final class FileMutationRuntimeAcknowledgement<T> {
  const FileMutationRuntimeAcknowledgement({
    required this.identity,
    required this.disposition,
    this.value,
    this.message,
  });

  final FileMutationRuntimeIdentity identity;
  final FileMutationRuntimeAcknowledgementDisposition disposition;
  final T? value;
  final String? message;
}

final class FileMutationRuntimeOperationRequest {
  FileMutationRuntimeOperationRequest({
    required this.identity,
    required this.operation,
  }) {
    requireFileMutationOperation(identity, operation);
  }

  final FileMutationRuntimeIdentity identity;
  final FileMutationOperation operation;
}

final class FileMutationRuntimePreviewRequest {
  FileMutationRuntimePreviewRequest({
    required this.operationRequest,
    required this.deleteContent,
  });

  final FileMutationRuntimeOperationRequest operationRequest;
  final String? deleteContent;

  FileMutationRuntimeIdentity get identity => operationRequest.identity;
}

final class FileMutationRuntimeApprovalRequest {
  FileMutationRuntimeApprovalRequest({
    required this.identity,
    required this.request,
  }) {
    requireFileMutationApproval(identity, request);
  }

  final FileMutationRuntimeIdentity identity;
  final FileMutationApprovalRequest request;
}

final class FileMutationRuntimeCacheWriteRequest {
  const FileMutationRuntimeCacheWriteRequest({
    required this.approval,
    required this.result,
  });

  final FileMutationRuntimeApprovalRequest approval;
  final McpToolResult result;

  FileMutationRuntimeIdentity get identity => approval.identity;
}

enum FileMutationRuntimeDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
  boundaryMismatch,
}

final class FileMutationRuntimeCompletion {
  const FileMutationRuntimeCompletion({
    required this.identity,
    required this.disposition,
    required this.result,
  });

  final FileMutationRuntimeIdentity identity;
  final FileMutationRuntimeDisposition disposition;
  final McpToolResult result;
}

void requireFileMutationOperation(
  FileMutationRuntimeIdentity identity,
  FileMutationOperation operation,
) {
  if (operation.toolName != identity.toolName ||
      fileMutationJsonDigest(operation.arguments) !=
          identity.resolvedArgumentDigest ||
      (operation.path.isEmpty ? '' : DartProjectPath.pathKey(operation.path)) !=
          identity.canonicalPath) {
    throw ArgumentError('File mutation operation identity mismatch.');
  }
}

void requireFileMutationApproval(
  FileMutationRuntimeIdentity identity,
  FileMutationApprovalRequest request,
) {
  requireFileMutationOperation(identity, request.operation);
  final root = _canonicalRoot(request.toolRequest.projectRoot);
  if (request.toolRequest.owner != identity.owner ||
      request.toolCallId != identity.toolCallId ||
      root != identity.projectRoot ||
      fileMutationJsonDigest(request.arguments) != identity.argumentDigest ||
      _approvalContextDigest(
            request.approvalMode,
            request.conversationMessages,
            request.hasUntrustedInfluence,
          ) !=
          identity.approvalContextDigest) {
    throw ArgumentError('File mutation approval identity mismatch.');
  }
}

String fileMutationJsonDigest(Map<String, dynamic> arguments) {
  final frozen = ImmutableJsonSnapshot.freezeMap(arguments);
  return _digest(_canonicalJson(frozen));
}

McpToolResult fileMutationRuntimeFailure(
  String toolName,
  FileMutationRuntimeDisposition disposition,
  String message,
) {
  final code = switch (disposition) {
    FileMutationRuntimeDisposition.completed => throw StateError(
      'Completed file mutations do not use failure results.',
    ),
    FileMutationRuntimeDisposition.rejected => 'file_mutation_rejected',
    FileMutationRuntimeDisposition.ownerExpired => 'turn_owner_expired',
    FileMutationRuntimeDisposition.effectUncertain ||
    FileMutationRuntimeDisposition.boundaryMismatch =>
      'file_mutation_effect_uncertain',
  };
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': code,
      'error': message,
      'next_action': disposition == FileMutationRuntimeDisposition.ownerExpired
          ? 'Repeat the mutation in the current turn.'
          : 'Inspect the target file before retrying.',
    }),
    isSuccess: false,
    errorMessage: message,
  );
}

FileMutationKind _kindFor(String toolName) =>
    FileMutationKind.values.singleWhere((kind) => kind.toolName == toolName);

String _canonicalToolName(String value) {
  if (!FileMutationKind.values.any((kind) => kind.toolName == value)) {
    throw ArgumentError.value(
      value,
      'toolName',
      'Unsupported file mutation tool name.',
    );
  }
  return value;
}

String? _canonicalRoot(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return Directory(normalized).absolute.path;
}

String _approvalContextDigest(
  ToolApprovalMode mode,
  List<Message> messages,
  bool hasUntrustedInfluence,
) => _digest({
  'mode': mode.name,
  'hasUntrustedInfluence': hasUntrustedInfluence,
  'messages': [
    for (final message in messages)
      {
        'id': message.id,
        'role': message.role.name,
        'content': message.content,
        'timestamp': message.timestamp.toIso8601String(),
        'isStreaming': message.isStreaming,
        'error': message.error,
        'imageBase64': message.imageBase64,
        'imageMimeType': message.imageMimeType,
        'originalImagePath': message.originalImagePath,
        'originalImageMimeType': message.originalImageMimeType,
        'participantId': message.participantId,
        'participantDisplayName': message.participantDisplayName,
        'participantRoleLabel': message.participantRoleLabel,
        'participantColorValue': message.participantColorValue,
        'participantToolNames': [...message.participantToolNames],
        'handoffTargetParticipantId': message.handoffTargetParticipantId,
        'handoffTargetDisplayName': message.handoffTargetDisplayName,
        'handoffTargetRoleLabel': message.handoffTargetRoleLabel,
        'responseMetrics': switch (message.responseMetrics) {
          null => null,
          final metrics => {
            'promptTokens': metrics.promptTokens,
            'completionTokens': metrics.completionTokens,
            'totalTokens': metrics.totalTokens,
            'elapsedMilliseconds': metrics.elapsedMilliseconds,
            'finishReason': metrics.finishReason,
          },
        },
      },
  ],
});

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalJson).toList(growable: false);
  return value;
}

String _digest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

String _requiredExact(String value, String name) {
  if (value.isEmpty || value != value.trim()) {
    throw ArgumentError.value(
      value,
      name,
      '$name must be exact and non-empty.',
    );
  }
  return value;
}
