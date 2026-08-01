part of 'create_routine_tool_runtime_adapter.dart';

extension on _CreateRoutineRuntimeBridge {
  Future<McpToolResult> _releasePreparedSuccess(
    CreateRoutineSuccessIdentity identity,
    CreateRoutineReceiptIdentity receipt,
    McpToolResult result,
  ) async {
    final release = await releaseCreateRoutineSuccess(
      _releaseSuccess,
      identity,
    );
    if (release == CreateRoutineSuccessReleaseResult.released) return result;
    if (release == CreateRoutineSuccessReleaseResult.boundaryMismatch) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      return _compensateUnsettledReceipt(receipt);
    }
    return _reconcileUncertainRelease(identity, receipt, result);
  }

  Future<McpToolResult> _reconcileUncertainRelease(
    CreateRoutineSuccessIdentity identity,
    CreateRoutineReceiptIdentity receipt,
    McpToolResult result,
  ) async {
    try {
      final acknowledgement = await _recordSuccess(identity);
      if (acknowledgement.identity != identity) {
        _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      } else if (acknowledgement.disposition ==
          CreateRoutineSuccessDisposition.released) {
        return result;
      }
    } catch (_) {
      markEffectUncertain();
    }
    return _compensateUnsettledReceipt(receipt);
  }

  Future<McpToolResult> _compensateUnsettledReceipt(
    CreateRoutineReceiptIdentity receipt, {
    String? failureMessage,
    bool ownerExpired = false,
  }) async {
    try {
      final acknowledgement = await _compensate(receipt);
      if (acknowledgement.receiptIdentity != receipt) {
        _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
        return _uncertainSettlement();
      }
      if (acknowledgement.disposition ==
              CreateRoutineCompensationDisposition.reverted ||
          acknowledgement.disposition ==
              CreateRoutineCompensationDisposition.alreadyAbsent) {
        if (ownerExpired) {
          _observation.observe(CreateRoutineRuntimeDisposition.ownerExpired);
        }
        return createRoutineRuntimeFailure(
          failureMessage ??
              (ownerExpired
                  ? 'The create_routine turn expired.'
                  : 'Routine creation receipt settlement failed.'),
        );
      }
      markEffectUncertain();
      return _uncertainSettlement();
    } catch (_) {
      markEffectUncertain();
      return _uncertainSettlement();
    }
  }

  McpToolResult _uncertainSettlement() {
    markEffectUncertain();
    return createRoutineRuntimeFailure(
      'Routine creation may still be persisted because its final receipt '
      'could not be settled; inspect scheduled routines before retrying.',
    );
  }
}
