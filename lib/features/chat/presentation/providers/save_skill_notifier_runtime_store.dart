import '../../data/datasources/save_skill_runtime_contract.dart';
import '../../domain/entities/chat_turn_owner.dart';
import 'skills_notifier.dart';

typedef SaveSkillRuntimeOwnerCurrentCallback =
    bool Function(ChatTurnOwner owner);

/// Exact receipt adapter between the save-skill runtime and [SkillsNotifier].
final class SaveSkillNotifierRuntimeStore {
  const SaveSkillNotifierRuntimeStore({
    required SkillsNotifier notifier,
    required SaveSkillRuntimeOwnerCurrentCallback isOwnerCurrent,
  }) : _notifier = notifier,
       _isOwnerCurrent = isOwnerCurrent;

  final SkillsNotifier _notifier;
  final SaveSkillRuntimeOwnerCurrentCallback _isOwnerCurrent;

  SaveSkillSnapshotAcknowledgement captureSnapshot(
    SaveSkillRuntimeIdentity identity,
  ) {
    if (!_isOwnerCurrent(identity.owner)) {
      return SaveSkillSnapshotAcknowledgement.rejected(identity: identity);
    }
    return SaveSkillSnapshotAcknowledgement.captured(
      identity: identity,
      skills: _notifier.skillsSnapshot,
    );
  }

  Future<SaveSkillWriteAcknowledgement> write(
    SaveSkillRuntimeWriteRequest request,
  ) async {
    final identity = request.identity;
    final owner = identity.catalog.runtime.owner;
    final bool ownerCurrentBeforeEffect;
    try {
      ownerCurrentBeforeEffect = _isOwnerCurrent(owner);
    } catch (error) {
      return SaveSkillWriteAcknowledgement.rejectedBeforeEffect(
        identity: identity,
        errorMessage: 'Failed to save skill: $error',
      );
    }
    if (!ownerCurrentBeforeEffect) {
      return SaveSkillWriteAcknowledgement.ownerExpiredBeforeEffect(
        identity: identity,
      );
    }
    final SkillMutationWriteAttempt attempt;
    try {
      attempt = await _notifier.upsertMarkdownWithReceipt(
        identity: identity,
        isOwnerCurrent: () => _isOwnerCurrent(owner),
        existingId: request.request.existingId,
        markdown: request.request.markdown,
      );
    } catch (error) {
      return SaveSkillWriteAcknowledgement.rejectedBeforeEffect(
        identity: identity,
        errorMessage: 'Failed to save skill: $error',
      );
    }
    bool ownerCurrentAfterEffect() {
      try {
        return _isOwnerCurrent(owner);
      } catch (_) {
        return false;
      }
    }

    return switch (attempt.disposition) {
      SkillMutationWriteDisposition.committed when !ownerCurrentAfterEffect() =>
        SaveSkillWriteAcknowledgement.ownerExpiredAfterEffect(
          identity: identity,
          compensationToken: attempt.receipt!.token,
        ),
      SkillMutationWriteDisposition.committed =>
        SaveSkillWriteAcknowledgement.committed(
          identity: identity,
          skill: attempt.receipt!.after,
          compensationToken: attempt.receipt!.token,
        ),
      SkillMutationWriteDisposition.rejectedBeforeEffect =>
        SaveSkillWriteAcknowledgement.rejectedBeforeEffect(
          identity: identity,
          errorMessage: 'Failed to save skill: ${attempt.error}',
        ),
      SkillMutationWriteDisposition.ownerExpiredBeforeEffect =>
        SaveSkillWriteAcknowledgement.ownerExpiredBeforeEffect(
          identity: identity,
        ),
      SkillMutationWriteDisposition.effectUncertainAfterEffect =>
        SaveSkillWriteAcknowledgement.effectUncertainAfterEffect(
          identity: identity,
          compensationToken: attempt.receipt!.token,
          errorMessage: 'Failed to save skill: ${attempt.error}',
        ),
    };
  }

  Future<SaveSkillCompensationAcknowledgement> compensate(
    SaveSkillCompensationRequest request,
  ) async {
    try {
      final disposition = await _notifier.compensateMutation(
        request.identity,
        request.compensationToken,
      );
      return SaveSkillCompensationAcknowledgement(
        identity: request.identity,
        compensationToken: request.compensationToken,
        disposition: switch (disposition) {
          SkillMutationCompensationDisposition.compensated =>
            SaveSkillCompensationDisposition.compensated,
          SkillMutationCompensationDisposition.alreadyAbsent =>
            SaveSkillCompensationDisposition.alreadyAbsent,
          SkillMutationCompensationDisposition.conflict =>
            SaveSkillCompensationDisposition.retained,
          SkillMutationCompensationDisposition.unknownToken =>
            SaveSkillCompensationDisposition.effectUncertain,
        },
      );
    } catch (_) {
      return SaveSkillCompensationAcknowledgement(
        identity: request.identity,
        compensationToken: request.compensationToken,
        disposition: SaveSkillCompensationDisposition.effectUncertain,
      );
    }
  }

  Future<SaveSkillSuccessAcknowledgement> recordSuccess(
    SaveSkillSuccessIdentity identity,
  ) async {
    final disposition = await _notifier.settleMutation(
      identity: identity.mutation,
      token: identity.compensationToken,
      savedSkillDigest: identity.savedSkillDigest,
      isOwnerCurrent: () =>
          _isOwnerCurrent(identity.mutation.catalog.runtime.owner),
    );
    return SaveSkillSuccessAcknowledgement(
      identity: identity,
      disposition: switch (disposition) {
        SkillMutationSettlementDisposition.settled =>
          SaveSkillSuccessDisposition.acknowledged,
        SkillMutationSettlementDisposition.ownerExpired =>
          SaveSkillSuccessDisposition.ownerExpired,
        SkillMutationSettlementDisposition.conflict ||
        SkillMutationSettlementDisposition.unknownToken ||
        SkillMutationSettlementDisposition.effectUncertain =>
          SaveSkillSuccessDisposition.effectUncertain,
      },
    );
  }

  Future<SaveSkillSuccessAcknowledgement> reconcileSuccess(
    SaveSkillSuccessIdentity identity,
  ) async {
    final disposition = await _notifier.reconcileMutationSettlement(
      identity: identity.mutation,
      token: identity.compensationToken,
      savedSkillDigest: identity.savedSkillDigest,
    );
    return SaveSkillSuccessAcknowledgement(
      identity: identity,
      disposition: disposition == SkillMutationSettlementDisposition.settled
          ? SaveSkillSuccessDisposition.acknowledged
          : SaveSkillSuccessDisposition.effectUncertain,
    );
  }
}
