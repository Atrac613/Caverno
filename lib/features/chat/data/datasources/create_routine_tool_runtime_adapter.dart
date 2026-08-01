import '../../../routines/domain/entities/routine.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/create_routine_tool_handler.dart';
import 'create_routine_runtime_contract.dart';
import 'create_routine_runtime_support.dart';

export 'create_routine_runtime_contract.dart';

part 'create_routine_runtime_success_recovery.dart';

final class CreateRoutineToolRuntimeAdapter {
  const CreateRoutineToolRuntimeAdapter({
    required CreateRoutineApprovalCallback requestApproval,
    required CreateRoutineOwnerCallback acknowledgeOwner,
    required CreateRoutineStoreCallback create,
    required CreateRoutineSnapshotCallback captureSnapshot,
    required CreateRoutineCompensationCallback compensate,
    required CreateRoutineSuccessCallback recordSuccess,
    required CreateRoutineSuccessReleaseCallback releaseSuccess,
  }) : _requestApproval = requestApproval,
       _acknowledgeOwner = acknowledgeOwner,
       _create = create,
       _captureSnapshot = captureSnapshot,
       _compensate = compensate,
       _recordSuccess = recordSuccess,
       _releaseSuccess = releaseSuccess;

  final CreateRoutineApprovalCallback _requestApproval;
  final CreateRoutineOwnerCallback _acknowledgeOwner;
  final CreateRoutineStoreCallback _create;
  final CreateRoutineSnapshotCallback _captureSnapshot;
  final CreateRoutineCompensationCallback _compensate;
  final CreateRoutineSuccessCallback _recordSuccess;
  final CreateRoutineSuccessReleaseCallback _releaseSuccess;

  Future<CreateRoutineRuntimeCompletion> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) async {
    final input = CreateRoutineRuntimeInput(owner: owner, toolCall: toolCall);
    final bridge = _CreateRoutineRuntimeBridge(
      input: input,
      requestApproval: _requestApproval,
      acknowledgeOwner: _acknowledgeOwner,
      create: _create,
      captureSnapshot: _captureSnapshot,
      compensate: _compensate,
      recordSuccess: _recordSuccess,
      releaseSuccess: _releaseSuccess,
    );
    final handler = CreateRoutineToolHandler(
      storePort: bridge,
      approvalPort: bridge,
    );
    McpToolResult result;
    try {
      result = await handler.handle(input.toToolRequest());
      if (result.isSuccess) {
        result = await bridge.finalizeSuccess(result);
      }
    } catch (error) {
      result = createRoutineRuntimeFailure('Failed to create routine: $error');
    }
    return CreateRoutineRuntimeCompletion(
      identity: input.identity,
      disposition: bridge.classify(result),
      result: result,
    );
  }
}

final class _CreateRoutineRuntimeBridge
    implements RoutineCreationApprovalPort, RoutineStorePort {
  _CreateRoutineRuntimeBridge({
    required this.input,
    required CreateRoutineApprovalCallback requestApproval,
    required CreateRoutineOwnerCallback acknowledgeOwner,
    required CreateRoutineStoreCallback create,
    required CreateRoutineSnapshotCallback captureSnapshot,
    required CreateRoutineCompensationCallback compensate,
    required CreateRoutineSuccessCallback recordSuccess,
    required CreateRoutineSuccessReleaseCallback releaseSuccess,
  }) : _requestApproval = requestApproval,
       _acknowledgeOwner = acknowledgeOwner,
       _create = create,
       _captureSnapshot = captureSnapshot,
       _compensate = compensate,
       _recordSuccess = recordSuccess,
       _releaseSuccess = releaseSuccess;

  final CreateRoutineRuntimeInput input;
  final CreateRoutineApprovalCallback _requestApproval;
  final CreateRoutineOwnerCallback _acknowledgeOwner;
  final CreateRoutineStoreCallback _create;
  final CreateRoutineSnapshotCallback _captureSnapshot;
  final CreateRoutineCompensationCallback _compensate;
  final CreateRoutineSuccessCallback _recordSuccess;
  final CreateRoutineSuccessReleaseCallback _releaseSuccess;

  final CreateRoutineRuntimeObservation _observation =
      CreateRoutineRuntimeObservation();
  CreateRoutineReceiptIdentity? _committedReceipt;

  @override
  Future<RoutineCreationApprovalDecision> requestApproval(
    CreateRoutineOperationIdentity identity,
    RoutineCreationApprovalRequest request,
  ) async {
    if (!matchesCreateRoutineOperation(identity, input.identity)) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      return RoutineCreationApprovalDecision(
        identity: identity,
        approved: false,
      );
    }
    try {
      final acknowledgement = await _requestApproval(input.identity, request);
      if (!acknowledgement.identity.belongsTo(input.identity)) {
        _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
        return RoutineCreationApprovalDecision(
          identity: identity,
          approved: false,
        );
      }
      final approved = switch (acknowledgement.disposition) {
        CreateRoutineApprovalDisposition.approved => true,
        CreateRoutineApprovalDisposition.rejected => false,
        CreateRoutineApprovalDisposition.ownerExpired => false,
        CreateRoutineApprovalDisposition.effectUncertain => false,
      };
      _observation.observeApproval(acknowledgement.disposition);
      return RoutineCreationApprovalDecision(
        identity: identity,
        approved: approved,
      );
    } catch (_) {
      markEffectUncertain();
      return RoutineCreationApprovalDecision(
        identity: identity,
        approved: false,
      );
    }
  }

  @override
  RoutineCreationOwnerState ownerState(
    CreateRoutineOperationIdentity identity,
    CreateRoutineToolRequest request,
  ) {
    if (!matchesCreateRoutineOperation(identity, input.identity)) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      return RoutineCreationOwnerState.expired(
        identity: identity,
        result: createRoutineRuntimeFailure(
          'Routine creation owner identity mismatch.',
        ),
      );
    }
    try {
      final acknowledgement = _acknowledgeOwner(input.identity);
      if (!acknowledgement.identity.belongsTo(input.identity)) {
        _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
        return RoutineCreationOwnerState.expired(
          identity: identity,
          result: createRoutineRuntimeFailure(
            'Routine creation owner identity mismatch.',
          ),
        );
      }
      _observation.observeOwner(acknowledgement.disposition);
      return switch (acknowledgement.disposition) {
        CreateRoutineOwnerDisposition.current =>
          RoutineCreationOwnerState.current(identity: identity),
        CreateRoutineOwnerDisposition.ownerExpired =>
          RoutineCreationOwnerState.expired(
            identity: identity,
            result:
                acknowledgement.expiredResult ??
                createRoutineRuntimeFailure('The create_routine turn expired.'),
          ),
        CreateRoutineOwnerDisposition.effectUncertain =>
          RoutineCreationOwnerState.expired(
            identity: identity,
            result: createRoutineRuntimeFailure(
              'The create_routine owner state could not be verified.',
            ),
          ),
      };
    } catch (_) {
      markEffectUncertain();
      return RoutineCreationOwnerState.expired(
        identity: identity,
        result: createRoutineRuntimeFailure(
          'The create_routine owner state could not be verified.',
        ),
      );
    }
  }

  @override
  Future<RoutineStoreWriteResult> create(
    CreateRoutineOperationIdentity identity,
    RoutineStoreCreateRequest request,
  ) async {
    if (!matchesCreateRoutineOperation(identity, input.identity)) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      throw StateError('Routine store operation identity mismatch.');
    }
    CreateRoutineStoreAcknowledgement acknowledgement;
    try {
      acknowledgement = await _create(input.identity, request);
    } catch (_) {
      markEffectUncertain();
      rethrow;
    }
    if (!acknowledgement.identity.belongsTo(input.identity)) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      throw StateError('Routine store acknowledgement identity mismatch.');
    }
    switch (acknowledgement.disposition) {
      case CreateRoutineStoreDisposition.rejected:
        _observation.observe(CreateRoutineRuntimeDisposition.rejected);
        return RoutineStoreWriteResult.rejected(
          identity: identity,
          errorMessage:
              acknowledgement.errorMessage ??
              'Routine store rejected an owner that is still current.',
        );
      case CreateRoutineStoreDisposition.ownerExpired:
        _observation.observe(CreateRoutineRuntimeDisposition.ownerExpired);
        return RoutineStoreWriteResult.ownerExpired(identity: identity);
      case CreateRoutineStoreDisposition.effectUncertain:
        markEffectUncertain();
        if (acknowledgement.receiptIdentity == null) {
          throw StateError(
            acknowledgement.errorMessage ??
                'Routine store effect could not be verified.',
          );
        }
        break;
      case CreateRoutineStoreDisposition.committed:
        break;
    }

    final receipt = acknowledgement.receiptIdentity!;
    final createdRoutine = acknowledgement.createdRoutine!;
    if (receipt.runtime != input.identity ||
        receipt.requestDigest != createRoutineRequestDigest(request) ||
        receipt.createdRoutineDigest != createRoutineDigest(createdRoutine)) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      throw StateError('Routine store receipt identity mismatch.');
    }
    _committedReceipt = receipt;
    final snapshot =
        acknowledgement.disposition == CreateRoutineStoreDisposition.committed
        ? _snapshot(identity, receipt, createdRoutine)
        : null;
    return RoutineStoreWriteResult.committed(
      identity: identity,
      compensationToken: RoutineStoreCompensationToken(
        identity: identity,
        value: receipt.compensationToken,
      ),
      snapshot: snapshot,
    );
  }

  RoutineStoreSnapshot? _snapshot(
    CreateRoutineOperationIdentity identity,
    CreateRoutineReceiptIdentity receipt,
    Routine createdRoutine,
  ) {
    try {
      final acknowledgement = _captureSnapshot(receipt);
      if (acknowledgement.receiptIdentity != receipt) {
        _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
        return null;
      }
      switch (acknowledgement.disposition) {
        case CreateRoutineSnapshotDisposition.captured:
          if (!acknowledgement.routines!.contains(createdRoutine)) {
            _observation.observe(
              CreateRoutineRuntimeDisposition.boundaryMismatch,
            );
            return null;
          }
          return RoutineStoreSnapshot(
            identity: identity,
            routines: acknowledgement.routines!,
            createdRoutine: createdRoutine,
          );
        case CreateRoutineSnapshotDisposition.rejected:
          _observation.observe(CreateRoutineRuntimeDisposition.rejected);
          return null;
        case CreateRoutineSnapshotDisposition.ownerExpired:
          _observation.observe(CreateRoutineRuntimeDisposition.ownerExpired);
          return null;
        case CreateRoutineSnapshotDisposition.effectUncertain:
          markEffectUncertain();
          return null;
      }
    } catch (_) {
      markEffectUncertain();
      return null;
    }
  }

  @override
  Future<RoutineStoreCompensationResult> compensate(
    CreateRoutineOperationIdentity identity,
    RoutineStoreWriteResult committedWrite,
  ) async {
    final token = committedWrite.compensationToken?.value;
    final receipt = _committedReceipt;
    if (!matchesCreateRoutineOperation(identity, input.identity) ||
        !committedWrite.identity.belongsTo(identity) ||
        token == null ||
        receipt == null ||
        token != receipt.compensationToken) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      return RoutineStoreCompensationResult(
        identity: identity,
        disposition: RoutineStoreCompensationDisposition.failed,
        errorMessage: 'Routine compensation token identity mismatch.',
      );
    }
    try {
      final acknowledgement = await _compensate(receipt);
      if (acknowledgement.receiptIdentity != receipt) {
        _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
        return RoutineStoreCompensationResult(
          identity: identity,
          disposition: RoutineStoreCompensationDisposition.failed,
          errorMessage: 'Routine compensation acknowledgement mismatch.',
        );
      }
      return switch (acknowledgement.disposition) {
        CreateRoutineCompensationDisposition.reverted =>
          RoutineStoreCompensationResult(
            identity: identity,
            disposition: RoutineStoreCompensationDisposition.reverted,
          ),
        CreateRoutineCompensationDisposition.alreadyAbsent =>
          RoutineStoreCompensationResult(
            identity: identity,
            disposition: RoutineStoreCompensationDisposition.alreadyAbsent,
          ),
        CreateRoutineCompensationDisposition.rejected ||
        CreateRoutineCompensationDisposition.ownerExpired ||
        CreateRoutineCompensationDisposition.effectUncertain =>
          _failedCompensation(identity, acknowledgement),
      };
    } catch (error) {
      markEffectUncertain();
      return RoutineStoreCompensationResult(
        identity: identity,
        disposition: RoutineStoreCompensationDisposition.failed,
        errorMessage: '$error',
      );
    }
  }

  Future<McpToolResult> finalizeSuccess(McpToolResult successfulResult) async {
    final receipt = _committedReceipt;
    if (receipt == null) {
      markEffectUncertain();
      return createRoutineRuntimeFailure(
        'Routine creation succeeded without an exact settlement token.',
      );
    }
    final owner = _ownerAcknowledgement();
    if (owner == null ||
        owner.disposition != CreateRoutineOwnerDisposition.current) {
      return _compensateUnsettledReceipt(receipt, ownerExpired: true);
    }
    final identity = CreateRoutineSuccessIdentity(receiptIdentity: receipt);
    final CreateRoutineSuccessAcknowledgement acknowledgement;
    try {
      acknowledgement = await _recordSuccess(identity);
    } catch (_) {
      return _compensateUnsettledReceipt(
        receipt,
        failureMessage:
            'Routine creation succeeded but its receipt could not be settled.',
      );
    }
    if (acknowledgement.identity != identity) {
      _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
      return _compensateUnsettledReceipt(
        receipt,
        failureMessage:
            'Routine creation succeeded with a mismatched settlement receipt.',
      );
    }
    return switch (acknowledgement.disposition) {
      CreateRoutineSuccessDisposition.acknowledged =>
        await _releasePreparedSuccess(identity, receipt, successfulResult),
      CreateRoutineSuccessDisposition.released => successfulResult,
      CreateRoutineSuccessDisposition.ownerExpired =>
        await _compensateUnsettledReceipt(receipt, ownerExpired: true),
      CreateRoutineSuccessDisposition.effectUncertain =>
        await _compensateUnsettledReceipt(
          receipt,
          failureMessage:
              'Routine creation succeeded but its receipt could not be settled.',
        ),
    };
  }

  CreateRoutineOwnerAcknowledgement? _ownerAcknowledgement() {
    try {
      final acknowledgement = _acknowledgeOwner(input.identity);
      if (!acknowledgement.identity.belongsTo(input.identity)) {
        _observation.observe(CreateRoutineRuntimeDisposition.boundaryMismatch);
        return null;
      }
      _observation.observeOwner(acknowledgement.disposition);
      return acknowledgement;
    } catch (_) {
      markEffectUncertain();
      return null;
    }
  }

  RoutineStoreCompensationResult _failedCompensation(
    CreateRoutineOperationIdentity identity,
    CreateRoutineCompensationAcknowledgement acknowledgement,
  ) {
    markEffectUncertain();
    return RoutineStoreCompensationResult(
      identity: identity,
      disposition: RoutineStoreCompensationDisposition.failed,
      errorMessage: acknowledgement.errorMessage,
    );
  }

  CreateRoutineRuntimeDisposition classify(McpToolResult result) =>
      _observation.classify(result);

  void markEffectUncertain() =>
      _observation.observe(CreateRoutineRuntimeDisposition.effectUncertain);
}
