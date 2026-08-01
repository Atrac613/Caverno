import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/browser_session_ownership_coordinator.dart';
import '../../domain/services/browser_tool_handler.dart';

typedef BrowserExecutionCallback =
    Future<BrowserExecutionResult> Function(
      BrowserSessionOperationIdentity operation,
      BrowserExecutionRequest request,
    );
typedef BrowserApprovalGateCallback =
    Future<BrowserApprovalGateResult> Function(
      BrowserSessionOperationIdentity operation,
      BrowserApprovalGateRequest request,
    );
typedef BrowserManualApprovalCallback =
    Future<BrowserManualApprovalResult> Function(
      BrowserSessionOperationIdentity operation,
      BrowserManualApprovalRequest request,
    );
typedef BrowserOperationCurrentCallback =
    bool Function(BrowserSessionOperationIdentity operation);
typedef BrowserExpiredResultCallback =
    McpToolResult? Function(BrowserSessionOperationIdentity operation);
typedef BrowserCurrentPageCallback =
    BrowserPageObservation Function(BrowserSessionOperationIdentity operation);
typedef BrowserSaveTargetCallback =
    Future<BrowserSaveTargetObservation> Function(
      BrowserSessionOperationIdentity operation,
      BrowserSaveTargetRequest request,
    );

/// Production-facing browser handler with one shared ownership coordinator.
///
/// The adapter keeps UI, browser transport, and save-target resolution behind
/// exact operation-tagged callbacks. One instance must be shared across calls
/// so overlapping browser operations cannot bypass the session lease.
final class BrowserToolRuntimeAdapter {
  BrowserToolRuntimeAdapter({
    required BrowserExecutionCallback execute,
    required BrowserApprovalGateCallback resolveApprovalGate,
    required BrowserManualApprovalCallback requestManualApproval,
    required BrowserOperationCurrentCallback isOperationCurrent,
    required BrowserExpiredResultCallback expiredResult,
    required BrowserCurrentPageCallback currentPage,
    required BrowserSaveTargetCallback resolveSaveTarget,
    required BrowserSessionOwnershipCoordinator sessionCoordinator,
  }) : _sessionCoordinator = sessionCoordinator {
    _handler = BrowserToolHandler(
      executionPort: CallbackBrowserExecutionPort(execute),
      approvalPort: CallbackBrowserApprovalPort(
        resolveApprovalGate: resolveApprovalGate,
        requestManualApproval: requestManualApproval,
        isOperationCurrent: isOperationCurrent,
        expiredResult: expiredResult,
      ),
      observationPort: CallbackBrowserObservationPort(
        currentPage: currentPage,
        resolveSaveTarget: resolveSaveTarget,
      ),
      sessionCoordinator: _sessionCoordinator,
    );
  }

  final BrowserSessionOwnershipCoordinator _sessionCoordinator;
  late final BrowserToolHandler _handler;

  Future<McpToolResult> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    bool withoutApproval = false,
  }) {
    final request = BrowserToolRequest(
      operation: BrowserSessionOperationIdentity(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
      ),
      arguments: toolCall.arguments,
    );
    return withoutApproval
        ? _handler.handleWithoutApproval(request)
        : _handler.handle(request);
  }

  BrowserSessionOwnerClearResult clearOwner(ChatTurnOwner owner) {
    return _sessionCoordinator.clearOwner(owner);
  }

  BrowserSessionInvalidationResult clearAll() {
    return _sessionCoordinator.clearAll();
  }

  BrowserSessionInvalidationResult invalidateSession() {
    return _sessionCoordinator.invalidateSession();
  }

  BrowserSessionEffectReceipt? get pendingEffectRecovery {
    return _sessionCoordinator.pendingEffectRecovery;
  }

  bool clearEffectRecovery(BrowserSessionEffectReceipt receipt) {
    return _sessionCoordinator.clearEffectRecovery(receipt);
  }

  bool settleInvalidatedLease(BrowserSessionLease lease) {
    return _sessionCoordinator.settleInvalidatedLease(lease);
  }
}

final class CallbackBrowserExecutionPort implements BrowserExecutionPort {
  const CallbackBrowserExecutionPort(this._execute);

  final BrowserExecutionCallback _execute;

  @override
  Future<BrowserExecutionResult> execute(
    BrowserSessionOperationIdentity operation,
    BrowserExecutionRequest request,
    BrowserSessionEffectPermit permit,
  ) {
    return permit.runEffect(() => _execute(operation, request));
  }
}

final class CallbackBrowserApprovalPort implements BrowserApprovalPort {
  const CallbackBrowserApprovalPort({
    required BrowserApprovalGateCallback resolveApprovalGate,
    required BrowserManualApprovalCallback requestManualApproval,
    required BrowserOperationCurrentCallback isOperationCurrent,
    required BrowserExpiredResultCallback expiredResult,
  }) : _resolveApprovalGate = resolveApprovalGate,
       _requestManualApproval = requestManualApproval,
       _isOperationCurrent = isOperationCurrent,
       _expiredResult = expiredResult;

  final BrowserApprovalGateCallback _resolveApprovalGate;
  final BrowserManualApprovalCallback _requestManualApproval;
  final BrowserOperationCurrentCallback _isOperationCurrent;
  final BrowserExpiredResultCallback _expiredResult;

  @override
  Future<BrowserApprovalGateResult> resolveGate(
    BrowserSessionOperationIdentity operation,
    BrowserApprovalGateRequest request,
  ) => _resolveApprovalGate(operation, request);

  @override
  Future<BrowserManualApprovalResult> requestManualApproval(
    BrowserSessionOperationIdentity operation,
    BrowserManualApprovalRequest request,
  ) => _requestManualApproval(operation, request);

  @override
  bool isOperationCurrent(BrowserSessionOperationIdentity operation) {
    return _isOperationCurrent(operation);
  }

  @override
  McpToolResult? expiredResult(BrowserSessionOperationIdentity operation) {
    return _expiredResult(operation);
  }
}

final class CallbackBrowserObservationPort implements BrowserObservationPort {
  const CallbackBrowserObservationPort({
    required BrowserCurrentPageCallback currentPage,
    required BrowserSaveTargetCallback resolveSaveTarget,
  }) : _currentPage = currentPage,
       _resolveSaveTarget = resolveSaveTarget;

  final BrowserCurrentPageCallback _currentPage;
  final BrowserSaveTargetCallback _resolveSaveTarget;

  @override
  BrowserPageObservation currentPage(
    BrowserSessionOperationIdentity operation,
  ) => _currentPage(operation);

  @override
  Future<BrowserSaveTargetObservation> resolveSaveTarget(
    BrowserSessionOperationIdentity operation,
    BrowserSaveTargetRequest request,
  ) => _resolveSaveTarget(operation, request);
}
