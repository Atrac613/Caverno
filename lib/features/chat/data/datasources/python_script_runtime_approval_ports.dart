part of 'python_script_runtime_ports.dart';

final class PythonScriptApprovalRuntimePorts
    implements PythonScriptApprovalPort {
  const PythonScriptApprovalRuntimePorts._(
    this._owner, {
    required PythonRuntimeDenialLookupCallback lookupDenial,
    required PythonRuntimeGateCallback resolveGate,
    required PythonRuntimeManualApprovalCallback requestManualApproval,
    required PythonRuntimeCacheWriteCallback rememberDenial,
    required PythonRuntimeCacheWriteCallback rememberResult,
  }) : _lookupDenial = lookupDenial,
       _resolveGate = resolveGate,
       _requestManualApproval = requestManualApproval,
       _rememberDenial = rememberDenial,
       _rememberResult = rememberResult;

  final PythonScriptRuntimePorts _owner;
  final PythonRuntimeDenialLookupCallback _lookupDenial;
  final PythonRuntimeGateCallback _resolveGate;
  final PythonRuntimeManualApprovalCallback _requestManualApproval;
  final PythonRuntimeCacheWriteCallback _rememberDenial;
  final PythonRuntimeCacheWriteCallback _rememberResult;

  @override
  PythonScriptCompletion<McpToolResult?> lookupDenial(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
  ) {
    if (!_owner._attemptMatches(attempt)) {
      _owner._observeMismatch();
      return _owner._expired<McpToolResult?>();
    }
    final cacheRequest = _cacheRequest(key);
    final PythonRuntimeAcknowledgement<
      PythonApprovalRuntimeIdentity,
      McpToolResult?
    >
    acknowledgement;
    try {
      acknowledgement = _lookupDenial(cacheRequest);
    } catch (_) {
      _owner._observe(PythonScriptRuntimeDisposition.rejected);
      return _owner._expired<McpToolResult?>();
    }
    if (!_acceptAcknowledgement(
      acknowledgement.identity,
      cacheRequest.identity,
      acknowledgement.disposition,
    )) {
      return _owner._expired<McpToolResult?>();
    }
    final result = acknowledgement.value;
    if (result != null && result.toolName != _owner.identity.toolName) {
      _owner._observeMismatch();
      return _owner._expired<McpToolResult?>();
    }
    if (_owner._lifecycleDisposition() != null) {
      return _owner._expired<McpToolResult?>();
    }
    return _owner._completed(result);
  }

  @override
  Future<PythonScriptCompletion<ToolApprovalGateDecision>> resolveGate(
    PythonStagingAttempt attempt,
    PythonScriptApprovalRequest request,
  ) async {
    final acknowledgement = await _approvalAcknowledgement(
      attempt,
      request,
      _resolveGate,
    );
    final gate = acknowledgement?.value;
    if (acknowledgement == null || gate == null) {
      return _owner._expired<ToolApprovalGateDecision>();
    }
    _owner._resultCacheRequired = !gate.bypassedApproval;
    return _owner._completed(gate);
  }

  @override
  Future<PythonScriptCompletion<bool>> requestManualApproval(
    PythonStagingAttempt attempt,
    PythonScriptApprovalRequest request,
  ) async {
    final acknowledgement = await _approvalAcknowledgement(
      attempt,
      request,
      _requestManualApproval,
    );
    final approved = acknowledgement?.value;
    return acknowledgement == null || approved == null
        ? _owner._expired<bool>()
        : _owner._completed(approved);
  }

  @override
  PythonScriptCompletion<Object?> rememberDenial(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
    McpToolResult result,
  ) {
    return _remember(
      attempt,
      key,
      result,
      _rememberDenial,
      afterExecution: false,
    );
  }

  @override
  PythonScriptCompletion<Object?> rememberResult(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
    McpToolResult result,
  ) {
    return _remember(
      attempt,
      key,
      result,
      _rememberResult,
      afterExecution: true,
    );
  }

  @override
  PythonScriptCompletion<McpToolResult?> expiredResult(
    PythonStagingAttempt attempt,
  ) {
    if (!_owner._attemptMatches(attempt)) {
      _owner._observeMismatch();
      return _owner._expired<McpToolResult?>();
    }
    if (_owner._lifecycleDisposition() != null) {
      return _owner._expired<McpToolResult?>();
    }
    if (_owner._resultCacheRequired == false &&
        _owner._acceptedExecutionResult != null &&
        _owner._executionCleanupAccepted &&
        (!_owner._prepareExecutionRelease() || !_owner._releaseExecution())) {
      return _owner._expired<McpToolResult?>();
    }
    return _owner._completed<McpToolResult?>(null);
  }

  Future<PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, T>?>
  _approvalAcknowledgement<T>(
    PythonStagingAttempt attempt,
    PythonScriptApprovalRequest request,
    Future<PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, T>>
    Function(PythonRuntimeApprovalRequest request)
    callback,
  ) async {
    if (!_owner._attemptMatches(attempt) ||
        request.toolRequest.owner != _owner.identity.owner ||
        request.toolCallId != _owner.identity.toolCallId) {
      _owner._observeMismatch();
      return null;
    }
    if (_owner._lifecycleDisposition() != null) return null;
    final approvalIdentity = _approvalIdentity(request.key);
    final runtimeRequest = PythonRuntimeApprovalRequest(
      identity: approvalIdentity,
      toolRequest: request,
    );
    final PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, T>
    acknowledgement;
    try {
      acknowledgement = await callback(runtimeRequest);
    } catch (_) {
      _owner._observe(PythonScriptRuntimeDisposition.rejected);
      return null;
    }
    if (!_acceptAcknowledgement(
      acknowledgement.identity,
      approvalIdentity,
      acknowledgement.disposition,
    )) {
      return null;
    }
    return _owner._lifecycleDisposition() == null ? acknowledgement : null;
  }

  PythonScriptCompletion<Object?> _remember(
    PythonStagingAttempt attempt,
    PythonScriptApprovalKey key,
    McpToolResult result,
    PythonRuntimeCacheWriteCallback callback, {
    required bool afterExecution,
  }) {
    final hasExecutionEffect =
        afterExecution && !_owner._preEffectExecutionRejected;
    if (!_owner._attemptMatches(attempt) ||
        result.toolName != _owner.identity.toolName) {
      hasExecutionEffect
          ? _owner.markEffectUncertain()
          : _owner._observeMismatch();
      return _owner._expired<Object?>();
    }
    if (_owner._lifecycleDisposition() != null) {
      return _owner._expired<Object?>();
    }
    if (hasExecutionEffect &&
        (!_owner._matchesAcceptedExecutionResult(result) ||
            _owner._resultCacheRequired != true ||
            !_owner._prepareExecutionRelease())) {
      _owner.markEffectUncertain();
      return _owner._expired<Object?>();
    }
    final cacheRequest = _cacheRequest(key);
    final acknowledgement = _captureCacheWrite(
      callback,
      PythonRuntimeCacheWriteRequest(
        cacheRequest: cacheRequest,
        result: result,
      ),
      afterExecution: hasExecutionEffect,
    );
    if (acknowledgement == null ||
        !_acceptAcknowledgement(
          acknowledgement.identity,
          cacheRequest.identity,
          acknowledgement.disposition,
          postEffect: hasExecutionEffect,
        ) ||
        _owner._lifecycleDisposition() != null) {
      return _owner._expired<Object?>();
    }
    if (hasExecutionEffect && !_owner._releaseExecution()) {
      return _owner._expired<Object?>();
    }
    return _owner._completed<Object?>(null);
  }

  PythonRuntimeAcknowledgement<PythonApprovalRuntimeIdentity, Object?>?
  _captureCacheWrite(
    PythonRuntimeCacheWriteCallback callback,
    PythonRuntimeCacheWriteRequest request, {
    required bool afterExecution,
  }) {
    try {
      return callback(request);
    } catch (_) {
      afterExecution
          ? _owner.markEffectUncertain()
          : _owner._observe(PythonScriptRuntimeDisposition.rejected);
      return null;
    }
  }

  PythonRuntimeCacheRequest _cacheRequest(PythonScriptApprovalKey key) {
    return PythonRuntimeCacheRequest(
      identity: _approvalIdentity(key),
      cacheArguments: key.cacheArguments,
    );
  }

  PythonApprovalRuntimeIdentity _approvalIdentity(PythonScriptApprovalKey key) {
    return PythonApprovalRuntimeIdentity(
      runtime: _owner.identity,
      cacheArguments: key.cacheArguments,
    );
  }

  bool _acceptAcknowledgement<I>(
    I actual,
    I expected,
    PythonRuntimeAcknowledgementDisposition disposition, {
    bool postEffect = false,
  }) {
    if (actual != expected) {
      postEffect ? _owner.markEffectUncertain() : _owner._observeMismatch();
      return false;
    }
    if (disposition != PythonRuntimeAcknowledgementDisposition.completed) {
      postEffect
          ? _owner.markEffectUncertain()
          : _owner._observeAcknowledgement(disposition);
      return false;
    }
    return true;
  }
}
