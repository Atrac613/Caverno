part of 'python_script_runtime_ports.dart';

extension _PythonExecutionSettlement on PythonScriptRuntimePorts {
  void _acknowledgeExecutionCleanup(
    PythonStagingCleanupIdentity cleanupIdentity,
  ) {
    final permit = _executionPermit;
    final executionIdentity = _executionIdentity;
    if (permit == null || permit.receipt == null) return;
    if (executionIdentity == null ||
        cleanupIdentity.runtime != identity ||
        cleanupIdentity.directoryIdentity !=
            executionIdentity.directoryIdentity ||
        !_executionAuthority.acknowledgeCleanup(permit)) {
      _retainExecutionRecovery();
      return;
    }
    _executionCleanupAccepted = true;
  }

  bool _prepareExecutionRelease() {
    final permit = _executionPermit;
    if (permit == null ||
        permit.receipt == null ||
        _acceptedExecutionResult == null ||
        !_executionCleanupAccepted ||
        !_executionAuthority.prepareRelease(permit)) {
      _retainExecutionRecovery();
      return false;
    }
    return true;
  }

  bool _releaseExecution() {
    final permit = _executionPermit;
    if (permit == null || !_executionAuthority.release(permit)) {
      _retainExecutionRecovery();
      return false;
    }
    _executionReleased = true;
    return true;
  }

  void _retainExecutionRecovery() {
    final permit = _executionPermit;
    if (permit != null) {
      _executionAuthority.retainRecovery(permit);
    }
    _observe(PythonScriptRuntimeDisposition.effectUncertain);
  }

  bool _matchesAcceptedExecutionResult(McpToolResult result) {
    final accepted = _acceptedExecutionResult;
    return accepted != null &&
        accepted.toolName == result.toolName &&
        accepted.result == result.result &&
        accepted.isSuccess == result.isSuccess &&
        accepted.errorMessage == result.errorMessage;
  }
}
