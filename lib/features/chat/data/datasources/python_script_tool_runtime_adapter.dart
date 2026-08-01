import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/python_script_tool_handler.dart';
import '../../domain/services/python_staging_lease_registry.dart';
import 'python_script_runtime_contract.dart';
import 'python_script_runtime_ports.dart';

export 'python_execution_authority.dart';
export 'python_input_staging_runtime_adapter.dart';
export 'python_script_runtime_contract.dart';
export '../../domain/services/python_staging_lease_registry.dart';

/// Summary of one owner or runtime-wide Python staging retirement.
final class PythonStagingRuntimeRetirementResult {
  PythonStagingRuntimeRetirementResult({
    required this.retiredReservationCount,
    required this.cleanupClaimCount,
    required this.settledCleanupCount,
    required Iterable<PythonStagingAttempt> outstandingCleanupAttempts,
    this.executionRecoveryReceipt,
  }) : outstandingCleanupAttempts = List.unmodifiable(
         outstandingCleanupAttempts,
       );

  final int retiredReservationCount;
  final int cleanupClaimCount;
  final int settledCleanupCount;
  final List<PythonStagingAttempt> outstandingCleanupAttempts;
  final PythonScriptExecutionRecoveryReceipt? executionRecoveryReceipt;

  int get failedCleanupCount => cleanupClaimCount - settledCleanupCount;

  bool get cleanupSettled =>
      failedCleanupCount == 0 && outstandingCleanupAttempts.isEmpty;
}

/// Production callback bridge for one exact owner-bound Python tool call.
final class PythonScriptToolRuntimeAdapter {
  PythonScriptToolRuntimeAdapter({
    required PythonOwnerMessagesCallback resolveOwnerMessages,
    required PythonRuntimeLifecycleCallback acknowledgeLifecycle,
    required PythonRuntimeStagingCallback stage,
    required PythonRuntimeCleanupCallback cleanup,
    required PythonRuntimeDenialLookupCallback lookupDenial,
    required PythonRuntimeGateCallback resolveGate,
    required PythonRuntimeManualApprovalCallback requestManualApproval,
    required PythonRuntimeCacheWriteCallback rememberDenial,
    required PythonRuntimeCacheWriteCallback rememberResult,
    required PythonRuntimeExecutionCallback execute,
    required PythonStagingLeaseRegistry stagingLeases,
    required PythonScriptExecutionAuthority executionAuthority,
  }) : _resolveOwnerMessages = resolveOwnerMessages,
       _acknowledgeLifecycle = acknowledgeLifecycle,
       _stage = stage,
       _cleanup = cleanup,
       _lookupDenial = lookupDenial,
       _resolveGate = resolveGate,
       _requestManualApproval = requestManualApproval,
       _rememberDenial = rememberDenial,
       _rememberResult = rememberResult,
       _execute = execute,
       _stagingLeases = stagingLeases,
       _executionAuthority = executionAuthority;

  final PythonOwnerMessagesCallback _resolveOwnerMessages;
  final PythonRuntimeLifecycleCallback _acknowledgeLifecycle;
  final PythonRuntimeStagingCallback _stage;
  final PythonRuntimeCleanupCallback _cleanup;
  final PythonRuntimeDenialLookupCallback _lookupDenial;
  final PythonRuntimeGateCallback _resolveGate;
  final PythonRuntimeManualApprovalCallback _requestManualApproval;
  final PythonRuntimeCacheWriteCallback _rememberDenial;
  final PythonRuntimeCacheWriteCallback _rememberResult;
  final PythonRuntimeExecutionCallback _execute;
  final PythonStagingLeaseRegistry _stagingLeases;
  final PythonScriptExecutionAuthority _executionAuthority;
  final Map<PythonStagingAttempt, PythonScriptRuntimeIdentity>
  _runtimeIdentitiesByAttempt = {};

  Future<PythonScriptRuntimeCompletion> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) async {
    final input = PythonScriptRuntimeInput(owner: owner, toolCall: toolCall);
    final snapshot = _captureMessages(input.identity);
    final messages = snapshot.messages;
    final identity = PythonScriptRuntimeIdentity(
      invocation: input.identity,
      ownerMessages: messages,
    );
    if (snapshot.disposition case final disposition?) {
      return PythonScriptRuntimeCompletion(
        identity: identity,
        disposition: disposition,
        result: pythonRuntimeFailure(
          identity.toolName,
          disposition,
          snapshot.message,
        ),
      );
    }

    final attempt = PythonStagingAttempt(
      owner: identity.owner,
      toolCallId: identity.toolCallId,
      toolName: identity.toolName,
    );
    var installedRuntimeIdentity = false;
    _runtimeIdentitiesByAttempt.putIfAbsent(attempt, () {
      installedRuntimeIdentity = true;
      return identity;
    });
    final ports = PythonScriptRuntimePorts(
      identity: identity,
      acknowledgeLifecycle: _acknowledgeLifecycle,
      stage: _stage,
      cleanup: _cleanup,
      lookupDenial: _lookupDenial,
      resolveGate: _resolveGate,
      requestManualApproval: _requestManualApproval,
      rememberDenial: _rememberDenial,
      rememberResult: _rememberResult,
      execute: _execute,
      executionAuthority: _executionAuthority,
    );
    final handler = PythonScriptToolHandler(
      stagingPort: ports,
      executionPort: ports,
      approvalPort: ports.approvalPort,
      stagingLeases: _stagingLeases,
    );
    try {
      final result = await handler.handle(input.toToolRequest(messages));
      if (result.toolName != identity.toolName) {
        ports.markEffectUncertain();
        return PythonScriptRuntimeCompletion(
          identity: identity,
          disposition: PythonScriptRuntimeDisposition.effectUncertain,
          result: pythonRuntimeFailure(
            identity.toolName,
            PythonScriptRuntimeDisposition.effectUncertain,
            'The Python handler returned a mismatched tool result.',
          ),
        );
      }
      return PythonScriptRuntimeCompletion(
        identity: identity,
        disposition: ports.classify(result),
        result: result,
      );
    } catch (error) {
      final disposition = ports.classifyUnhandledError();
      return PythonScriptRuntimeCompletion(
        identity: identity,
        disposition: disposition,
        result: pythonRuntimeFailure(
          identity.toolName,
          disposition,
          'The Python runtime boundary failed: $error',
        ),
      );
    } finally {
      if (installedRuntimeIdentity &&
          !_stagingLeases.outstandingCleanupAttempts().contains(attempt) &&
          _runtimeIdentitiesByAttempt[attempt] == identity) {
        _runtimeIdentitiesByAttempt.remove(attempt);
      }
    }
  }

  /// Retires one exact owner and deletes every committed staging directory
  /// whose marker identity still matches.
  Future<PythonStagingRuntimeRetirementResult> retireOwner(
    ChatTurnOwner owner,
  ) {
    final recoveryReceipt = _executionAuthority.clearOwner(owner);
    return _drainRetirement(
      _stagingLeases.clearOwner(owner),
      owner: owner,
      executionRecoveryReceipt: recoveryReceipt,
    );
  }

  /// Retires all observed owners and drains every immediately claimable
  /// staging directory.
  Future<PythonStagingRuntimeRetirementResult> clearAll() {
    final recoveryReceipt = _executionAuthority.clearAll();
    return _drainRetirement(
      _stagingLeases.clearAll(),
      executionRecoveryReceipt: recoveryReceipt,
    );
  }

  PythonScriptExecutionRecoveryReceipt? get pendingExecutionRecovery =>
      _executionAuthority.pendingRecovery;

  bool reconcileExecutionRecovery({
    required PythonScriptExecutionRecoveryReceipt receipt,
    required PythonExecutionRuntimeIdentity observedIdentity,
  }) {
    return _executionAuthority.reconcileRecovery(
      receipt: receipt,
      observedIdentity: observedIdentity,
    );
  }

  bool clearExecutionRecovery(PythonScriptExecutionRecoveryReceipt receipt) {
    return _executionAuthority.clearRecovery(receipt);
  }

  Future<PythonStagingRuntimeRetirementResult> _drainRetirement(
    PythonStagingClearDisposition retirement, {
    ChatTurnOwner? owner,
    PythonScriptExecutionRecoveryReceipt? executionRecoveryReceipt,
  }) async {
    var settledCleanupCount = 0;
    for (final claim in retirement.cleanupClaims) {
      final attempt = claim.lease.attempt;
      final runtimeIdentity = _runtimeIdentitiesByAttempt[attempt];
      var cleanupSucceeded = false;
      if (runtimeIdentity != null) {
        final cleanupIdentity = PythonStagingCleanupIdentity(
          runtime: runtimeIdentity,
          attempt: attempt,
          directoryIdentity: claim.lease.directoryIdentity,
        );
        try {
          final acknowledgement = await _cleanup(
            PythonRuntimeCleanupRequest(identity: cleanupIdentity),
          );
          cleanupSucceeded =
              acknowledgement.identity == cleanupIdentity &&
              acknowledgement.disposition ==
                  PythonRuntimeAcknowledgementDisposition.completed &&
              acknowledgement.value?.isSettled == true;
        } catch (_) {
          cleanupSucceeded = false;
        }
      }

      final settlement = _stagingLeases.settleCleanup(
        claim: claim,
        succeeded: cleanupSucceeded,
      );
      final settled =
          cleanupSucceeded &&
          settlement == PythonStagingCleanupSettleStatus.settled;
      if (settled) {
        settledCleanupCount += 1;
        if (_runtimeIdentitiesByAttempt[attempt] == runtimeIdentity) {
          _runtimeIdentitiesByAttempt.remove(attempt);
        }
      } else if (runtimeIdentity != null) {
        _runtimeIdentitiesByAttempt[attempt] = runtimeIdentity;
      }
    }

    return PythonStagingRuntimeRetirementResult(
      retiredReservationCount: retirement.retiredReservationCount,
      cleanupClaimCount: retirement.cleanupClaims.length,
      settledCleanupCount: settledCleanupCount,
      outstandingCleanupAttempts: _stagingLeases.outstandingCleanupAttempts(
        owner: owner,
      ),
      executionRecoveryReceipt:
          executionRecoveryReceipt ?? _executionAuthority.pendingRecovery,
    );
  }

  _OwnerMessagesCapture _captureMessages(
    PythonScriptInvocationIdentity identity,
  ) {
    try {
      final acknowledgement = _resolveOwnerMessages(identity);
      if (acknowledgement.identity != identity) {
        return const _OwnerMessagesCapture.rejected(
          'The owner message acknowledgement identity did not match.',
        );
      }
      final disposition = acknowledgement.disposition;
      if (disposition != PythonRuntimeAcknowledgementDisposition.completed) {
        return _OwnerMessagesCapture.failed(
          _runtimeDisposition(disposition),
          acknowledgement.message ??
              'The owner message snapshot was not available.',
        );
      }
      final messages = acknowledgement.value;
      if (messages == null) {
        return const _OwnerMessagesCapture.rejected(
          'The owner message snapshot acknowledgement had no messages.',
        );
      }
      return _OwnerMessagesCapture.completed(messages);
    } catch (_) {
      return const _OwnerMessagesCapture.rejected(
        'The owner message snapshot could not be captured.',
      );
    }
  }
}

final class _OwnerMessagesCapture {
  _OwnerMessagesCapture.completed(List<Message> messages)
    : messages = List<Message>.unmodifiable(messages),
      disposition = null,
      message = '';

  const _OwnerMessagesCapture.rejected(this.message)
    : messages = const <Message>[],
      disposition = PythonScriptRuntimeDisposition.rejected;

  const _OwnerMessagesCapture.failed(this.disposition, this.message)
    : messages = const <Message>[];

  final List<Message> messages;
  final PythonScriptRuntimeDisposition? disposition;
  final String message;
}

PythonScriptRuntimeDisposition _runtimeDisposition(
  PythonRuntimeAcknowledgementDisposition disposition,
) {
  return switch (disposition) {
    PythonRuntimeAcknowledgementDisposition.completed =>
      PythonScriptRuntimeDisposition.completed,
    PythonRuntimeAcknowledgementDisposition.rejected =>
      PythonScriptRuntimeDisposition.rejected,
    PythonRuntimeAcknowledgementDisposition.ownerExpired =>
      PythonScriptRuntimeDisposition.ownerExpired,
    PythonRuntimeAcknowledgementDisposition.effectUncertain =>
      PythonScriptRuntimeDisposition.effectUncertain,
  };
}
