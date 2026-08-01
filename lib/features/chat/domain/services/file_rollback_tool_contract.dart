import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'immutable_json_snapshot.dart';

const String canonicalFileRollbackToolName = 'rollback_last_file_change';

String _requiredIdentityPart(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return normalized;
}

/// Exact identity of one single-file rollback invocation.
final class FileRollbackOperationIdentity {
  FileRollbackOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
  }) : toolCallId = _requiredIdentityPart(toolCallId, 'toolCallId'),
       toolName = _requiredIdentityPart(toolName, 'toolName') {
    if (this.toolName != canonicalFileRollbackToolName) {
      throw ArgumentError.value(
        toolName,
        'toolName',
        'The canonical rollback_last_file_change tool name is required.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;

  @override
  bool operator ==(Object other) {
    return other is FileRollbackOperationIdentity &&
        other.owner == owner &&
        other.toolCallId == toolCallId &&
        other.toolName == toolName;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName);
}

/// Immutable tool input captured for one exact rollback invocation.
final class FileRollbackToolRequest {
  FileRollbackToolRequest({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) : identity = FileRollbackOperationIdentity(
         owner: owner,
         toolCallId: toolCallId,
         toolName: toolName,
       ),
       arguments = _freezeFileRollbackArguments(arguments);

  final FileRollbackOperationIdentity identity;
  final Map<String, dynamic> arguments;

  ChatTurnOwner get owner => identity.owner;
  String get toolCallId => identity.toolCallId;
  String get toolName => identity.toolName;
  String? get reason => switch (arguments['reason']) {
    final String value => value,
    _ => null,
  };
}

Map<String, dynamic> _freezeFileRollbackArguments(
  Map<String, dynamic> arguments,
) {
  final frozen = ImmutableJsonSnapshot.freezeMap(arguments);
  void requireJsonNumber(Object? value) {
    if (value is double && !value.isFinite) {
      throw ArgumentError.value(
        value,
        'arguments',
        'Numbers must be finite JSON values.',
      );
    }
    if (value is Map<String, dynamic>) {
      value.values.forEach(requireJsonNumber);
    } else if (value is List<Object?>) {
      value.forEach(requireJsonNumber);
    }
  }

  frozen.values.forEach(requireJsonNumber);
  return frozen;
}

/// Exact rollback entry selected for one invocation.
final class FileRollbackToolPreview {
  FileRollbackToolPreview({
    required this.identity,
    required String checkpointToken,
    required this.path,
    required this.preview,
    required this.summary,
  }) : checkpointToken = _requiredIdentityPart(
         checkpointToken,
         'checkpointToken',
       ) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Must not be empty.');
    }
  }

  final FileRollbackOperationIdentity identity;
  final String checkpointToken;
  final String path;
  final String preview;
  final String summary;

  bool belongsTo(FileRollbackOperationIdentity expected) {
    return identity == expected;
  }
}

/// Immutable facts supplied to the exact rollback approval adapter.
final class FileRollbackApprovalRequest {
  const FileRollbackApprovalRequest({
    required this.toolRequest,
    required this.target,
    required this.reason,
  });

  final FileRollbackToolRequest toolRequest;
  final FileRollbackToolPreview target;
  final String? reason;

  FileRollbackOperationIdentity get identity => toolRequest.identity;
  String get checkpointToken => target.checkpointToken;
}

/// A cached denial bound to the invocation that produced it.
final class FileRollbackCachedDenial {
  const FileRollbackCachedDenial({
    required this.identity,
    required this.result,
  });

  final FileRollbackOperationIdentity identity;
  final McpToolResult result;
}

/// Auto-review or policy decision bound to one selected checkpoint.
final class FileRollbackApprovalDecision {
  const FileRollbackApprovalDecision({
    required this.identity,
    required this.checkpointToken,
    required this.gate,
  });

  final FileRollbackOperationIdentity identity;
  final String checkpointToken;
  final ToolApprovalGateDecision gate;

  bool belongsTo(FileRollbackApprovalRequest request) {
    return identity == request.identity &&
        checkpointToken == request.checkpointToken;
  }
}

/// Manual approval response bound to one selected checkpoint.
final class FileRollbackManualApprovalDecision {
  const FileRollbackManualApprovalDecision({
    required this.identity,
    required this.checkpointToken,
    required this.approved,
  });

  final FileRollbackOperationIdentity identity;
  final String checkpointToken;
  final bool approved;

  bool belongsTo(FileRollbackApprovalRequest request) {
    return identity == request.identity &&
        checkpointToken == request.checkpointToken;
  }
}

enum FileRollbackAcknowledgementDisposition {
  acknowledged,
  ownerExpired,
  effectUncertain,
}

/// Exact owner or cache acknowledgement for one selected checkpoint.
final class FileRollbackAcknowledgement {
  const FileRollbackAcknowledgement({
    required this.identity,
    required this.checkpointToken,
    required this.disposition,
  });

  final FileRollbackOperationIdentity identity;
  final String checkpointToken;
  final FileRollbackAcknowledgementDisposition disposition;

  bool belongsTo(FileRollbackApprovalRequest request) {
    return identity == request.identity &&
        checkpointToken == request.checkpointToken;
  }
}

enum FileRollbackExecutionDisposition {
  completed,
  ownerExpired,
  effectUncertain,
}

/// Durable state left when an owner expires around a rollback effect.
enum FileRollbackExpiredEffectDisposition {
  notApplied,
  compensated,
  retained,
  uncertain,
}

/// Execution completion bound to the exact selected checkpoint.
final class FileRollbackExecutionResult {
  const FileRollbackExecutionResult.completed({
    required this.identity,
    required this.checkpointToken,
    required McpToolResult this.result,
  }) : disposition = FileRollbackExecutionDisposition.completed,
       expiredEffectDisposition = null;

  const FileRollbackExecutionResult.ownerExpired({
    required this.identity,
    required this.checkpointToken,
    required FileRollbackExpiredEffectDisposition this.expiredEffectDisposition,
  }) : disposition = FileRollbackExecutionDisposition.ownerExpired,
       result = null;

  const FileRollbackExecutionResult.effectUncertain({
    required this.identity,
    required this.checkpointToken,
  }) : disposition = FileRollbackExecutionDisposition.effectUncertain,
       expiredEffectDisposition =
           FileRollbackExpiredEffectDisposition.uncertain,
       result = null;

  final FileRollbackOperationIdentity identity;
  final String checkpointToken;
  final FileRollbackExecutionDisposition disposition;
  final FileRollbackExpiredEffectDisposition? expiredEffectDisposition;
  final McpToolResult? result;

  bool belongsTo(FileRollbackApprovalRequest request) {
    return identity == request.identity &&
        checkpointToken == request.checkpointToken;
  }
}

/// Exact-invocation single-file rollback history lookup.
abstract interface class FileRollbackHistoryPort {
  Future<FileRollbackToolPreview?> previewLatest(
    FileRollbackOperationIdentity identity,
  );
}

/// Exact-invocation approval and owner acknowledgement boundary.
abstract interface class FileRollbackApprovalPort {
  FileRollbackCachedDenial? lookupDenial(FileRollbackToolRequest request);

  Future<FileRollbackApprovalDecision> resolveGate(
    FileRollbackApprovalRequest request,
  );

  Future<FileRollbackManualApprovalDecision> requestManualApproval(
    FileRollbackApprovalRequest request,
  );

  FileRollbackAcknowledgement acknowledgeOwner(
    FileRollbackApprovalRequest request,
  );

  FileRollbackAcknowledgement rememberDenial(
    FileRollbackApprovalRequest request,
    McpToolResult result,
  );

  FileRollbackAcknowledgement rememberResult(
    FileRollbackApprovalRequest request,
    McpToolResult result,
  );
}

/// Exact-checkpoint single-file rollback execution boundary.
abstract interface class FileRollbackExecutionPort {
  Future<FileRollbackExecutionResult> rollback(
    FileRollbackOperationIdentity identity,
    String checkpointToken,
  );
}
