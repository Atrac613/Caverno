import '../entities/mcp_tool_entity.dart';
import 'git_process_execution_coordinator.dart';
import 'git_tool_contract.dart';

typedef _HandledGitCompletion = ({
  McpToolResult result,
  bool cacheable,
  GitProcessEffectReceipt? pendingReceipt,
});

/// Coordinates one raw Git process from reservation through final release.
final class GitToolProcessRunner {
  const GitToolProcessRunner({
    required GitApprovalPort approvalPort,
    required GitProcessExecutionCoordinator processCoordinator,
  }) : _approvalPort = approvalPort,
       _processCoordinator = processCoordinator;

  static const _uncertainMessage =
      'The Git process may have completed after its owner expired or with '
      'partial effects; inspect repository and worktree state, reconcile any '
      'effects, then retry';

  final GitApprovalPort _approvalPort;
  final GitProcessExecutionCoordinator _processCoordinator;

  Future<McpToolResult> run({
    required GitProcessExecutionIdentity identity,
    required String toolName,
    required Future<GitRawProcessCompletion> Function(
      GitProcessStartAuthorization authorization,
    )
    execute,
    GitApprovalRequest? approval,
  }) async {
    final reservation = _processCoordinator.reserve(identity);
    final token = reservation.token;
    if (token == null) {
      return _reservationFailure(toolName, reservation.disposition);
    }

    var processStarted = false;
    var bypassesApproval = true;
    try {
      if (approval != null) {
        final owner = identity.owner;
        final cachedDenial = _approvalPort.lookupDenial(owner, approval);
        if (cachedDenial != null) return cachedDenial;

        final gate = await _approvalPort.resolveGate(owner, approval);
        bypassesApproval = gate.bypassedApproval;
        if (gate.isDenied) {
          return _approvalPort.rememberDenial(
            owner,
            approval,
            _autoReviewDeniedResult(toolName, gate.deniedRationale!),
          );
        }
        if (gate.needsManual) {
          final approved = await _approvalPort.requestManualApproval(
            owner,
            approval,
          );
          if (!approved) {
            return _approvalPort.rememberDenial(
              owner,
              approval,
              _failure(toolName, approval.manualDenialMessage),
            );
          }
        }
        final expired = _approvalPort.expiredResult(owner, approval);
        if (expired != null) return expired;
      }

      final authorization = GitProcessStartAuthorization(
        identity: identity,
        start: () {
          final disposition = _processCoordinator.start(identity, token);
          processStarted = disposition == GitProcessStartDisposition.started;
          return disposition;
        },
      );
      final GitRawProcessCompletion completion;
      try {
        completion = await execute(authorization);
      } on GitProcessLaunchFailure catch (failure) {
        final handled = _handleLaunchFailure(
          identity: identity,
          token: token,
          toolName: toolName,
          processStarted: processStarted,
          failure: failure,
        );
        return _rememberExecutionResult(
          approval: approval,
          result: handled.result,
          cacheable: handled.cacheable,
          bypassesApproval: bypassesApproval,
        );
      } catch (error) {
        if (!processStarted) rethrow;
        return _settleUnknownEffect(
          identity: identity,
          token: token,
          toolName: toolName,
          reason: 'execution threw after process handoff: $error',
        );
      }

      if (!processStarted) {
        return authorization.disposition ==
                GitProcessStartDisposition.ownerRetired
            ? _expired(toolName)
            : _failure(
                toolName,
                'Git execution returned before the raw process handoff',
              );
      }
      final handled = _handleCompletion(
        identity: identity,
        token: token,
        toolName: toolName,
        completion: completion,
      );
      return _finalizeCompletion(
        identity: identity,
        token: token,
        toolName: toolName,
        approval: approval,
        handled: handled,
        bypassesApproval: bypassesApproval,
      );
    } finally {
      if (!processStarted) {
        _processCoordinator.abandonBeforeStart(identity, token);
      }
    }
  }

  ({McpToolResult result, bool cacheable}) _handleLaunchFailure({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required String toolName,
    required bool processStarted,
    required GitProcessLaunchFailure failure,
  }) {
    if (failure.identity != identity || failure.result.toolName != toolName) {
      if (!processStarted) {
        return (
          result: _failure(toolName, 'Git launch failure identity mismatch'),
          cacheable: false,
        );
      }
      return (
        result: _settleUnknownEffect(
          identity: identity,
          token: token,
          toolName: toolName,
          reason: 'launch failure identity mismatch after process handoff',
        ),
        cacheable: false,
      );
    }
    if (!processStarted) {
      return (result: failure.result, cacheable: true);
    }
    final completion = _processCoordinator.complete(
      identity: identity,
      token: token,
      effectKind: GitProcessEffectKind.noEffect,
      effectDetails: const {'launchFailedBeforeProcessCreation': true},
    );
    return (
      result: completion.isLate
          ? _uncertain(toolName, failure.result)
          : failure.result,
      cacheable: !completion.isLate,
    );
  }

  _HandledGitCompletion _handleCompletion({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required String toolName,
    required GitRawProcessCompletion completion,
  }) {
    if (completion.identity != identity ||
        completion.result.toolName != toolName) {
      return (
        result: _settleUnknownEffect(
          identity: identity,
          token: token,
          toolName: toolName,
          reason: 'execution completion identity mismatch',
        ),
        cacheable: false,
        pendingReceipt: null,
      );
    }
    final settled = _processCoordinator.complete(
      identity: identity,
      token: token,
      effectKind: completion.effectKind,
      effectDetails: completion.effectDetails,
    );
    if (settled.disposition == GitProcessCompletionDisposition.noEffect) {
      return (
        result: settled.isLate
            ? _uncertain(toolName, completion.result)
            : completion.result,
        cacheable: !settled.isLate,
        pendingReceipt: null,
      );
    }
    if (settled.disposition ==
            GitProcessCompletionDisposition.effectCommitted &&
        !settled.isLate) {
      return (
        result: completion.result,
        cacheable: true,
        pendingReceipt: settled.receipt,
      );
    }
    _releaseAfterReconciliation(
      identity: identity,
      token: token,
      effectReceipt: settled.receipt,
      confirmation: completion.reconciliation,
    );
    return (
      result: _uncertain(toolName, completion.result),
      cacheable: false,
      pendingReceipt: null,
    );
  }

  McpToolResult _settleUnknownEffect({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required String toolName,
    required String reason,
  }) {
    _processCoordinator.complete(
      identity: identity,
      token: token,
      effectKind: GitProcessEffectKind.partialOrUnknown,
      effectDetails: {'reason': reason},
    );
    return _uncertain(toolName);
  }

  bool _releaseAfterReconciliation({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required GitProcessEffectReceipt? effectReceipt,
    required GitProcessReconciliationConfirmation? confirmation,
  }) {
    if (effectReceipt == null || confirmation?.identity != identity) {
      return false;
    }
    final recorded = _processCoordinator.recordReconciliation(
      identity: identity,
      token: token,
      effectReceipt: effectReceipt,
    );
    final receipt = recorded.receipt;
    if (receipt == null) return false;
    final released = _processCoordinator.release(
      identity: identity,
      token: token,
      reconciliationReceipt: receipt,
    );
    return released.disposition ==
        GitProcessReleaseDisposition.reconciledAndReleased;
  }

  McpToolResult _rememberExecutionResult({
    required GitApprovalRequest? approval,
    required McpToolResult result,
    required bool cacheable,
    required bool bypassesApproval,
  }) {
    if (approval == null || !cacheable || bypassesApproval) return result;
    try {
      final remembered = _approvalPort.rememberResult(
        approval.source.owner,
        approval,
        result,
      );
      return remembered == result && remembered.toolName == result.toolName
          ? result
          : _failure(
              result.toolName,
              'Git result cache acknowledgement mismatch',
            );
    } catch (error) {
      return _failure(
        result.toolName,
        'Git result cache acknowledgement failed: $error',
      );
    }
  }

  McpToolResult _finalizeCompletion({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required String toolName,
    required GitApprovalRequest? approval,
    required _HandledGitCompletion handled,
    required bool bypassesApproval,
  }) {
    final receipt = handled.pendingReceipt;
    if (receipt == null) {
      return _rememberExecutionResult(
        approval: approval,
        result: handled.result,
        cacheable: handled.cacheable,
        bypassesApproval: bypassesApproval,
      );
    }

    if (approval != null && handled.cacheable && !bypassesApproval) {
      try {
        final remembered = _approvalPort.rememberResult(
          identity.owner,
          approval,
          handled.result,
        );
        final expired = _approvalPort.expiredResult(identity.owner, approval);
        if (remembered != handled.result ||
            remembered.toolName != toolName ||
            expired != null) {
          _retainForReconciliation(
            identity: identity,
            token: token,
            receipt: receipt,
          );
          return _uncertain(toolName, handled.result);
        }
      } catch (_) {
        _retainForReconciliation(
          identity: identity,
          token: token,
          receipt: receipt,
        );
        return _uncertain(toolName, handled.result);
      }
    }

    final released = _processCoordinator.release(
      identity: identity,
      token: token,
    );
    if (released.disposition == GitProcessReleaseDisposition.released) {
      return handled.result;
    }
    _retainForReconciliation(
      identity: identity,
      token: token,
      receipt: receipt,
    );
    return _uncertain(toolName, handled.result);
  }

  void _retainForReconciliation({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required GitProcessEffectReceipt receipt,
  }) {
    _processCoordinator.requireReconciliation(
      identity: identity,
      token: token,
      effectReceipt: receipt,
    );
  }

  McpToolResult _reservationFailure(
    String toolName,
    GitProcessReserveDisposition disposition,
  ) {
    final message = switch (disposition) {
      GitProcessReserveDisposition.ownerRetired =>
        'The Git process owner expired before execution',
      GitProcessReserveDisposition.resourceBusy =>
        'Another Git process is active for this repository and worktree',
      GitProcessReserveDisposition.attemptConflict =>
        'This exact Git process attempt is already active',
      GitProcessReserveDisposition.reserved =>
        'Git process reservation failed unexpectedly',
    };
    return _failure(toolName, message);
  }

  McpToolResult _expired(String toolName) =>
      _failure(toolName, 'The Git process owner expired before execution');

  McpToolResult _uncertain(String toolName, [McpToolResult? original]) {
    return McpToolResult(
      toolName: toolName,
      result: original?.result ?? '',
      isSuccess: false,
      errorMessage: _uncertainMessage,
    );
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }

  McpToolResult _autoReviewDeniedResult(String toolName, String rationale) {
    return McpToolResult(
      toolName: toolName,
      result: 'Auto-review denied this action. Rationale: $rationale',
      isSuccess: false,
      errorMessage: 'Auto-review denied: $rationale',
    );
  }
}
