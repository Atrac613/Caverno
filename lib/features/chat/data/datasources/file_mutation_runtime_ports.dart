import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/file_mutation_effect_coordinator.dart';
import '../../domain/services/file_mutation_tool_handler.dart';
import 'file_mutation_runtime_contract.dart';
import 'file_mutation_runtime_state.dart';

part 'file_mutation_runtime_effect_settlement.dart';

/// Filesystem and rollback bridge for one exact mutation attempt.
final class FileMutationRuntimePorts<Snapshot extends Object>
    implements
        FileMutationExecutionPort,
        FileMutationRollbackCapturePort<FileMutationRollbackCapture<Snapshot>> {
  FileMutationRuntimePorts({
    required this.identity,
    required this.state,
    required FileMutationEffectCoordinator effectCoordinator,
    required FileMutationPreflightCallback preflightEdit,
    required FileMutationFingerprintCallback fingerprint,
    required FileMutationRegularFileCallback isRegularFile,
    required FileMutationDeleteSnapshotCallback captureDeleteSnapshot,
    required FileMutationPreviewCallback buildPreview,
    required FileMutationRollbackCaptureCallback<Snapshot> captureBefore,
    required FileMutationRollbackRecordCallback<Snapshot> recordMutation,
    required FileMutationExecutionCallback<Snapshot> execute,
    required FileMutationCompensationCallback<Snapshot> compensate,
  }) : _effectCoordinator = effectCoordinator,
       _preflightEdit = preflightEdit,
       _fingerprint = fingerprint,
       _isRegularFile = isRegularFile,
       _captureDeleteSnapshot = captureDeleteSnapshot,
       _buildPreview = buildPreview,
       _captureBefore = captureBefore,
       _recordMutation = recordMutation,
       _execute = execute,
       _compensate = compensate;

  final FileMutationRuntimeIdentity identity;
  final FileMutationRuntimeState state;
  final FileMutationEffectCoordinator _effectCoordinator;
  final FileMutationPreflightCallback _preflightEdit;
  final FileMutationFingerprintCallback _fingerprint;
  final FileMutationRegularFileCallback _isRegularFile;
  final FileMutationDeleteSnapshotCallback _captureDeleteSnapshot;
  final FileMutationPreviewCallback _buildPreview;
  final FileMutationRollbackCaptureCallback<Snapshot> _captureBefore;
  final FileMutationRollbackRecordCallback<Snapshot> _recordMutation;
  final FileMutationExecutionCallback<Snapshot> _execute;
  final FileMutationCompensationCallback<Snapshot> _compensate;

  FileMutationRollbackCapture<Snapshot>? _capture;
  FileMutationAppliedReceipt? _appliedReceipt;
  String? _recordToken;

  @override
  Future<String?> preflightEdit(
    ChatTurnOwner owner,
    FileMutationOperation operation,
  ) async {
    final request = _operationRequest(owner, operation);
    state.ensureCurrent();
    final acknowledgement = await _preflightEdit(request);
    final value = state.acceptNullable(
      acknowledgement,
      'File mutation edit preflight',
    );
    state.ensureCurrent();
    return value;
  }

  @override
  Future<String> fingerprint(ChatTurnOwner owner, String path) async {
    _requirePath(owner, path);
    state.ensureCurrent();
    final value = await _rawFingerprint();
    state.ensureCurrent();
    return value;
  }

  @override
  Future<bool> isRegularFile(ChatTurnOwner owner, String path) async {
    _requirePath(owner, path);
    state.ensureCurrent();
    final acknowledgement = await _isRegularFile(identity);
    final value = state.accept(
      acknowledgement,
      'File mutation regular-file check',
    );
    state.ensureCurrent();
    return value;
  }

  @override
  Future<FileMutationDeleteSnapshot> captureDeleteSnapshot(
    ChatTurnOwner owner,
    String path,
  ) async {
    _requirePath(owner, path);
    state.ensureCurrent();
    final acknowledgement = await _captureDeleteSnapshot(identity);
    final value = state.accept(
      acknowledgement,
      'File mutation delete snapshot',
    );
    state.ensureCurrent();
    return value;
  }

  @override
  Future<String> buildPreview(
    ChatTurnOwner owner,
    FileMutationOperation operation, {
    String? deleteContent,
  }) async {
    final operationRequest = _operationRequest(owner, operation);
    state.ensureCurrent();
    final acknowledgement = await _buildPreview(
      FileMutationRuntimePreviewRequest(
        operationRequest: operationRequest,
        deleteContent: deleteContent,
      ),
    );
    final value = state.accept(acknowledgement, 'File mutation preview');
    state.ensureCurrent();
    return value;
  }

  @override
  Future<FileMutationRollbackCapture<Snapshot>> captureBefore(
    ChatTurnOwner owner,
    String path,
  ) async {
    _requirePath(owner, path);
    state.ensureCurrent();
    final acknowledgement = await _captureBefore(identity);
    final capture = state.accept(
      acknowledgement,
      'File mutation rollback capture',
    );
    if (capture.identity != identity) {
      state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw const FileMutationRuntimeBoundaryException(
        'File mutation rollback capture identity mismatch.',
      );
    }
    final observedFingerprint = await _rawFingerprint();
    if (observedFingerprint != capture.beforeFingerprint) {
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'The file changed while its rollback snapshot was captured.',
      );
    }
    state.ensureCurrent();
    return _capture = capture;
  }

  @override
  Future<McpToolResult> execute(
    ChatTurnOwner owner,
    FileMutationOperation operation,
  ) async {
    final operationRequest = _operationRequest(owner, operation);
    final capture = _capture;
    if (capture == null) {
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'File mutation execution has no rollback capture.',
      );
    }
    state.ensureCurrent();
    final operationIdentity = _coordinatorIdentity();
    final acquired = _effectCoordinator.acquire(
      operationIdentity,
      beforeFingerprint: capture.beforeFingerprint,
    );
    final lease = acquired.lease;
    if (lease == null) {
      if (acquired.disposition == FileMutationAcquireDisposition.ownerRetired) {
        state.observe(FileMutationRuntimeDisposition.ownerExpired);
      } else {
        state.observe(FileMutationRuntimeDisposition.rejected);
      }
      throw FileMutationRuntimeBoundaryException(
        acquired.disposition == FileMutationAcquireDisposition.pathBusy
            ? 'The target path already has a mutation in flight.'
            : 'The file mutation owner expired before execution.',
      );
    }
    final authorization = FileMutationEffectAuthorization(
      identity: identity,
      beginEffect: () {
        try {
          state.ensureCurrent();
        } on FileMutationRuntimeBoundaryException {
          return false;
        }
        final started = _effectCoordinator.beginEffect(
          operationIdentity,
          lease,
        );
        if (started) state.effectStarted = true;
        return started;
      },
    );

    late final FileMutationExecutionAcknowledgement acknowledgement;
    try {
      acknowledgement = await _execute(
        FileMutationEffectRequest(
          operationRequest: operationRequest,
          capture: capture,
        ),
        authorization,
      );
    } catch (error) {
      if (!authorization.started) {
        _effectCoordinator.finishWithoutEffect(operationIdentity, lease);
        state.observe(FileMutationRuntimeDisposition.rejected);
      } else {
        state.markEffectUncertain();
        await _reconcileStartedEffectWithoutReceipt(
          operationIdentity,
          lease,
          capture,
        );
      }
      throw FileMutationRuntimeBoundaryException(
        'The raw file mutation callback failed: $error',
      );
    }

    try {
      if (acknowledgement.identity != identity) {
        state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
        throw const FileMutationRuntimeBoundaryException(
          'File mutation execution acknowledgement identity mismatch.',
        );
      }
      state.validateResult(acknowledgement.result);
      return await _settleExecution(
        operationIdentity,
        lease,
        capture,
        authorization,
        acknowledgement,
      );
    } catch (_) {
      if (!authorization.started) {
        _effectCoordinator.finishWithoutEffect(operationIdentity, lease);
      } else if (_appliedReceipt == null &&
          _effectCoordinator.isPathBusy(operationIdentity.canonicalPath)) {
        state.markEffectUncertain();
        await _reconcileStartedEffectWithoutReceipt(
          operationIdentity,
          lease,
          capture,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> recordSuccessfulMutation(
    ChatTurnOwner owner, {
    required FileMutationRollbackCapture<Snapshot> before,
    required String path,
  }) async {
    _requirePath(owner, path);
    if (!identical(before, _capture) ||
        before.identity != identity ||
        _appliedReceipt == null) {
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'File mutation rollback record identity mismatch.',
      );
    }
    final receipt = _appliedReceipt!;
    try {
      final acknowledgement = await _recordMutation(
        FileMutationRollbackRecordRequest(
          capture: before,
          expectedAfterFingerprint: receipt.expectedAfterFingerprint,
        ),
      );
      final record = state.accept(
        acknowledgement,
        'File mutation rollback record',
      );
      if (record.identity != identity ||
          record.compensationToken != before.compensationToken) {
        state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
        throw const FileMutationRuntimeBoundaryException(
          'File mutation rollback record receipt mismatch.',
        );
      }
      _recordToken = record.recordToken;
      state.ensureCurrent();
      final disposition = _effectCoordinator.finishCommitted(
        _coordinatorIdentity(),
        receipt,
      );
      if (disposition == FileMutationCommitDisposition.committed) {
        _appliedReceipt = null;
        return;
      }
      if (disposition == FileMutationCommitDisposition.invalidReceipt) {
        state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
      }
      await _compensateAppliedEffect();
      throw const FileMutationRuntimeBoundaryException(
        'The file mutation could not be committed to its owning turn.',
      );
    } on FileMutationRuntimeBoundaryException {
      if (_appliedReceipt != null &&
          state.classify(null) !=
              FileMutationRuntimeDisposition.effectUncertain &&
          state.classify(null) !=
              FileMutationRuntimeDisposition.boundaryMismatch) {
        await _compensateAppliedEffect();
      }
      rethrow;
    } catch (error) {
      state.markEffectUncertain();
      throw FileMutationRuntimeBoundaryException(
        'The rollback record callback failed after mutation: $error',
      );
    }
  }

  Future<void> settleAfterHandler(McpToolResult? result) async {
    final receipt = _appliedReceipt;
    if (receipt == null) return;
    final disposition = state.classify(result);
    if (disposition == FileMutationRuntimeDisposition.ownerExpired ||
        result?.isSuccess != true) {
      await _compensateAppliedEffect();
    }
    if (_appliedReceipt != null ||
        result?.isSuccess != true ||
        disposition == FileMutationRuntimeDisposition.completed) {
      state.markEffectUncertain();
    }
  }

  Future<String> _rawFingerprint() async {
    final acknowledgement = await _fingerprint(identity);
    final value = state.accept(acknowledgement, 'File mutation fingerprint');
    if (value.trim().isEmpty) {
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'File mutation fingerprint was empty.',
      );
    }
    return value;
  }

  FileMutationRuntimeOperationRequest _operationRequest(
    ChatTurnOwner owner,
    FileMutationOperation operation,
  ) {
    if (owner != identity.owner) {
      state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw const FileMutationRuntimeBoundaryException(
        'File mutation owner identity mismatch.',
      );
    }
    return FileMutationRuntimeOperationRequest(
      identity: identity,
      operation: operation,
    );
  }

  void _requirePath(ChatTurnOwner owner, String path) {
    final canonicalPath = path.trim().isEmpty
        ? ''
        : DartProjectPath.pathKey(path);
    if (owner != identity.owner || canonicalPath != identity.canonicalPath) {
      state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw const FileMutationRuntimeBoundaryException(
        'File mutation path identity mismatch.',
      );
    }
  }

  FileMutationOperationIdentity _coordinatorIdentity() =>
      FileMutationOperationIdentity(
        owner: identity.owner,
        toolCallId: identity.toolCallId,
        toolName: identity.toolName,
        canonicalPath: identity.canonicalPath,
      );
}
