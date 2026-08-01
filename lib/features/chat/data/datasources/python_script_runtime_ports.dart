import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/python_script_tool_contract.dart';
import '../../domain/services/python_staging_lease_registry.dart';
import 'python_execution_authority.dart';
import 'python_script_runtime_contract.dart';

part 'python_script_runtime_approval_ports.dart';
part 'python_script_runtime_execution_settlement.dart';

/// Bound handler ports for one exact Python runtime identity.
final class PythonScriptRuntimePorts
    implements PythonInputStagingPort, PythonScriptExecutionPort {
  PythonScriptRuntimePorts({
    required this.identity,
    required PythonRuntimeLifecycleCallback acknowledgeLifecycle,
    required PythonRuntimeStagingCallback stage,
    required PythonRuntimeCleanupCallback cleanup,
    required PythonRuntimeDenialLookupCallback lookupDenial,
    required PythonRuntimeGateCallback resolveGate,
    required PythonRuntimeManualApprovalCallback requestManualApproval,
    required PythonRuntimeCacheWriteCallback rememberDenial,
    required PythonRuntimeCacheWriteCallback rememberResult,
    required PythonRuntimeExecutionCallback execute,
    required PythonScriptExecutionAuthority executionAuthority,
  }) : _acknowledgeLifecycle = acknowledgeLifecycle,
       _stage = stage,
       _cleanup = cleanup,
       _execute = execute,
       _executionAuthority = executionAuthority {
    approvalPort = PythonScriptApprovalRuntimePorts._(
      this,
      lookupDenial: lookupDenial,
      resolveGate: resolveGate,
      requestManualApproval: requestManualApproval,
      rememberDenial: rememberDenial,
      rememberResult: rememberResult,
    );
  }

  final PythonScriptRuntimeIdentity identity;
  final PythonRuntimeLifecycleCallback _acknowledgeLifecycle;
  final PythonRuntimeStagingCallback _stage;
  final PythonRuntimeCleanupCallback _cleanup;
  final PythonRuntimeExecutionCallback _execute;
  final PythonScriptExecutionAuthority _executionAuthority;
  late final PythonScriptApprovalPort approvalPort;

  PythonScriptRuntimeDisposition? _observedDisposition;
  bool _stagingEffectActive = false;
  bool? _resultCacheRequired;
  bool _executionCleanupAccepted = false;
  bool _executionReleased = false;
  bool _preEffectExecutionRejected = false;
  PythonScriptExecutionEffectPermit? _executionPermit;
  PythonExecutionRuntimeIdentity? _executionIdentity;
  McpToolResult? _acceptedExecutionResult;

  @override
  Future<PythonScriptCompletion<Object?>> stage(
    PythonStagingAttempt attempt,
    PythonStagingLeaseToken token,
    PythonInputAttachment? attachment,
    PythonStagingAllocationCallback onAllocated,
  ) async {
    if (!_attemptMatches(attempt)) {
      _observeMismatch();
      return _expired<Object?>();
    }
    if (_lifecycleDisposition() != null) return _expired<Object?>();

    final acknowledgement = await _captureStaging(
      PythonRuntimeStagingRequest(
        identity: identity,
        attempt: attempt,
        attachment: attachment,
      ),
    );
    if (acknowledgement == null) return _expired<Object?>();
    if (acknowledgement.identity != identity) {
      markEffectUncertain();
      return _expired<Object?>();
    }
    final allocation = acknowledgement.value;
    if (acknowledgement.disposition !=
        PythonRuntimeAcknowledgementDisposition.completed) {
      _observeAcknowledgement(acknowledgement.disposition);
      if (allocation != null) {
        _stagingEffectActive = true;
        await _cleanupAllocation(attempt, allocation);
      }
      return _expired<Object?>();
    }
    if (allocation == null) {
      markEffectUncertain();
      return _expired<Object?>();
    }

    _stagingEffectActive = true;
    final PythonStagingAllocationAcknowledgement transfer;
    try {
      transfer = onAllocated(allocation);
    } catch (_) {
      markEffectUncertain();
      rethrow;
    }
    if (transfer.portMustCleanup) {
      await _cleanupAllocation(attempt, allocation);
    }
    if (!transfer.isAccepted) {
      _observe(PythonScriptRuntimeDisposition.rejected);
    }
    if (_lifecycleDisposition() != null) return _expired<Object?>();
    return _completed<Object?>(null);
  }

  @override
  Future<PythonScriptCompletion<PythonStagingCleanupOutcome>> release(
    PythonStagingCleanupClaim claim,
  ) async {
    final lease = claim.lease;
    if (!_attemptMatches(lease.attempt)) {
      markEffectUncertain();
      return _completed(PythonStagingCleanupOutcome.identityMismatch);
    }
    final outcome = await _cleanupExact(
      PythonStagingCleanupIdentity(
        runtime: identity,
        attempt: lease.attempt,
        directoryIdentity: lease.directoryIdentity,
      ),
    );
    return _completed(outcome);
  }

  @override
  Future<PythonScriptCompletion<McpToolResult>> execute(
    PythonStagingAttempt attempt,
    PythonScriptExecutionRequest request,
  ) async {
    if (!_attemptMatches(attempt)) {
      _observeMismatch();
      return _expired<McpToolResult>();
    }
    if (_lifecycleDisposition() != null) {
      return _expired<McpToolResult>();
    }
    final executionIdentity = PythonExecutionRuntimeIdentity(
      runtime: identity,
      directoryIdentity: request.directoryIdentity,
      arguments: request.arguments,
    );
    final reservation = _executionAuthority.reserve(
      owner: identity.owner,
      identity: executionIdentity,
      ownerIsCurrent: _ownerIsCurrentForPermit,
    );
    final permit = reservation.permit;
    if (permit == null) {
      if (reservation.disposition ==
          PythonExecutionReservationDisposition.ownerExpired) {
        _observe(PythonScriptRuntimeDisposition.ownerExpired);
      } else {
        markEffectUncertain();
      }
      return _expired<McpToolResult>();
    }
    _executionPermit = permit;
    _executionIdentity = executionIdentity;
    final runtimeRequest = PythonRuntimeExecutionRequest(
      identity: executionIdentity,
      arguments: request.arguments,
      effectPermit: permit,
    );
    final PythonRuntimeAcknowledgement<
      PythonExecutionRuntimeIdentity,
      McpToolResult
    >
    acknowledgement;
    try {
      acknowledgement = await _execute(runtimeRequest);
    } on PythonExecutionEffectPermitExpired {
      _executionAuthority.abandonBeforeEffect(permit);
      _observe(PythonScriptRuntimeDisposition.ownerExpired);
      return _expired<McpToolResult>();
    } catch (_) {
      _retainExecutionRecovery();
      return _expired<McpToolResult>();
    }
    if (acknowledgement.identity != executionIdentity) {
      _retainExecutionRecovery();
      return _expired<McpToolResult>();
    }
    switch (acknowledgement.disposition) {
      case PythonRuntimeAcknowledgementDisposition.completed:
        break;
      case PythonRuntimeAcknowledgementDisposition.rejected:
        final failure = acknowledgement.value;
        if (failure != null &&
            (failure.isSuccess || failure.toolName != identity.toolName)) {
          _retainExecutionRecovery();
          return _expired<McpToolResult>();
        }
        final rejection =
            failure != null &&
                !failure.isSuccess &&
                failure.toolName == identity.toolName
            ? failure
            : pythonRuntimeFailure(
                identity.toolName,
                PythonScriptRuntimeDisposition.rejected,
                acknowledgement.message ?? 'Python execution was rejected.',
              );
        if (permit.receipt == null) {
          _executionAuthority.abandonBeforeEffect(permit);
          _preEffectExecutionRejected = true;
          _observe(PythonScriptRuntimeDisposition.rejected);
          return _completed(rejection);
        }
        _acceptedExecutionResult = rejection;
        break;
      case PythonRuntimeAcknowledgementDisposition.ownerExpired:
        if (permit.receipt == null) {
          _executionAuthority.abandonBeforeEffect(permit);
          _observe(PythonScriptRuntimeDisposition.ownerExpired);
        } else {
          _retainExecutionRecovery();
        }
        return _expired<McpToolResult>();
      case PythonRuntimeAcknowledgementDisposition.effectUncertain:
        _retainExecutionRecovery();
        return _expired<McpToolResult>();
    }
    final result = _acceptedExecutionResult ?? acknowledgement.value;
    if (result == null || result.toolName != identity.toolName) {
      _retainExecutionRecovery();
      return _expired<McpToolResult>();
    }
    if (permit.receipt == null) {
      _retainExecutionRecovery();
      return _expired<McpToolResult>();
    }
    if (_lifecycleDisposition() != null) {
      _retainExecutionRecovery();
      return _expired<McpToolResult>();
    }
    if (!_executionAuthority.acknowledgeExecution(permit)) {
      _retainExecutionRecovery();
      return _expired<McpToolResult>();
    }
    _acceptedExecutionResult = result;
    return _completed(result);
  }

  Future<
    PythonRuntimeAcknowledgement<
      PythonScriptRuntimeIdentity,
      PythonStagingAllocation
    >?
  >
  _captureStaging(PythonRuntimeStagingRequest request) async {
    try {
      return await _stage(request);
    } catch (_) {
      markEffectUncertain();
      return null;
    }
  }

  Future<void> _cleanupAllocation(
    PythonStagingAttempt attempt,
    PythonStagingAllocation allocation,
  ) async {
    await _cleanupExact(
      PythonStagingCleanupIdentity(
        runtime: identity,
        attempt: attempt,
        directoryIdentity: allocation.directoryIdentity,
      ),
    );
  }

  Future<PythonStagingCleanupOutcome> _cleanupExact(
    PythonStagingCleanupIdentity cleanupIdentity,
  ) async {
    final PythonRuntimeAcknowledgement<
      PythonStagingCleanupIdentity,
      PythonStagingCleanupOutcome
    >
    acknowledgement;
    try {
      acknowledgement = await _cleanup(
        PythonRuntimeCleanupRequest(identity: cleanupIdentity),
      );
    } catch (_) {
      markEffectUncertain();
      return PythonStagingCleanupOutcome.failed;
    }
    if (acknowledgement.identity != cleanupIdentity) {
      markEffectUncertain();
      return PythonStagingCleanupOutcome.identityMismatch;
    }
    if (acknowledgement.disposition !=
        PythonRuntimeAcknowledgementDisposition.completed) {
      markEffectUncertain();
      return PythonStagingCleanupOutcome.failed;
    }
    final outcome = acknowledgement.value ?? PythonStagingCleanupOutcome.failed;
    if (outcome.isSettled) {
      _stagingEffectActive = false;
      _acknowledgeExecutionCleanup(cleanupIdentity);
    } else {
      markEffectUncertain();
    }
    return outcome;
  }

  PythonScriptRuntimeDisposition? _lifecycleDisposition() {
    final PythonRuntimeAcknowledgement<PythonScriptRuntimeIdentity, Object?>
    acknowledgement;
    try {
      acknowledgement = _acknowledgeLifecycle(identity);
    } catch (_) {
      markEffectUncertain();
      return PythonScriptRuntimeDisposition.effectUncertain;
    }
    if (acknowledgement.identity != identity) {
      if (_executionPermit?.receipt != null) {
        _retainExecutionRecovery();
      } else {
        _observeMismatch();
      }
      return _observedDisposition;
    }
    if (acknowledgement.disposition ==
        PythonRuntimeAcknowledgementDisposition.completed) {
      return null;
    }
    _observeAcknowledgement(acknowledgement.disposition);
    if (_executionPermit?.receipt != null) {
      _retainExecutionRecovery();
    }
    return _observedDisposition;
  }

  bool _ownerIsCurrentForPermit() {
    try {
      final acknowledgement = _acknowledgeLifecycle(identity);
      return acknowledgement.identity == identity &&
          acknowledgement.disposition ==
              PythonRuntimeAcknowledgementDisposition.completed;
    } catch (_) {
      return false;
    }
  }

  bool _attemptMatches(PythonStagingAttempt attempt) {
    return attempt.owner == identity.owner &&
        attempt.toolCallId == identity.toolCallId &&
        attempt.toolName == identity.toolName;
  }

  PythonScriptCompletion<T> _completed<T>(T value) {
    return PythonScriptCompletion.completed(
      owner: identity.owner,
      toolCallId: identity.toolCallId,
      toolName: identity.toolName,
      value: value,
    );
  }

  PythonScriptCompletion<T> _expired<T>() {
    return PythonScriptCompletion.ownerExpired(
      owner: identity.owner,
      toolCallId: identity.toolCallId,
      toolName: identity.toolName,
    );
  }

  PythonScriptRuntimeDisposition classify(McpToolResult result) {
    if (_executionPermit?.receipt != null && !_executionReleased) {
      _retainExecutionRecovery();
      return PythonScriptRuntimeDisposition.effectUncertain;
    }
    return _observedDisposition ??
        (result.isSuccess
            ? PythonScriptRuntimeDisposition.completed
            : PythonScriptRuntimeDisposition.rejected);
  }

  PythonScriptRuntimeDisposition classifyUnhandledError() {
    if (_executionPermit?.receipt != null) {
      _retainExecutionRecovery();
      return PythonScriptRuntimeDisposition.effectUncertain;
    }
    if (_stagingEffectActive ||
        _observedDisposition ==
            PythonScriptRuntimeDisposition.effectUncertain) {
      return PythonScriptRuntimeDisposition.effectUncertain;
    }
    return _observedDisposition ?? PythonScriptRuntimeDisposition.rejected;
  }

  void markEffectUncertain() {
    if (_executionPermit != null) {
      _executionAuthority.retainRecovery(_executionPermit!);
    }
    _observe(PythonScriptRuntimeDisposition.effectUncertain);
  }

  void _observeMismatch() {
    _observe(
      _executionPermit?.receipt != null || _stagingEffectActive
          ? PythonScriptRuntimeDisposition.effectUncertain
          : PythonScriptRuntimeDisposition.rejected,
    );
  }

  void _observeAcknowledgement(
    PythonRuntimeAcknowledgementDisposition disposition,
  ) {
    _observe(switch (disposition) {
      PythonRuntimeAcknowledgementDisposition.completed =>
        PythonScriptRuntimeDisposition.completed,
      PythonRuntimeAcknowledgementDisposition.rejected =>
        PythonScriptRuntimeDisposition.rejected,
      PythonRuntimeAcknowledgementDisposition.ownerExpired =>
        PythonScriptRuntimeDisposition.ownerExpired,
      PythonRuntimeAcknowledgementDisposition.effectUncertain =>
        PythonScriptRuntimeDisposition.effectUncertain,
    });
  }

  void _observe(PythonScriptRuntimeDisposition disposition) {
    if (disposition == PythonScriptRuntimeDisposition.completed) return;
    final current = _observedDisposition;
    if (current == PythonScriptRuntimeDisposition.effectUncertain) return;
    if (disposition == PythonScriptRuntimeDisposition.effectUncertain ||
        current == null ||
        (current == PythonScriptRuntimeDisposition.rejected &&
            disposition == PythonScriptRuntimeDisposition.ownerExpired)) {
      _observedDisposition = disposition;
    }
  }
}
