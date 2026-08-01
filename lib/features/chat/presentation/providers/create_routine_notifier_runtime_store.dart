import '../../../routines/presentation/providers/routines_notifier.dart';
import '../../data/datasources/create_routine_runtime_contract.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/create_routine_tool_handler.dart';

typedef CreateRoutineRuntimeOwnerCurrentCallback =
    bool Function(ChatTurnOwner owner);

/// Exact receipt adapter between create-routine runtime and RoutinesNotifier.
final class CreateRoutineNotifierRuntimeStore {
  const CreateRoutineNotifierRuntimeStore({
    required RoutinesNotifier notifier,
    required CreateRoutineRuntimeOwnerCurrentCallback isOwnerCurrent,
  }) : _notifier = notifier,
       _isOwnerCurrent = isOwnerCurrent;

  final RoutinesNotifier _notifier;
  final CreateRoutineRuntimeOwnerCurrentCallback _isOwnerCurrent;

  Future<CreateRoutineStoreAcknowledgement> create(
    CreateRoutineRuntimeIdentity identity,
    RoutineStoreCreateRequest request,
  ) async {
    final bool ownerCurrent;
    try {
      ownerCurrent = _isOwnerCurrent(identity.owner);
    } catch (error) {
      return CreateRoutineStoreAcknowledgement.rejected(
        identity: identity,
        errorMessage: 'Failed to validate routine creation owner: $error',
      );
    }
    if (!ownerCurrent) {
      return CreateRoutineStoreAcknowledgement.ownerExpired(identity: identity);
    }
    try {
      final requestDigest = createRoutineRequestDigest(request);
      final binding = _binding(identity, requestDigest);
      final attempt = await _notifier.attemptRoutineCreationWithReceipt(
        binding: binding,
        preEffectOwnerIsCurrent: (candidate) =>
            candidate == binding && _isOwnerCurrent(identity.owner),
        name: request.name,
        prompt: request.prompt,
        intervalValue: request.intervalValue,
        intervalUnit: request.intervalUnit,
        scheduleMode: request.scheduleMode,
        timeOfDayMinutes: request.timeOfDayMinutes,
        enabled: request.enabled,
        notifyOnCompletion: request.notifyOnCompletion,
        toolsEnabled: request.toolsEnabled,
        completionAction: request.completionAction,
        googleChatRule: request.googleChatRule,
        workspaceDirectory: request.workspaceDirectory,
        allowWorkspaceWrites: request.allowWorkspaceWrites,
      );
      final receiptIdentity = _receiptIdentity(identity, attempt.receipt);
      return switch (attempt.disposition) {
        RoutineCreationCommitDisposition.committed =>
          CreateRoutineStoreAcknowledgement.committed(
            identity: identity,
            receiptIdentity: receiptIdentity,
            createdRoutine: attempt.receipt.routine,
          ),
        RoutineCreationCommitDisposition.rejectedBeforeEffect =>
          CreateRoutineStoreAcknowledgement.rejected(
            identity: identity,
            errorMessage:
                attempt.error?.toString() ??
                'Routine creation was rejected before persistence.',
          ),
        RoutineCreationCommitDisposition.ownerExpiredBeforeEffect =>
          CreateRoutineStoreAcknowledgement.ownerExpired(identity: identity),
        RoutineCreationCommitDisposition.effectUncertain =>
          CreateRoutineStoreAcknowledgement.effectUncertain(
            identity: identity,
            receiptIdentity: receiptIdentity,
            createdRoutine: attempt.receipt.routine,
            errorMessage: attempt.error?.toString(),
          ),
      };
    } on RoutineCreationPreEffectRejection catch (error) {
      return CreateRoutineStoreAcknowledgement.rejected(
        identity: identity,
        errorMessage: 'Failed to create routine: ${error.message}',
      );
    } catch (error) {
      return CreateRoutineStoreAcknowledgement.effectUncertain(
        identity: identity,
        errorMessage: '$error',
      );
    }
  }

  CreateRoutineSnapshotAcknowledgement captureSnapshot(
    CreateRoutineReceiptIdentity identity,
  ) {
    if (!_isOwnerCurrent(identity.runtime.owner)) {
      return CreateRoutineSnapshotAcknowledgement.ownerExpired(
        receiptIdentity: identity,
      );
    }
    final claim = _claim(identity);
    final pending = _notifier.pendingCreationReceipt(claim);
    final released = _notifier.releasedCreationReceipt(claim);
    final receipt = pending ?? released;
    if (receipt == null ||
        (pending != null &&
            receipt.phase != RoutineCreationReceiptPhase.committed) ||
        createRoutineDigest(receipt.routine) != identity.createdRoutineDigest ||
        !_notifier.routinesSnapshot.contains(receipt.routine)) {
      return CreateRoutineSnapshotAcknowledgement.effectUncertain(
        receiptIdentity: identity,
      );
    }
    return CreateRoutineSnapshotAcknowledgement.captured(
      receiptIdentity: identity,
      routines: _notifier.routinesSnapshot,
    );
  }

  Future<CreateRoutineCompensationAcknowledgement> compensate(
    CreateRoutineReceiptIdentity identity,
  ) async {
    try {
      final disposition = await _notifier.compensateRoutineCreation(
        _claim(identity),
      );
      return CreateRoutineCompensationAcknowledgement(
        receiptIdentity: identity,
        disposition: switch (disposition) {
          RoutineCreationCompensationDisposition.reverted =>
            CreateRoutineCompensationDisposition.reverted,
          RoutineCreationCompensationDisposition.alreadyAbsent =>
            CreateRoutineCompensationDisposition.alreadyAbsent,
          RoutineCreationCompensationDisposition.conflict ||
          RoutineCreationCompensationDisposition.unknownToken ||
          RoutineCreationCompensationDisposition.effectUncertain =>
            CreateRoutineCompensationDisposition.effectUncertain,
        },
      );
    } catch (error) {
      return CreateRoutineCompensationAcknowledgement(
        receiptIdentity: identity,
        disposition: CreateRoutineCompensationDisposition.effectUncertain,
        errorMessage: '$error',
      );
    }
  }

  Future<CreateRoutineSuccessAcknowledgement> recordSuccess(
    CreateRoutineSuccessIdentity identity,
  ) async {
    final disposition = await _notifier.prepareRoutineCreationSettlement(
      _claim(identity.receiptIdentity),
      isStillValid: () => _isOwnerCurrent(identity.runtime.owner),
    );
    return CreateRoutineSuccessAcknowledgement(
      identity: identity,
      disposition: switch (disposition) {
        RoutineCreationSettlementDisposition.prepared =>
          CreateRoutineSuccessDisposition.acknowledged,
        RoutineCreationSettlementDisposition.released =>
          CreateRoutineSuccessDisposition.released,
        RoutineCreationSettlementDisposition.ownerExpired =>
          CreateRoutineSuccessDisposition.ownerExpired,
        RoutineCreationSettlementDisposition.conflict ||
        RoutineCreationSettlementDisposition.unknownToken ||
        RoutineCreationSettlementDisposition.effectUncertain =>
          CreateRoutineSuccessDisposition.effectUncertain,
      },
    );
  }

  Future<CreateRoutineSuccessReleaseAcknowledgement> releaseSuccess(
    CreateRoutineSuccessIdentity identity,
  ) async {
    final released = await _notifier.releaseRoutineCreationSettlement(
      _claim(identity.receiptIdentity),
    );
    return CreateRoutineSuccessReleaseAcknowledgement(
      identity: identity,
      disposition: released
          ? CreateRoutineSuccessReleaseDisposition.released
          : CreateRoutineSuccessReleaseDisposition.effectUncertain,
    );
  }

  RoutineCreationReceiptBinding _binding(
    CreateRoutineRuntimeIdentity identity,
    String requestDigest,
  ) => RoutineCreationReceiptBinding(
    conversationId: identity.owner.conversationId,
    interactionGeneration: identity.owner.interactionGeneration,
    toolCallId: identity.toolCallId,
    toolName: identity.toolName,
    argumentDigest: identity.argumentDigest,
    requestDigest: requestDigest,
  );

  CreateRoutineReceiptIdentity _receiptIdentity(
    CreateRoutineRuntimeIdentity runtime,
    RoutineCreationReceipt receipt,
  ) => CreateRoutineReceiptIdentity(
    runtime: runtime,
    compensationToken: receipt.token,
    requestDigest: receipt.binding.requestDigest,
    createdRoutineDigest: receipt.routineDigest,
  );

  RoutineCreationReceiptClaim _claim(CreateRoutineReceiptIdentity identity) =>
      RoutineCreationReceiptClaim(
        token: identity.compensationToken,
        binding: _binding(identity.runtime, identity.requestDigest),
        routineDigest: identity.createdRoutineDigest,
      );
}
