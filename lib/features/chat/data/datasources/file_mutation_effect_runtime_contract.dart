part of 'file_mutation_runtime_contract.dart';

/// Captured before-state paired with replacement-resistant evidence.
final class FileMutationRollbackCapture<Snapshot extends Object> {
  FileMutationRollbackCapture({
    required this.identity,
    required this.snapshot,
    required String beforeFingerprint,
    required String compensationToken,
  }) : beforeFingerprint = _requiredExact(
         beforeFingerprint,
         'beforeFingerprint',
       ),
       compensationToken = _requiredExact(
         compensationToken,
         'compensationToken',
       );

  final FileMutationRuntimeIdentity identity;
  final Snapshot snapshot;
  final String beforeFingerprint;
  final String compensationToken;
}

final class FileMutationRollbackRecordRequest<Snapshot extends Object> {
  const FileMutationRollbackRecordRequest({
    required this.capture,
    required this.expectedAfterFingerprint,
  });

  final FileMutationRollbackCapture<Snapshot> capture;
  final String expectedAfterFingerprint;

  FileMutationRuntimeIdentity get identity => capture.identity;
}

final class FileMutationRollbackRecordReceipt {
  FileMutationRollbackRecordReceipt({
    required this.identity,
    required String compensationToken,
    required String recordToken,
  }) : compensationToken = _requiredExact(
         compensationToken,
         'compensationToken',
       ),
       recordToken = _requiredExact(recordToken, 'recordToken');

  final FileMutationRuntimeIdentity identity;
  final String compensationToken;
  final String recordToken;
}

final class FileMutationEffectRequest<Snapshot extends Object> {
  FileMutationEffectRequest({
    required this.operationRequest,
    required this.capture,
  }) {
    if (capture.identity != operationRequest.identity) {
      throw ArgumentError('File mutation capture identity mismatch.');
    }
  }

  final FileMutationRuntimeOperationRequest operationRequest;
  final FileMutationRollbackCapture<Snapshot> capture;

  FileMutationRuntimeIdentity get identity => operationRequest.identity;
}

/// Single-use handoff that must run immediately before raw mutation start.
final class FileMutationEffectAuthorization {
  FileMutationEffectAuthorization({
    required this.identity,
    required bool Function() beginEffect,
  }) : _beginEffect = beginEffect;

  final FileMutationRuntimeIdentity identity;
  final bool Function() _beginEffect;
  bool _attempted = false;
  bool _started = false;

  bool beginEffectHandoff() {
    if (_attempted) return false;
    _attempted = true;
    return _started = _beginEffect();
  }

  bool get attempted => _attempted;
  bool get started => _started;
}

enum FileMutationRawEffectDisposition { noEffect, applied, partialOrUnknown }

final class FileMutationEffectPostcondition {
  FileMutationEffectPostcondition({
    required this.identity,
    required String afterFingerprint,
    required String compensationToken,
  }) : afterFingerprint = _requiredExact(afterFingerprint, 'afterFingerprint'),
       compensationToken = _requiredExact(
         compensationToken,
         'compensationToken',
       );

  final FileMutationRuntimeIdentity identity;
  final String afterFingerprint;
  final String compensationToken;
}

final class FileMutationExecutionAcknowledgement {
  const FileMutationExecutionAcknowledgement({
    required this.identity,
    required this.result,
    required this.effectDisposition,
    this.postcondition,
  });

  final FileMutationRuntimeIdentity identity;
  final McpToolResult result;
  final FileMutationRawEffectDisposition effectDisposition;
  final FileMutationEffectPostcondition? postcondition;
}

final class FileMutationCompensationRequest<Snapshot extends Object> {
  const FileMutationCompensationRequest({
    required this.capture,
    required this.expectedAfterFingerprint,
    required this.recordToken,
  });

  final FileMutationRollbackCapture<Snapshot> capture;
  final String expectedAfterFingerprint;
  final String? recordToken;

  FileMutationRuntimeIdentity get identity => capture.identity;
}

enum FileMutationRuntimeCompensationDisposition {
  reverted,
  fingerprintConflict,
  failed,
  effectUncertain,
}

final class FileMutationCompensationAcknowledgement {
  const FileMutationCompensationAcknowledgement({
    required this.identity,
    required this.compensationToken,
    required this.disposition,
    this.message,
  });

  final FileMutationRuntimeIdentity identity;
  final String compensationToken;
  final FileMutationRuntimeCompensationDisposition disposition;
  final String? message;
}
