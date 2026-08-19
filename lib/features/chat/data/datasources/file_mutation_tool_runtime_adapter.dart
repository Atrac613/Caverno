import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/file_mutation_effect_coordinator.dart';
import '../../domain/services/file_mutation_tool_handler.dart';
import 'file_mutation_runtime_approval_port.dart';
import 'file_mutation_runtime_contract.dart';
import 'file_mutation_runtime_ports.dart';
import 'file_mutation_runtime_state.dart';
import 'project_mutation_path_fence.dart';

export 'file_mutation_runtime_contract.dart';

/// Production bridge for exact owner-bound write, edit, and delete calls.
final class FileMutationToolRuntimeAdapter<Snapshot extends Object> {
  FileMutationToolRuntimeAdapter({
    required FileMutationLifecycleCallback acknowledgeLifecycle,
    required FileMutationPreflightCallback preflightEdit,
    required FileMutationFingerprintCallback fingerprint,
    required FileMutationRegularFileCallback isRegularFile,
    required FileMutationDeleteSnapshotCallback captureDeleteSnapshot,
    required FileMutationPreviewCallback buildPreview,
    required FileMutationDenialLookupCallback lookupDenial,
    required FileMutationGateCallback resolveGate,
    required FileMutationManualApprovalCallback requestManualApproval,
    required FileMutationCacheWriteCallback rememberDenial,
    required FileMutationCacheWriteCallback rememberResult,
    required FileMutationRollbackCaptureCallback<Snapshot> captureBefore,
    required FileMutationRollbackRecordCallback<Snapshot> recordMutation,
    required FileMutationExecutionCallback<Snapshot> execute,
    required FileMutationCompensationCallback<Snapshot> compensate,
    FileMutationEffectCoordinator? effectCoordinator,
    FileMutationPathAuthorizer authorizePath =
        ProjectMutationPathFence.authorizeCall,
  }) : _acknowledgeLifecycle = acknowledgeLifecycle,
       _preflightEdit = preflightEdit,
       _fingerprint = fingerprint,
       _isRegularFile = isRegularFile,
       _captureDeleteSnapshot = captureDeleteSnapshot,
       _buildPreview = buildPreview,
       _lookupDenial = lookupDenial,
       _resolveGate = resolveGate,
       _requestManualApproval = requestManualApproval,
       _rememberDenial = rememberDenial,
       _rememberResult = rememberResult,
       _captureBefore = captureBefore,
       _recordMutation = recordMutation,
       _execute = execute,
       _compensate = compensate,
       _effectCoordinator =
           effectCoordinator ?? FileMutationEffectCoordinator(),
       _authorizePath = authorizePath;

  final FileMutationLifecycleCallback _acknowledgeLifecycle;
  final FileMutationPreflightCallback _preflightEdit;
  final FileMutationFingerprintCallback _fingerprint;
  final FileMutationRegularFileCallback _isRegularFile;
  final FileMutationDeleteSnapshotCallback _captureDeleteSnapshot;
  final FileMutationPreviewCallback _buildPreview;
  final FileMutationDenialLookupCallback _lookupDenial;
  final FileMutationGateCallback _resolveGate;
  final FileMutationManualApprovalCallback _requestManualApproval;
  final FileMutationCacheWriteCallback _rememberDenial;
  final FileMutationCacheWriteCallback _rememberResult;
  final FileMutationRollbackCaptureCallback<Snapshot> _captureBefore;
  final FileMutationRollbackRecordCallback<Snapshot> _recordMutation;
  final FileMutationExecutionCallback<Snapshot> _execute;
  final FileMutationCompensationCallback<Snapshot> _compensate;
  final FileMutationEffectCoordinator _effectCoordinator;
  final FileMutationPathAuthorizer _authorizePath;

  Future<FileMutationRuntimeCompletion> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required ToolApprovalMode approvalMode,
    required String? projectRoot,
    required Map<String, dynamic> resolvedArguments,
    required List<Message> conversationMessages,
    required bool hasUntrustedInfluence,
  }) async {
    final input = FileMutationRuntimeInput(
      owner: owner,
      toolCall: toolCall,
      approvalMode: approvalMode,
      projectRoot: projectRoot,
      resolvedArguments: resolvedArguments,
      conversationMessages: conversationMessages,
      hasUntrustedInfluence: hasUntrustedInfluence,
    );
    final identity = input.identity;
    final state = FileMutationRuntimeState(
      identity: identity,
      acknowledgeLifecycle: _acknowledgeLifecycle,
      retireOwner: () => _effectCoordinator.retireOwner(identity.owner),
    );
    final filesystemPorts = FileMutationRuntimePorts<Snapshot>(
      identity: identity,
      state: state,
      effectCoordinator: _effectCoordinator,
      preflightEdit: _preflightEdit,
      fingerprint: _fingerprint,
      isRegularFile: _isRegularFile,
      captureDeleteSnapshot: _captureDeleteSnapshot,
      buildPreview: _buildPreview,
      captureBefore: _captureBefore,
      recordMutation: _recordMutation,
      execute: _execute,
      compensate: _compensate,
    );
    final approvalPort = FileMutationRuntimeApprovalPort(
      identity: identity,
      state: state,
      lookupDenial: _lookupDenial,
      resolveGate: _resolveGate,
      requestManualApproval: _requestManualApproval,
      rememberDenial: _rememberDenial,
      rememberResult: _rememberResult,
    );
    final handler =
        FileMutationToolHandler<FileMutationRollbackCapture<Snapshot>>(
          executionPort: filesystemPorts,
          approvalPort: approvalPort,
          rollbackCapturePort: filesystemPorts,
          authorizePath: _authorizePath,
        );

    McpToolResult? result;
    var failureMessage = 'The file mutation runtime boundary failed.';
    try {
      result = await handler.handle(input.toToolRequest());
      state.validateResult(result);
    } on FileMutationRuntimeBoundaryException catch (error) {
      failureMessage = error.message;
    } catch (error) {
      failureMessage = 'The file mutation runtime boundary failed: $error';
      if (state.effectStarted) {
        state.markEffectUncertain();
      } else {
        state.observe(FileMutationRuntimeDisposition.rejected);
      }
    }
    await filesystemPorts.settleAfterHandler(result);
    final disposition = state.classify(result);
    final finalResult = switch (disposition) {
      FileMutationRuntimeDisposition.completed => result!,
      FileMutationRuntimeDisposition.rejected =>
        result ??
            fileMutationRuntimeFailure(
              identity.toolName,
              disposition,
              failureMessage,
            ),
      FileMutationRuntimeDisposition.ownerExpired =>
        result != null && !result.isSuccess
            ? result
            : fileMutationRuntimeFailure(
                identity.toolName,
                disposition,
                failureMessage,
              ),
      FileMutationRuntimeDisposition.effectUncertain ||
      FileMutationRuntimeDisposition.boundaryMismatch =>
        fileMutationRuntimeFailure(
          identity.toolName,
          disposition,
          failureMessage,
        ),
    };
    return FileMutationRuntimeCompletion(
      identity: identity,
      disposition: disposition,
      result: finalResult,
    );
  }

  FileMutationOwnerRetirement retireOwner(ChatTurnOwner owner) {
    return _effectCoordinator.retireOwner(owner);
  }

  FileMutationOwnerRetirement clearAll() {
    return _effectCoordinator.clearAll();
  }
}
