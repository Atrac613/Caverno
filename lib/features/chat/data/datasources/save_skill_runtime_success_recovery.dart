part of 'save_skill_tool_runtime_adapter.dart';

extension on _SaveSkillRuntimeBridge {
  Future<SkillSaveAcknowledgement> _uncertainSuccess(
    SaveSkillOperationIdentity identity,
    SaveSkillWriteAcknowledgement write,
  ) async {
    final successIdentity = SaveSkillSuccessIdentity(
      mutation: write.identity,
      compensationToken: write.compensationToken!,
      savedSkillDigest: saveSkillDigest(write.skill!),
    );
    try {
      final reconciliation = await _reconcileSuccess(successIdentity);
      if (reconciliation.identity == successIdentity &&
          reconciliation.disposition ==
              SaveSkillSuccessDisposition.acknowledged) {
        return SkillSaveAcknowledgement.acknowledged(identity: identity);
      }
      if (reconciliation.identity != successIdentity) {
        _observe(SaveSkillRuntimeDisposition.boundaryMismatch);
      }
    } catch (_) {
      // Compensation below retains the exact receipt when reconciliation fails.
    }
    _observe(SaveSkillRuntimeDisposition.effectUncertain);
    await _compensateWrite(
      identity,
      write.identity,
      write.compensationToken!,
      reconciledError: 'Skill success settlement failed.',
    );
    return SkillSaveAcknowledgement.effectUncertain(identity: identity);
  }
}
