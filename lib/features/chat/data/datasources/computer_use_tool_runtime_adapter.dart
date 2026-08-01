import '../../../../core/services/macos_computer_use_runtime_identity.dart';
import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/computer_use_action_policy.dart';
import '../../domain/services/computer_use_runtime_coordinator.dart';
import '../../domain/services/computer_use_tool_handler.dart';

typedef ComputerUseRuntimeStateCallback =
    ComputerUseRuntimeState Function(
      ComputerUseOperationIdentity? expectedIdentity,
    );
typedef ComputerUseOwnerCurrentCallback =
    bool Function(ComputerUseOperationIdentity identity);
typedef ComputerUseDenialLookupCallback =
    McpToolResult? Function(ComputerUseToolRequest request);
typedef ComputerUseApprovalCallback =
    Future<ComputerUseApprovalOutcome> Function(
      ComputerUseApprovalRequest request,
    );
typedef ComputerUseDenialRecorderCallback =
    bool Function(ComputerUseToolRequest request, McpToolResult result);
typedef ComputerUseTransportCallback =
    Future<McpToolResult> Function(
      ComputerUseToolRequest request,
      ComputerUseRuntimeLease lease,
    );
typedef ComputerUseObservationCallback =
    Future<McpToolResult> Function(
      ComputerUseObservationRequest request,
      ComputerUseRuntimeLease lease,
    );
typedef ComputerUseAuditCallback =
    bool Function(
      ComputerUseToolRequest request,
      ComputerUseAuditRecord record,
    );

/// Production callback bridge for the exact-operation Computer Use handler.
final class ComputerUseToolRuntimeAdapter {
  ComputerUseToolRuntimeAdapter({
    ComputerUseRuntimeStateCallback? captureRuntimeState,
    MacosComputerUseRuntimeIdentityProvider? runtimeIdentityProvider,
    required ComputerUseOwnerCurrentCallback ownerIsCurrent,
    required ComputerUseDenialLookupCallback lookupDenial,
    required ComputerUseApprovalCallback requestApproval,
    required ComputerUseDenialRecorderCallback rememberDenial,
    required ComputerUseTransportCallback execute,
    required ComputerUseObservationCallback observe,
    required ComputerUseAuditCallback recordAudit,
    required DateTime Function() clock,
    required ComputerUseRuntimeCoordinator runtimeCoordinator,
    this.authorizationLifetime = const Duration(minutes: 5),
    ComputerUseActionPolicy actionPolicy = const ComputerUseActionPolicy(),
  }) : _runtimeIdentityProvider = runtimeIdentityProvider,
       _captureRuntimeState = _resolveRuntimeCapture(
         captureRuntimeState,
         runtimeIdentityProvider,
       ),
       _ownerIsCurrent = ownerIsCurrent,
       _lookupDenial = lookupDenial,
       _requestApproval = requestApproval,
       _rememberDenial = rememberDenial,
       _execute = execute,
       _observe = observe,
       _recordAudit = recordAudit,
       _clock = clock,
       _runtimeCoordinator = runtimeCoordinator,
       _actionPolicy = actionPolicy {
    if (authorizationLifetime <= Duration.zero) {
      throw ArgumentError.value(
        authorizationLifetime,
        'authorizationLifetime',
        'The Computer Use authorization lifetime must be positive.',
      );
    }
    final provider = _runtimeIdentityProvider;
    if (provider != null) {
      _detachRuntimeInvalidationListener = provider.addInvalidationListener(
        _handleRuntimeInvalidation,
      );
    }
  }

  final MacosComputerUseRuntimeIdentityProvider? _runtimeIdentityProvider;
  final ComputerUseRuntimeStateCallback _captureRuntimeState;
  final ComputerUseOwnerCurrentCallback _ownerIsCurrent;
  final ComputerUseDenialLookupCallback _lookupDenial;
  final ComputerUseApprovalCallback _requestApproval;
  final ComputerUseDenialRecorderCallback _rememberDenial;
  final ComputerUseTransportCallback _execute;
  final ComputerUseObservationCallback _observe;
  final ComputerUseAuditCallback _recordAudit;
  final DateTime Function() _clock;
  final ComputerUseRuntimeCoordinator _runtimeCoordinator;
  final ComputerUseActionPolicy _actionPolicy;
  final Duration authorizationLifetime;
  void Function()? _detachRuntimeInvalidationListener;
  MacosComputerUseRuntimeInvalidation? _lastRuntimeInvalidation;
  ComputerUseRuntimeInvalidationResult? _lastCoordinatorInvalidation;

  Future<McpToolResult> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) async {
    _validateInvocation(toolCall);
    final action = ComputerUseActionInput(
      toolName: toolCall.name.trim(),
      arguments: toolCall.arguments,
    );
    final runtime = _captureRuntime();
    if (runtime == null) {
      return _expired(action.toolName);
    }
    final now = _clock();
    final request = ComputerUseToolRequest(
      owner: owner,
      toolCallId: toolCall.id,
      toolName: action.toolName,
      arguments: action.arguments,
      runtimeSessionId: runtime.sessionId,
      runtimeRevision: runtime.revision,
      authorizationExpiresAt: now.add(authorizationLifetime),
    );
    final ports = _BoundComputerUseRuntimePorts(
      identity: request.identity,
      captureRuntimeState: _captureRuntimeState,
      ownerIsCurrent: _ownerIsCurrent,
      lookupDenial: _lookupDenial,
      requestApproval: _requestApproval,
      rememberDenial: _rememberDenial,
      execute: _execute,
      observe: _observe,
      recordAudit: _recordAudit,
    );
    final handler = ComputerUseToolHandler(
      executionPort: ports,
      approvalPort: ports,
      observationPort: ports,
      runtimeStatePort: ports,
      runtimeCoordinator: _runtimeCoordinator,
      clock: _clock,
      actionPolicy: _actionPolicy,
    );
    return MacosComputerUseToolPolicy.requiresUserApproval(request.toolName)
        ? handler.handle(request)
        : handler.handleWithoutApproval(request);
  }

  ComputerUseTerminalClearResult retireOwner(ChatTurnOwner owner) {
    return _runtimeCoordinator.clearOwner(owner);
  }

  ComputerUseRuntimeInvalidationResult helperRestarted() {
    final provider = _runtimeIdentityProvider;
    if (provider == null) return _runtimeCoordinator.helperRestarted();
    return _providerInvalidationResult(provider.helperRestarted());
  }

  ComputerUseRuntimeInvalidationResult emergencyStop() {
    final provider = _runtimeIdentityProvider;
    if (provider == null) return _runtimeCoordinator.emergencyStop();
    return _providerInvalidationResult(provider.emergencyStop());
  }

  ComputerUseTerminalClearResult clearAll() {
    final result = _runtimeCoordinator.clearAll();
    dispose();
    return result;
  }

  void dispose() {
    _detachRuntimeInvalidationListener?.call();
    _detachRuntimeInvalidationListener = null;
  }

  ComputerUseRuntimeState? _captureRuntime() {
    try {
      return _captureRuntimeState(null);
    } catch (_) {
      return null;
    }
  }

  static void _validateInvocation(ToolCallInfo toolCall) {
    if (toolCall.id.trim().isEmpty) {
      throw ArgumentError.value(
        toolCall.id,
        'toolCall.id',
        'The Computer Use tool call ID must not be empty.',
      );
    }
    if (toolCall.name.trim().isEmpty) {
      throw ArgumentError.value(
        toolCall.name,
        'toolCall.name',
        'The Computer Use tool name must not be empty.',
      );
    }
    if (!MacosComputerUseToolPolicy.isComputerUseTool(toolCall.name.trim())) {
      throw ArgumentError.value(
        toolCall.name,
        'toolCall.name',
        'A registered Computer Use tool name is required.',
      );
    }
  }

  void _handleRuntimeInvalidation(
    MacosComputerUseRuntimeInvalidation invalidation,
  ) {
    _lastRuntimeInvalidation = invalidation;
    _lastCoordinatorInvalidation = switch (invalidation.cause) {
      MacosComputerUseRuntimeInvalidationCause.helperLaunch ||
      MacosComputerUseRuntimeInvalidationCause.helperRestart =>
        _runtimeCoordinator.helperRestarted(),
      MacosComputerUseRuntimeInvalidationCause.helperTermination =>
        _runtimeCoordinator.helperRestarted(),
      MacosComputerUseRuntimeInvalidationCause.emergencyStop =>
        _runtimeCoordinator.emergencyStop(),
    };
  }

  ComputerUseRuntimeInvalidationResult _providerInvalidationResult(
    MacosComputerUseRuntimeInvalidation invalidation,
  ) {
    final result = _lastCoordinatorInvalidation;
    if (identical(_lastRuntimeInvalidation, invalidation) && result != null) {
      return result;
    }
    return switch (invalidation.cause) {
      MacosComputerUseRuntimeInvalidationCause.helperLaunch ||
      MacosComputerUseRuntimeInvalidationCause.helperRestart =>
        _runtimeCoordinator.helperRestarted(),
      MacosComputerUseRuntimeInvalidationCause.helperTermination =>
        _runtimeCoordinator.helperRestarted(),
      MacosComputerUseRuntimeInvalidationCause.emergencyStop =>
        _runtimeCoordinator.emergencyStop(),
    };
  }

  static ComputerUseRuntimeStateCallback _resolveRuntimeCapture(
    ComputerUseRuntimeStateCallback? captureRuntimeState,
    MacosComputerUseRuntimeIdentityProvider? runtimeIdentityProvider,
  ) {
    if ((captureRuntimeState == null) == (runtimeIdentityProvider == null)) {
      throw ArgumentError(
        'Provide exactly one Computer Use runtime state authority.',
      );
    }
    if (captureRuntimeState case final callback?) return callback;
    return (_) {
      final identity = runtimeIdentityProvider!.captureAvailable();
      if (identity == null) {
        throw StateError('The Computer Use helper runtime is unavailable.');
      }
      return ComputerUseRuntimeState(
        sessionId: identity.sessionId,
        revision: identity.revision,
      );
    };
  }

  static McpToolResult _expired(String toolName) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: 'The approval turn expired before execution',
    );
  }
}

final class _BoundComputerUseRuntimePorts
    implements
        ComputerUseExecutionPort,
        ComputerUseApprovalPort,
        ComputerUseObservationPort,
        ComputerUseRuntimeStatePort {
  const _BoundComputerUseRuntimePorts({
    required this.identity,
    required ComputerUseRuntimeStateCallback captureRuntimeState,
    required ComputerUseOwnerCurrentCallback ownerIsCurrent,
    required ComputerUseDenialLookupCallback lookupDenial,
    required ComputerUseApprovalCallback requestApproval,
    required ComputerUseDenialRecorderCallback rememberDenial,
    required ComputerUseTransportCallback execute,
    required ComputerUseObservationCallback observe,
    required ComputerUseAuditCallback recordAudit,
  }) : _captureRuntimeState = captureRuntimeState,
       _ownerIsCurrent = ownerIsCurrent,
       _lookupDenial = lookupDenial,
       _requestApproval = requestApproval,
       _rememberDenial = rememberDenial,
       _execute = execute,
       _observe = observe,
       _recordAudit = recordAudit;

  final ComputerUseOperationIdentity identity;
  final ComputerUseRuntimeStateCallback _captureRuntimeState;
  final ComputerUseOwnerCurrentCallback _ownerIsCurrent;
  final ComputerUseDenialLookupCallback _lookupDenial;
  final ComputerUseApprovalCallback _requestApproval;
  final ComputerUseDenialRecorderCallback _rememberDenial;
  final ComputerUseTransportCallback _execute;
  final ComputerUseObservationCallback _observe;
  final ComputerUseAuditCallback _recordAudit;

  @override
  ComputerUseRuntimeState capture() => _captureRuntimeState(identity);

  @override
  bool isOwnerCurrent(ChatTurnOwner owner) {
    if (owner != identity.owner) return false;
    try {
      return _ownerIsCurrent(identity);
    } catch (_) {
      return false;
    }
  }

  @override
  ComputerUseOwnedValue<McpToolResult>? lookupDenial(
    ComputerUseToolRequest request,
  ) {
    if (!_belongsToBinding(request)) return null;
    final result = _lookupDenial(request);
    return result == null
        ? null
        : ComputerUseOwnedValue(identity: identity, value: result);
  }

  @override
  Future<ComputerUseOwnedValue<ComputerUseApprovalOutcome>> requestApproval(
    ComputerUseApprovalRequest request,
  ) async {
    _requireBinding(request.toolRequest);
    final outcome = await _requestApproval(request);
    return ComputerUseOwnedValue(identity: identity, value: outcome);
  }

  @override
  ComputerUseEffectAcknowledgement rememberDenial(
    ComputerUseToolRequest request,
    McpToolResult result,
  ) {
    if (!_belongsToBinding(request)) return _rejected();
    return _acknowledge(() => _rememberDenial(request, result));
  }

  @override
  Future<ComputerUseOwnedValue<McpToolResult>> execute(
    ComputerUseToolRequest request,
    ComputerUseRuntimeLease lease,
  ) async {
    _requireBinding(request);
    if (lease.identity != identity) {
      throw StateError('Computer Use execution lease identity mismatch.');
    }
    final result = await _execute(request, lease);
    return ComputerUseOwnedValue(identity: identity, value: result);
  }

  @override
  Future<ComputerUseOwnedValue<ComputerUsePostActionObservation>> observe(
    ComputerUseObservationRequest request,
    ComputerUseRuntimeLease lease,
  ) async {
    _requireBinding(request.toolRequest);
    if (lease.identity != identity) {
      throw StateError('Computer Use observation lease identity mismatch.');
    }
    final result = await _observe(request, lease);
    return ComputerUseOwnedValue(
      identity: identity,
      value: ComputerUsePostActionObservation(
        toolName: result.toolName,
        success: result.isSuccess,
        result: result.result,
        errorCode: result.errorMessage,
      ),
    );
  }

  @override
  ComputerUseEffectAcknowledgement recordAudit(
    ComputerUseToolRequest request,
    ComputerUseAuditRecord record,
  ) {
    if (!_belongsToBinding(request)) return _rejected();
    return _acknowledge(() => _recordAudit(request, record));
  }

  ComputerUseEffectAcknowledgement _acknowledge(bool Function() effect) {
    var accepted = false;
    try {
      accepted = effect() && _ownerIsCurrent(identity);
    } catch (_) {
      accepted = false;
    }
    return ComputerUseEffectAcknowledgement(
      identity: identity,
      accepted: accepted,
    );
  }

  ComputerUseEffectAcknowledgement _rejected() {
    return ComputerUseEffectAcknowledgement(
      identity: identity,
      accepted: false,
    );
  }

  bool _belongsToBinding(ComputerUseToolRequest request) {
    return request.identity == identity;
  }

  void _requireBinding(ComputerUseToolRequest request) {
    if (!_belongsToBinding(request)) {
      throw StateError('Computer Use request identity mismatch.');
    }
  }
}
