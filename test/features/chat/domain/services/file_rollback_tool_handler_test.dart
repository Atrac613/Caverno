import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/file_rollback_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

part 'file_rollback_tool_contract_cases.dart';
part 'file_rollback_tool_post_effect_cases.dart';
part 'file_rollback_tool_pre_effect_cases.dart';

const _success = McpToolResult(
  toolName: canonicalFileRollbackToolName,
  result: '{"ok":true,"path":"/workspace/a/lib/main.dart"}',
  isSuccess: true,
);

const _knownFailure = McpToolResult(
  toolName: canonicalFileRollbackToolName,
  result:
      '{"ok":false,"code":"file_changed_since_preview",'
      '"path":"/workspace/a/lib/main.dart"}',
  isSuccess: false,
  errorMessage: 'Failed to roll back the last file change',
);

final class _MutableLeaf {
  int value = 1;
}

final class _FakeHistoryPort implements FileRollbackHistoryPort {
  FileRollbackToolPreview? preview;
  Object? error;
  final List<FileRollbackOperationIdentity> identities = [];

  @override
  Future<FileRollbackToolPreview?> previewLatest(
    FileRollbackOperationIdentity identity,
  ) async {
    identities.add(identity);
    if (error case final error?) throw error;
    return preview;
  }
}

final class _FakeApprovalPort implements FileRollbackApprovalPort {
  FileRollbackCachedDenial? cachedDenial;
  ToolApprovalGateDecision gate = ToolApprovalGateDecision.needsManualApproval;
  bool manualApproved = true;
  FileRollbackOperationIdentity? gateIdentity;
  FileRollbackOperationIdentity? manualIdentity;
  FileRollbackOperationIdentity? ownerAckIdentity;
  FileRollbackOperationIdentity? denialAckIdentity;
  FileRollbackOperationIdentity? resultAckIdentity;
  String? gateToken;
  String? manualToken;
  String? ownerAckToken;
  String? denialAckToken;
  String? resultAckToken;
  FileRollbackAcknowledgementDisposition ownerAckDisposition =
      FileRollbackAcknowledgementDisposition.acknowledged;
  FileRollbackAcknowledgementDisposition denialAckDisposition =
      FileRollbackAcknowledgementDisposition.acknowledged;
  FileRollbackAcknowledgementDisposition resultAckDisposition =
      FileRollbackAcknowledgementDisposition.acknowledged;
  Object? resultAckError;

  final List<FileRollbackToolRequest> lookupRequests = [];
  final List<FileRollbackApprovalRequest> gateRequests = [];
  final List<FileRollbackApprovalRequest> manualRequests = [];
  final List<FileRollbackApprovalRequest> ownerAckRequests = [];
  final List<FileRollbackApprovalRequest> denialAckRequests = [];
  final List<FileRollbackApprovalRequest> resultAckRequests = [];
  final List<McpToolResult> rememberedDenials = [];
  final List<McpToolResult> rememberedResults = [];

  @override
  FileRollbackCachedDenial? lookupDenial(FileRollbackToolRequest request) {
    lookupRequests.add(request);
    return cachedDenial;
  }

  @override
  Future<FileRollbackApprovalDecision> resolveGate(
    FileRollbackApprovalRequest request,
  ) async {
    gateRequests.add(request);
    return FileRollbackApprovalDecision(
      identity: gateIdentity ?? request.identity,
      checkpointToken: gateToken ?? request.checkpointToken,
      gate: gate,
    );
  }

  @override
  Future<FileRollbackManualApprovalDecision> requestManualApproval(
    FileRollbackApprovalRequest request,
  ) async {
    manualRequests.add(request);
    return FileRollbackManualApprovalDecision(
      identity: manualIdentity ?? request.identity,
      checkpointToken: manualToken ?? request.checkpointToken,
      approved: manualApproved,
    );
  }

  @override
  FileRollbackAcknowledgement acknowledgeOwner(
    FileRollbackApprovalRequest request,
  ) {
    ownerAckRequests.add(request);
    return FileRollbackAcknowledgement(
      identity: ownerAckIdentity ?? request.identity,
      checkpointToken: ownerAckToken ?? request.checkpointToken,
      disposition: ownerAckDisposition,
    );
  }

  @override
  FileRollbackAcknowledgement rememberDenial(
    FileRollbackApprovalRequest request,
    McpToolResult result,
  ) {
    denialAckRequests.add(request);
    rememberedDenials.add(result);
    return FileRollbackAcknowledgement(
      identity: denialAckIdentity ?? request.identity,
      checkpointToken: denialAckToken ?? request.checkpointToken,
      disposition: denialAckDisposition,
    );
  }

  @override
  FileRollbackAcknowledgement rememberResult(
    FileRollbackApprovalRequest request,
    McpToolResult result,
  ) {
    resultAckRequests.add(request);
    rememberedResults.add(result);
    if (resultAckError case final error?) throw error;
    return FileRollbackAcknowledgement(
      identity: resultAckIdentity ?? request.identity,
      checkpointToken: resultAckToken ?? request.checkpointToken,
      disposition: resultAckDisposition,
    );
  }
}

typedef _ExecutionBuilder =
    FileRollbackExecutionResult Function(
      FileRollbackOperationIdentity identity,
      String checkpointToken,
    );

final class _FakeExecutionPort implements FileRollbackExecutionPort {
  _ExecutionBuilder? builder;
  Object? error;
  final List<FileRollbackOperationIdentity> identities = [];
  final List<String> checkpointTokens = [];

  @override
  Future<FileRollbackExecutionResult> rollback(
    FileRollbackOperationIdentity identity,
    String checkpointToken,
  ) async {
    identities.add(identity);
    checkpointTokens.add(checkpointToken);
    if (error case final error?) throw error;
    return builder?.call(identity, checkpointToken) ??
        FileRollbackExecutionResult.completed(
          identity: identity,
          checkpointToken: checkpointToken,
          result: _success,
        );
  }
}

FileRollbackOperationIdentity _identity(
  ChatTurnOwner owner, {
  String call = 'rollback-call-a',
}) {
  return FileRollbackOperationIdentity(
    owner: owner,
    toolCallId: call,
    toolName: canonicalFileRollbackToolName,
  );
}

FileRollbackToolRequest _request(
  ChatTurnOwner owner, {
  String call = 'rollback-call-a',
  Map<String, dynamic> arguments = const {},
}) {
  return FileRollbackToolRequest(
    owner: owner,
    toolCallId: call,
    toolName: canonicalFileRollbackToolName,
    arguments: arguments,
  );
}

FileRollbackToolPreview _preview(
  FileRollbackOperationIdentity identity, {
  String token = 'checkpoint-a',
  String path = '/workspace/a/lib/main.dart',
}) {
  return FileRollbackToolPreview(
    identity: identity,
    checkpointToken: token,
    path: path,
    preview: 'diff --git a/lib/main.dart b/lib/main.dart',
    summary: 'Restore the previous contents of this file.',
  );
}

FileRollbackToolHandler _handler(
  _FakeHistoryPort history,
  _FakeApprovalPort approval,
  _FakeExecutionPort execution,
) {
  return FileRollbackToolHandler(
    historyPort: history,
    approvalPort: approval,
    executionPort: execution,
  );
}

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );
  final ownerANext = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 8,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 7,
  );

  _runFileRollbackContractCases(ownerA);
  _runFileRollbackPreEffectCases(ownerA, ownerANext, ownerB);
  _runFileRollbackPostEffectCases(ownerA, ownerANext, ownerB);
}
