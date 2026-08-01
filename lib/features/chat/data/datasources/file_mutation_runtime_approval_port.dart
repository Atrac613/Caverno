import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/file_mutation_tool_handler.dart';
import 'file_mutation_runtime_contract.dart';
import 'file_mutation_runtime_state.dart';

/// Exact-identity bridge for approval policy, UI, cache, and expiry callbacks.
final class FileMutationRuntimeApprovalPort
    implements FileMutationApprovalPort {
  const FileMutationRuntimeApprovalPort({
    required FileMutationRuntimeIdentity identity,
    required FileMutationRuntimeState state,
    required FileMutationDenialLookupCallback lookupDenial,
    required FileMutationGateCallback resolveGate,
    required FileMutationManualApprovalCallback requestManualApproval,
    required FileMutationCacheWriteCallback rememberDenial,
    required FileMutationCacheWriteCallback rememberResult,
  }) : _identity = identity,
       _state = state,
       _lookupDenial = lookupDenial,
       _resolveGate = resolveGate,
       _requestManualApproval = requestManualApproval,
       _rememberDenial = rememberDenial,
       _rememberResult = rememberResult;

  final FileMutationRuntimeIdentity _identity;
  final FileMutationRuntimeState _state;
  final FileMutationDenialLookupCallback _lookupDenial;
  final FileMutationGateCallback _resolveGate;
  final FileMutationManualApprovalCallback _requestManualApproval;
  final FileMutationCacheWriteCallback _rememberDenial;
  final FileMutationCacheWriteCallback _rememberResult;

  @override
  McpToolResult? lookupDenial(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
  ) {
    final runtimeRequest = _request(owner, request);
    _state.ensureCurrent();
    final value = _state.acceptNullable(
      _lookupDenial(runtimeRequest),
      'File mutation denial lookup',
    );
    if (value != null) _state.validateResult(value);
    _state.ensureCurrent();
    return value;
  }

  @override
  Future<ToolApprovalGateDecision> resolveGate(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request, {
    required FileMutationPreviewLoader buildPreview,
  }) async {
    final runtimeRequest = _request(owner, request);
    _state.ensureCurrent();
    final acknowledgement = await _resolveGate(
      runtimeRequest,
      buildPreview: buildPreview,
    );
    final decision = _state.accept(
      acknowledgement,
      'File mutation approval gate',
    );
    _state.ensureCurrent();
    return decision;
  }

  @override
  Future<bool> requestManualApproval(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request, {
    required String preview,
  }) async {
    final runtimeRequest = _request(owner, request);
    _state.ensureCurrent();
    final acknowledgement = await _requestManualApproval(
      runtimeRequest,
      preview: preview,
    );
    final approved = _state.accept(
      acknowledgement,
      'File mutation manual approval',
    );
    _state.ensureCurrent();
    return approved;
  }

  @override
  McpToolResult rememberDenial(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
    McpToolResult result,
  ) {
    return _remember(
      owner,
      request,
      result,
      _rememberDenial,
      'File mutation denial cache write',
    );
  }

  @override
  McpToolResult rememberResult(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
    McpToolResult result,
  ) {
    return _remember(
      owner,
      request,
      result,
      _rememberResult,
      'File mutation result cache write',
    );
  }

  @override
  McpToolResult? expiredResult(ChatTurnOwner owner, String toolName) {
    _requireOwnerAndTool(owner, toolName);
    final acknowledgement = _state.readLifecycle();
    final value = acknowledgement.value;
    try {
      _state.requireCurrentLifecycle(acknowledgement);
      if (value != null) {
        _state.markEffectUncertain();
        throw const FileMutationRuntimeBoundaryException(
          'A current lifecycle acknowledgement returned an expired result.',
        );
      }
      return null;
    } on FileMutationRuntimeBoundaryException {
      final disposition = _state.classify(null);
      if (disposition == FileMutationRuntimeDisposition.ownerExpired) {
        if (value is McpToolResult) {
          _state.validateResult(value);
          return value;
        }
        return fileMutationRuntimeFailure(
          toolName,
          disposition,
          'The file mutation turn expired before execution.',
        );
      }
      if (disposition == FileMutationRuntimeDisposition.rejected) {
        return fileMutationRuntimeFailure(
          toolName,
          disposition,
          acknowledgement.message ?? 'The file mutation was rejected.',
        );
      }
      rethrow;
    }
  }

  McpToolResult _remember(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
    McpToolResult result,
    FileMutationCacheWriteCallback callback,
    String source,
  ) {
    final runtimeRequest = _request(owner, request);
    _state.validateResult(result);
    _state.ensureCurrent();
    _state.acceptNullable(
      callback(
        FileMutationRuntimeCacheWriteRequest(
          approval: runtimeRequest,
          result: result,
        ),
      ),
      source,
    );
    _state.ensureCurrent();
    return result;
  }

  FileMutationRuntimeApprovalRequest _request(
    ChatTurnOwner owner,
    FileMutationApprovalRequest request,
  ) {
    _requireOwnerAndTool(owner, request.toolName);
    return FileMutationRuntimeApprovalRequest(
      identity: _identity,
      request: request,
    );
  }

  void _requireOwnerAndTool(ChatTurnOwner owner, String toolName) {
    if (owner != _identity.owner || toolName != _identity.toolName) {
      _state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw const FileMutationRuntimeBoundaryException(
        'File mutation approval boundary identity mismatch.',
      );
    }
  }
}
