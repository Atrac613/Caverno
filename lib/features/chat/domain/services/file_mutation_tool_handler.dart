import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../data/datasources/project_mutation_path_fence.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import 'file_mutation_result_builders.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: file-mutation-tool-handler

enum FileMutationKind {
  writeFile(
    toolName: 'write_file',
    approvalTitle: 'Write File',
    manualDenialMessage: 'User denied file write',
  ),
  editFile(
    toolName: 'edit_file',
    approvalTitle: 'Edit File',
    manualDenialMessage: 'User denied file edit',
  ),
  deleteFile(
    toolName: 'delete_file',
    approvalTitle: 'Delete File',
    manualDenialMessage: 'User denied file deletion',
  );

  const FileMutationKind({
    required this.toolName,
    required this.approvalTitle,
    required this.manualDenialMessage,
  });

  final String toolName;
  final String approvalTitle;
  final String manualDenialMessage;
}

/// One resolved write, edit, or delete request.
final class FileMutationOperation {
  FileMutationOperation({
    required this.kind,
    required Map<String, dynamic> arguments,
    this.reason,
  }) : arguments = ImmutableJsonSnapshot.freezeMap(arguments);

  final FileMutationKind kind;
  final Map<String, dynamic> arguments;
  final String? reason;

  String get toolName => kind.toolName;
  String get path => (arguments['path'] as String?)?.trim() ?? '';
  String get content => arguments['content'] as String? ?? '';
  String get oldText => arguments['old_text'] as String? ?? '';
  String get newText => arguments['new_text'] as String? ?? '';
  bool get replaceAll => arguments['replace_all'] as bool? ?? false;
}

/// Immutable owner and root facts captured before handler dispatch.
final class FileMutationToolRequest {
  FileMutationToolRequest({
    required this.owner,
    required this.toolCallId,
    required this.approvalMode,
    required String? projectRoot,
    required this.operation,
    Map<String, dynamic>? toolArguments,
    List<Message> conversationMessages = const [],
    this.hasUntrustedInfluence = false,
  }) : projectRoot = projectRoot?.trim(),
       toolArguments = ImmutableJsonSnapshot.freezeMap(
         toolArguments ?? operation.arguments,
       ),
       conversationMessages = List<Message>.unmodifiable(conversationMessages);

  final ChatTurnOwner owner;
  final String toolCallId;
  final ToolApprovalMode approvalMode;
  final String? projectRoot;
  final FileMutationOperation operation;
  final Map<String, dynamic> toolArguments;
  final List<Message> conversationMessages;
  final bool hasUntrustedInfluence;
}

/// Delete-only snapshot facts needed for validation and preview construction.
final class FileMutationDeleteSnapshot {
  const FileMutationDeleteSnapshot({required this.content, this.error});

  final String? content;
  final String? error;
}

/// Immutable approval facts supplied to the owner-aware approval adapter.
final class FileMutationApprovalRequest {
  const FileMutationApprovalRequest({
    required this.toolRequest,
    required this.stateFingerprint,
  });

  final FileMutationToolRequest toolRequest;
  final String stateFingerprint;

  FileMutationOperation get operation => toolRequest.operation;
  String get toolCallId => toolRequest.toolCallId;
  String get toolName => operation.toolName;
  ToolApprovalMode get approvalMode => toolRequest.approvalMode;
  Map<String, dynamic> get arguments => toolRequest.toolArguments;
  Map<String, dynamic> get cacheArguments => operation.arguments;
  String get path => operation.path;
  String? get reason => operation.reason;
  List<Message> get conversationMessages => toolRequest.conversationMessages;
  bool get hasUntrustedInfluence => toolRequest.hasUntrustedInfluence;
}

typedef FileMutationPreviewLoader = Future<String> Function();

/// Filesystem operations required by [FileMutationToolHandler].
abstract interface class FileMutationExecutionPort {
  Future<String?> preflightEdit(
    ChatTurnOwner owner,
    FileMutationOperation operation,
  );

  Future<String> fingerprint(ChatTurnOwner owner, String path);

  Future<bool> isRegularFile(ChatTurnOwner owner, String path);

  Future<FileMutationDeleteSnapshot> captureDeleteSnapshot(
    ChatTurnOwner owner,
    String path,
  );

  Future<String> buildPreview(
    ChatTurnOwner owner,
    FileMutationOperation operation, {
    String? deleteContent,
  });

  Future<McpToolResult> execute(
    ChatTurnOwner owner,
    FileMutationOperation operation,
  );
}

/// Owner-scoped approval cache, policy, UI, and expiration boundary.
abstract interface class FileMutationApprovalPort {
  McpToolResult? lookupDenial(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
  );

  Future<ToolApprovalGateDecision> resolveGate(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request, {
    required FileMutationPreviewLoader buildPreview,
  });

  Future<bool> requestManualApproval(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request, {
    required String preview,
  });

  McpToolResult rememberDenial(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
    McpToolResult result,
  );

  McpToolResult rememberResult(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
    McpToolResult result,
  );

  McpToolResult? expiredResult(ChatTurnOwner owner, String toolName);
}

/// Captures before-state and records a successful owner-scoped mutation.
abstract interface class FileMutationRollbackCapturePort<
  Snapshot extends Object
> {
  Future<Snapshot> captureBefore(ChatTurnOwner owner, String path);

  Future<void> recordSuccessfulMutation(
    ChatTurnOwner owner, {
    required Snapshot before,
    required String path,
  });
}

/// Executes approved file mutations without reading notifier or provider state.
final class FileMutationToolHandler<Snapshot extends Object> {
  const FileMutationToolHandler({
    required FileMutationExecutionPort executionPort,
    required FileMutationApprovalPort approvalPort,
    required FileMutationRollbackCapturePort<Snapshot> rollbackCapturePort,
    FileMutationPathAuthorizer authorizePath =
        ProjectMutationPathFence.authorizeCall,
  }) : _executionPort = executionPort,
       _approvalPort = approvalPort,
       _rollbackCapturePort = rollbackCapturePort,
       _authorizePath = authorizePath;

  final FileMutationExecutionPort _executionPort;
  final FileMutationApprovalPort _approvalPort;
  final FileMutationRollbackCapturePort<Snapshot> _rollbackCapturePort;
  final FileMutationPathAuthorizer _authorizePath;

  Future<McpToolResult> handle(FileMutationToolRequest request) async {
    final owner = request.owner;
    final operation = request.operation;
    final path = operation.path;

    if (operation.kind != FileMutationKind.deleteFile && path.isEmpty) {
      return fileMutationFailure(operation.toolName, 'path is required');
    }

    final pathAuth = await _authorizePath(
      toolName: operation.toolName,
      projectRoot: request.projectRoot,
      rawPath: path,
    );
    if (!pathAuth.isAllowed) {
      return pathAuth.deniedResult!;
    }
    final resolvedOperation = FileMutationOperation(
      kind: operation.kind,
      arguments: {...operation.arguments, 'path': pathAuth.canonicalPath!},
      reason: operation.reason,
    );
    final resolvedPath = resolvedOperation.path;

    String? deleteContent;
    if (resolvedOperation.kind == FileMutationKind.editFile) {
      final preflightResult = await _executionPort.preflightEdit(
        owner,
        resolvedOperation,
      );
      if (preflightResult != null) {
        final error = _tryDecodeMap(preflightResult)?['error']?.toString();
        return McpToolResult(
          toolName: operation.toolName,
          result: preflightResult,
          isSuccess: error == null,
          errorMessage: error,
        );
      }
    } else if (resolvedOperation.kind == FileMutationKind.deleteFile) {
      if (!await _executionPort.isRegularFile(owner, resolvedPath)) {
        return fileMutationDeleteNotRegularFile(
          resolvedOperation.toolName,
          resolvedPath,
        );
      }
      final snapshot = await _executionPort.captureDeleteSnapshot(
        owner,
        resolvedPath,
      );
      if (snapshot.error != null) {
        return fileMutationDeleteSnapshotUnavailable(
          resolvedOperation.toolName,
          resolvedPath,
        );
      }
      deleteContent = snapshot.content;
    }

    final stateFingerprint = await _executionPort.fingerprint(
      owner,
      resolvedPath,
    );
    final approvalRequest = FileMutationApprovalRequest(
      toolRequest: request,
      stateFingerprint: stateFingerprint,
    );
    final cachedDenial = _approvalPort.lookupDenial(owner, approvalRequest);
    if (cachedDenial != null) {
      return cachedDenial;
    }

    String? previewCache;
    Future<String> ensurePreview() async {
      return previewCache ??= await _executionPort.buildPreview(
        owner,
        resolvedOperation,
        deleteContent: deleteContent,
      );
    }

    final gate = await _approvalPort.resolveGate(
      owner,
      approvalRequest,
      buildPreview: ensurePreview,
    );
    if (gate.isDenied) {
      return _approvalPort.rememberDenial(
        owner,
        approvalRequest,
        fileMutationAutoReviewDenied(
          resolvedOperation.toolName,
          gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approved = await _approvalPort.requestManualApproval(
        owner,
        approvalRequest,
        preview: await ensurePreview(),
      );
      if (!approved) {
        return _approvalPort.rememberDenial(
          owner,
          approvalRequest,
          fileMutationFailure(
            resolvedOperation.toolName,
            resolvedOperation.kind.manualDenialMessage,
          ),
        );
      }
    }

    if (!gate.bypassedApproval) {
      final staleResult = await fileChangedSinceApprovalResult(
        owner: owner,
        toolName: resolvedOperation.toolName,
        path: resolvedPath,
        approvedStateFingerprint: stateFingerprint,
      );
      if (staleResult != null) {
        return staleResult;
      }
    }

    final before = await _rollbackCapturePort.captureBefore(
      owner,
      resolvedPath,
    );
    final expired = _approvalPort.expiredResult(
      owner,
      resolvedOperation.toolName,
    );
    if (expired != null) {
      return expired;
    }
    final result = await _executionPort.execute(owner, resolvedOperation);
    if (isSuccessfulFileMutationResult(result)) {
      await _rollbackCapturePort.recordSuccessfulMutation(
        owner,
        before: before,
        path: resolvedPath,
      );
    }
    return gate.bypassedApproval
        ? result
        : _approvalPort.rememberResult(owner, approvalRequest, result);
  }

  Future<McpToolResult?> fileChangedSinceApprovalResult({
    required ChatTurnOwner owner,
    required String toolName,
    required String path,
    required String approvedStateFingerprint,
  }) async {
    final currentFingerprint = await _executionPort.fingerprint(owner, path);
    if (currentFingerprint == approvedStateFingerprint) {
      return null;
    }
    return fileMutationChangedSinceApproval(toolName: toolName, path: path);
  }

  bool isSuccessfulMutationResult(McpToolResult result) {
    return isSuccessfulFileMutationResult(result);
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
