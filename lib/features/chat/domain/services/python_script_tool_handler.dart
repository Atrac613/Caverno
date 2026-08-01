import '../entities/mcp_tool_entity.dart';
import 'python_script_tool_contract.dart';
import 'python_staging_lease_registry.dart';

export 'python_script_tool_contract.dart';

// ChatNotifier decomposition collaborator: python-script-tool-handler

/// Coordinates Python validation, owner attachment staging, and execution.
final class PythonScriptToolHandler {
  const PythonScriptToolHandler({
    required PythonInputStagingPort stagingPort,
    required PythonScriptExecutionPort executionPort,
    required PythonScriptApprovalPort approvalPort,
    required PythonStagingLeaseRegistry stagingLeases,
  }) : _stagingPort = stagingPort,
       _executionPort = executionPort,
       _approvalPort = approvalPort,
       _stagingLeases = stagingLeases;

  static const missingCodeMessage =
      'code is required; call run_python_script again with a complete '
      'Python script in the code argument. Use caverno.inputs[0] for '
      'attached files when analyzing attachments.';

  final PythonInputStagingPort _stagingPort;
  final PythonScriptExecutionPort _executionPort;
  final PythonScriptApprovalPort _approvalPort;
  final PythonStagingLeaseRegistry _stagingLeases;

  Future<McpToolResult> handle(PythonScriptToolRequest request) async {
    if (request.toolName != PythonScriptToolRequest.canonicalToolName) {
      return PythonToolResults.failure(
        request.toolName,
        'Unsupported Python tool',
      );
    }
    if (request.code.isEmpty) {
      return PythonToolResults.failure(request.toolName, missingCodeMessage);
    }

    final attempt = request.attempt;
    final initialExpiry = _expiryState(request, attempt);
    if (initialExpiry.expired) {
      return initialExpiry.result ?? PythonToolResults.expiredBefore(request);
    }
    final approvalKey = PythonScriptApprovalKey(request.code);
    final cached = _approvalPort.lookupDenial(attempt, approvalKey);
    if (PythonCompletionFence.expired(
      cached,
      request,
      'Python denial cache lookup',
    )) {
      return PythonToolResults.expiredBefore(request);
    }
    if (cached.value case final denial?) {
      return PythonCompletionFence.validResult(request, denial);
    }

    final reservation = _stagingLeases.reserve(attempt);
    if (!reservation.isReserved) {
      return reservation.status == PythonStagingReserveStatus.ownerCleared
          ? PythonToolResults.expiredBefore(request)
          : PythonToolResults.failure(
              request.toolName,
              'Python input staging is already active for this tool call',
            );
    }

    final token = reservation.token!;
    final cleanupClaims = <PythonStagingCleanupClaim>[];
    PythonStagingAllocation? firstAllocation;
    PythonStagingLease? activeLease;
    StateError? allocationError;
    var acceptingAllocations = true;
    var executionStarted = false;
    PythonStagedHandlerOutcome? outcome;
    Object? primaryError;
    StackTrace? primaryStackTrace;
    Object? cleanupError;
    StackTrace? cleanupStackTrace;

    PythonStagingAllocationAcknowledgement onAllocated(
      PythonStagingAllocation allocation,
    ) {
      if (!acceptingAllocations) {
        final alreadyTracked =
            firstAllocation?.directoryIdentity == allocation.directoryIdentity;
        return PythonStagingAllocationAcknowledgement(
          alreadyTracked
              ? PythonStagingAllocationDisposition.rejectedHandlerCleanup
              : PythonStagingAllocationDisposition.rejectedPortCleanup,
        );
      }
      final repeated = firstAllocation != null;
      firstAllocation ??= allocation;
      final commit = _stagingLeases.commit(
        attempt: attempt,
        token: token,
        directoryIdentity: allocation.directoryIdentity,
        metadata: {'inputCount': allocation.stagedInputs.inputs.length},
      );
      var disposition = PythonStagingAllocationDisposition.rejectedPortCleanup;
      if (commit.activeLease case final lease?) {
        activeLease ??= lease;
        if (!identical(activeLease, lease)) {
          allocationError ??= StateError(
            'Python input staging replaced its active lease.',
          );
        }
        disposition = PythonStagingAllocationDisposition.accepted;
      } else if (commit.cleanupClaim case final claim?) {
        cleanupClaims.add(claim);
        disposition = PythonStagingAllocationDisposition.rejectedHandlerCleanup;
      } else if (commit.status ==
          PythonStagingCommitStatus.cleanupAlreadyClaimed) {
        disposition = PythonStagingAllocationDisposition.rejectedHandlerCleanup;
      } else {
        allocationError ??= StateError(
          'Python input staging lease commit failed: ${commit.status.name}.',
        );
      }
      if (repeated) {
        allocationError ??= StateError(
          'Python input staging reported more than one allocation.',
        );
      }
      return PythonStagingAllocationAcknowledgement(disposition);
    }

    try {
      final staging = await _stagingPort.stage(
        attempt,
        token,
        request.latestEligibleAttachment,
        onAllocated,
      );
      if (PythonCompletionFence.expired(
        staging,
        request,
        'Python input staging',
      )) {
        outcome = _beforeOutcome(request);
      } else {
        if (firstAllocation == null) {
          throw StateError(
            'Python input staging settled before reporting its allocation.',
          );
        }
        if (allocationError case final error?) throw error;
        if (activeLease == null ||
            !_stagingLeases.isLeaseCurrent(attempt: attempt, token: token)) {
          outcome = _beforeOutcome(request);
        } else {
          outcome = await _runStaged(
            request: request,
            attempt: attempt,
            token: token,
            approvalKey: approvalKey,
            allocation: firstAllocation!,
            onExecutionStarted: () => executionStarted = true,
          );
        }
      }
    } catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    } finally {
      acceptingAllocations = false;
      try {
        await _cleanup(
          request: request,
          attempt: attempt,
          token: token,
          activeLease: activeLease,
          queuedClaims: cleanupClaims,
        );
      } catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      }
    }

    if (executionStarted && (primaryError != null || cleanupError != null)) {
      return PythonToolResults.expiredAfter(request);
    }
    if (primaryError case final error?) {
      Error.throwWithStackTrace(error, primaryStackTrace!);
    }
    if (cleanupError case final error?) {
      Error.throwWithStackTrace(error, cleanupStackTrace!);
    }
    final completed = outcome;
    if (completed == null) {
      throw StateError('Python staging finished without an outcome.');
    }
    if (!completed.executed || completed.effectsUncertain) {
      return completed.result;
    }
    return _finishExecutedOutcome(
      request: request,
      attempt: attempt,
      key: approvalKey,
      outcome: completed,
    );
  }

  Future<PythonStagedHandlerOutcome> _runStaged({
    required PythonScriptToolRequest request,
    required PythonStagingAttempt attempt,
    required PythonStagingLeaseToken token,
    required PythonScriptApprovalKey approvalKey,
    required PythonStagingAllocation allocation,
    required void Function() onExecutionStarted,
  }) async {
    final approvalRequest = PythonScriptApprovalRequest(
      toolRequest: request,
      key: approvalKey,
      stagedInputs: allocation.stagedInputs,
    );
    final gateCompletion = await _approvalPort.resolveGate(
      attempt,
      approvalRequest,
    );
    if (PythonCompletionFence.expired(
      gateCompletion,
      request,
      'Python approval gate',
    )) {
      return _beforeOutcome(request);
    }
    final gate = PythonCompletionFence.requiredValue(
      gateCompletion,
      'Python approval gate',
    );
    final gateExpiry = _expiryBeforeExecution(request, attempt, token);
    if (gateExpiry != null) {
      return PythonStagedHandlerOutcome.before(gateExpiry);
    }

    if (gate.isDenied) {
      return PythonStagedHandlerOutcome.before(
        _rememberDenial(
          request: request,
          attempt: attempt,
          token: token,
          key: approvalKey,
          result: PythonToolResults.autoReviewDenied(
            request.toolName,
            gate.deniedRationale!,
          ),
        ),
      );
    }
    if (gate.needsManual) {
      final manual = await _approvalPort.requestManualApproval(
        attempt,
        approvalRequest,
      );
      if (PythonCompletionFence.expired(
        manual,
        request,
        'Python manual approval',
      )) {
        return _beforeOutcome(request);
      }
      final allowed = PythonCompletionFence.requiredValue(
        manual,
        'Python manual approval',
      );
      final manualExpiry = _expiryBeforeExecution(request, attempt, token);
      if (manualExpiry != null) {
        return PythonStagedHandlerOutcome.before(manualExpiry);
      }
      if (!allowed) {
        return PythonStagedHandlerOutcome.before(
          _rememberDenial(
            request: request,
            attempt: attempt,
            token: token,
            key: approvalKey,
            result: PythonToolResults.failure(
              request.toolName,
              'User denied Python script execution',
            ),
          ),
        );
      }
    }

    final executionExpiry = _expiryBeforeExecution(request, attempt, token);
    if (executionExpiry != null) {
      return PythonStagedHandlerOutcome.before(executionExpiry);
    }
    onExecutionStarted();
    final execution = await _executionPort.execute(
      attempt,
      PythonScriptExecutionRequest(
        code: request.code,
        allocation: allocation,
        timeoutSeconds: request.arguments['timeout_seconds'],
      ),
    );
    if (PythonCompletionFence.expired(execution, request, 'Python execution') ||
        !_stagingLeases.isLeaseCurrent(attempt: attempt, token: token)) {
      return _afterOutcome(request);
    }
    final result = PythonCompletionFence.validResult(
      request,
      PythonCompletionFence.requiredValue(execution, 'Python execution'),
    );
    if (_expiryState(request, attempt).expired) {
      return _afterOutcome(request);
    }
    return PythonStagedHandlerOutcome.executed(
      result,
      cacheResult: !gate.bypassedApproval,
    );
  }

  Future<McpToolResult> _finishExecutedOutcome({
    required PythonScriptToolRequest request,
    required PythonStagingAttempt attempt,
    required PythonScriptApprovalKey key,
    required PythonStagedHandlerOutcome outcome,
  }) async {
    try {
      if (_expiryState(request, attempt).expired) {
        return PythonToolResults.expiredAfter(request);
      }
      if (!outcome.cacheResult) return outcome.result;
      final remembered = _approvalPort.rememberResult(
        attempt,
        key,
        outcome.result,
      );
      return PythonCompletionFence.expired(
            remembered,
            request,
            'Python result cache write',
          )
          ? PythonToolResults.expiredAfter(request)
          : outcome.result;
    } catch (_) {
      return PythonToolResults.expiredAfter(request);
    }
  }

  McpToolResult _rememberDenial({
    required PythonScriptToolRequest request,
    required PythonStagingAttempt attempt,
    required PythonStagingLeaseToken token,
    required PythonScriptApprovalKey key,
    required McpToolResult result,
  }) {
    final expiry = _expiryBeforeExecution(request, attempt, token);
    if (expiry != null) return expiry;
    final remembered = _approvalPort.rememberDenial(attempt, key, result);
    return PythonCompletionFence.expired(
          remembered,
          request,
          'Python denial cache write',
        )
        ? PythonToolResults.expiredBefore(request)
        : result;
  }

  Future<void> _cleanup({
    required PythonScriptToolRequest request,
    required PythonStagingAttempt attempt,
    required PythonStagingLeaseToken token,
    required PythonStagingLease? activeLease,
    required List<PythonStagingCleanupClaim> queuedClaims,
  }) async {
    final claims = <PythonStagingCleanupClaim>[...queuedClaims];
    if (activeLease != null) {
      final claimed = _stagingLeases.claimCleanup(
        attempt: attempt,
        token: token,
      );
      if (claimed.status == PythonStagingCleanupClaimStatus.claimed) {
        claims.add(claimed.claim!);
      } else if (claimed.status !=
              PythonStagingCleanupClaimStatus.alreadyClaimed &&
          claimed.status != PythonStagingCleanupClaimStatus.alreadySettled) {
        throw StateError(
          'Python input cleanup claim failed: ${claimed.status.name}.',
        );
      }
    } else if (claims.isEmpty) {
      final released = _stagingLeases.releaseReservation(
        attempt: attempt,
        token: token,
      );
      if (released != PythonStagingReservationReleaseStatus.cancelled &&
          released != PythonStagingReservationReleaseStatus.alreadyReleased) {
        throw StateError(
          'Python staging reservation settlement failed: ${released.name}.',
        );
      }
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final claim in claims) {
      var succeeded = false;
      try {
        final completion = await _stagingPort.release(claim);
        if (PythonCompletionFence.expired(
          completion,
          request,
          'Python input cleanup',
        )) {
          throw StateError('Python input cleanup did not complete.');
        }
        final cleanupOutcome = PythonCompletionFence.requiredValue(
          completion,
          'Python input cleanup',
        );
        if (!cleanupOutcome.isSettled) {
          throw StateError(
            'Python input cleanup failed: ${cleanupOutcome.name}.',
          );
        }
        succeeded = true;
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      } finally {
        final settled = _stagingLeases.settleCleanup(
          claim: claim,
          succeeded: succeeded,
        );
        final expected = succeeded
            ? PythonStagingCleanupSettleStatus.settled
            : PythonStagingCleanupSettleStatus.reopened;
        if (settled != expected && firstError == null) {
          firstError = StateError(
            'Python input cleanup settlement failed: ${settled.name}.',
          );
          firstStackTrace = StackTrace.current;
        }
      }
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  McpToolResult? _expiryBeforeExecution(
    PythonScriptToolRequest request,
    PythonStagingAttempt attempt,
    PythonStagingLeaseToken token,
  ) {
    if (!_stagingLeases.isLeaseCurrent(attempt: attempt, token: token)) {
      return PythonToolResults.expiredBefore(request);
    }
    final expiry = _expiryState(request, attempt);
    return expiry.expired
        ? expiry.result ?? PythonToolResults.expiredBefore(request)
        : null;
  }

  ({bool expired, McpToolResult? result}) _expiryState(
    PythonScriptToolRequest request,
    PythonStagingAttempt attempt,
  ) {
    final completion = _approvalPort.expiredResult(attempt);
    final ownerExpired = PythonCompletionFence.expired(
      completion,
      request,
      'Python expiration probe',
    );
    final result = completion.value;
    return (
      expired: ownerExpired || result != null,
      result: result == null
          ? null
          : PythonCompletionFence.validResult(request, result),
    );
  }

  PythonStagedHandlerOutcome _beforeOutcome(PythonScriptToolRequest request) =>
      PythonStagedHandlerOutcome.before(
        PythonToolResults.expiredBefore(request),
      );

  PythonStagedHandlerOutcome _afterOutcome(PythonScriptToolRequest request) =>
      PythonStagedHandlerOutcome.uncertain(
        PythonToolResults.expiredAfter(request),
      );
}
