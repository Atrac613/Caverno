part of 'file_mutation_runtime_ports.dart';

extension _FileMutationRuntimeEffectSettlement<Snapshot extends Object>
    on FileMutationRuntimePorts<Snapshot> {
  Future<bool> _reconcileStartedEffectWithoutReceipt(
    FileMutationOperationIdentity operationIdentity,
    FileMutationEffectLease lease,
    FileMutationRollbackCapture<Snapshot> capture,
  ) async {
    if (_appliedReceipt != null) return false;

    final String observedCurrent;
    try {
      observedCurrent = await _rawFingerprint();
    } catch (_) {
      state.markEffectUncertain();
      return false;
    }

    if (observedCurrent == capture.beforeFingerprint) {
      try {
        final acknowledgement = await _compensate(
          FileMutationCompensationRequest(
            capture: capture,
            expectedAfterFingerprint: observedCurrent,
            recordToken: null,
          ),
        );
        final reverted =
            acknowledgement.identity == identity &&
            acknowledgement.compensationToken == capture.compensationToken &&
            acknowledgement.disposition ==
                FileMutationRuntimeCompensationDisposition.reverted;
        if (!reverted) {
          state.markEffectUncertain();
          return false;
        }
        final released = _effectCoordinator.finishWithoutEffect(
          operationIdentity,
          lease,
        );
        if (!released) {
          state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
        }
        return released;
      } catch (_) {
        state.markEffectUncertain();
        return false;
      }
    }

    try {
      _markApplied(
        operationIdentity,
        lease,
        observedCurrent,
        capture.compensationToken,
      );
    } catch (_) {
      state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
      return false;
    }
    return _compensateAppliedEffect();
  }

  Future<McpToolResult> _settleExecution(
    FileMutationOperationIdentity operationIdentity,
    FileMutationEffectLease lease,
    FileMutationRollbackCapture<Snapshot> capture,
    FileMutationEffectAuthorization authorization,
    FileMutationExecutionAcknowledgement acknowledgement,
  ) async {
    if (!authorization.started) {
      if (acknowledgement.effectDisposition ==
          FileMutationRawEffectDisposition.noEffect) {
        _effectCoordinator.finishWithoutEffect(operationIdentity, lease);
        return acknowledgement.result;
      }
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'The mutation bypassed its effect-start authorization.',
      );
    }

    final observedAfter = await _rawFingerprint();
    final postcondition = acknowledgement.postcondition;
    if (acknowledgement.effectDisposition ==
        FileMutationRawEffectDisposition.noEffect) {
      if (observedAfter == capture.beforeFingerprint) {
        _effectCoordinator.finishWithoutEffect(operationIdentity, lease);
        return acknowledgement.result;
      }
      _markApplied(
        operationIdentity,
        lease,
        observedAfter,
        capture.compensationToken,
      );
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'A no-effect mutation acknowledgement changed the target file.',
      );
    }
    if (postcondition == null ||
        postcondition.identity != identity ||
        postcondition.compensationToken != capture.compensationToken ||
        postcondition.afterFingerprint != observedAfter) {
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'File mutation postcondition receipt mismatch.',
      );
    }
    _markApplied(
      operationIdentity,
      lease,
      observedAfter,
      capture.compensationToken,
    );
    if (acknowledgement.effectDisposition ==
        FileMutationRawEffectDisposition.partialOrUnknown) {
      state.markEffectUncertain();
      throw const FileMutationRuntimeBoundaryException(
        'The filesystem reported a partial or ambiguous mutation.',
      );
    }
    if (state.classify(null) == FileMutationRuntimeDisposition.ownerExpired) {
      await _compensateAppliedEffect();
      throw const FileMutationRuntimeBoundaryException(
        'The file mutation owner retired during execution.',
      );
    }
    try {
      state.ensureCurrent();
    } on FileMutationRuntimeBoundaryException {
      await _compensateAppliedEffect();
      rethrow;
    }
    return acknowledgement.result;
  }

  void _markApplied(
    FileMutationOperationIdentity operationIdentity,
    FileMutationEffectLease lease,
    String afterFingerprint,
    String compensationToken,
  ) {
    final applied = _effectCoordinator.markApplied(
      operationIdentity,
      lease,
      expectedAfterFingerprint: afterFingerprint,
      compensationToken: compensationToken,
    );
    final receipt = applied.receipt;
    if (receipt == null) {
      state.observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw const FileMutationRuntimeBoundaryException(
        'File mutation effect lease was rejected.',
      );
    }
    _appliedReceipt = receipt;
    if (applied.disposition ==
        FileMutationApplyDisposition.compensationRequired) {
      state.observe(FileMutationRuntimeDisposition.ownerExpired);
    }
  }

  Future<bool> _compensateAppliedEffect() async {
    final receipt = _appliedReceipt;
    final capture = _capture;
    if (receipt == null || capture == null) return false;
    final operationIdentity = _coordinatorIdentity();
    final current = await _rawFingerprint();
    final readiness = _effectCoordinator.beginCompensation(
      operationIdentity,
      receipt,
      observedCurrentFingerprint: current,
    );
    if (readiness != FileMutationCompensationDisposition.ready) {
      state.markEffectUncertain();
      return false;
    }
    try {
      final acknowledgement = await _compensate(
        FileMutationCompensationRequest(
          capture: capture,
          expectedAfterFingerprint: receipt.expectedAfterFingerprint,
          recordToken: _recordToken,
        ),
      );
      if (acknowledgement.identity != identity ||
          acknowledgement.compensationToken != capture.compensationToken ||
          acknowledgement.disposition !=
              FileMutationRuntimeCompensationDisposition.reverted) {
        _effectCoordinator.completeCompensation(
          operationIdentity,
          receipt,
          succeeded: false,
        );
        state.markEffectUncertain();
        return false;
      }
      final completed = _effectCoordinator.completeCompensation(
        operationIdentity,
        receipt,
        succeeded: true,
      );
      if (completed != FileMutationCompensationDisposition.reverted) {
        state.markEffectUncertain();
        return false;
      }
      _appliedReceipt = null;
      return true;
    } catch (_) {
      _effectCoordinator.completeCompensation(
        operationIdentity,
        receipt,
        succeeded: false,
      );
      state.markEffectUncertain();
      return false;
    }
  }
}
