part of 'built_in_filesystem_mutation_effect_boundary.dart';

extension BuiltInFilesystemMutationCompensation
    on BuiltInFilesystemMutationEffectBoundary {
  Future<FileMutationCompensationAcknowledgement> compensate(
    FileMutationCompensationRequest<TextFileSnapshot> request,
  ) async {
    final identity = request.identity;
    final capture = request.capture;
    if (!_captureIsExact(capture) ||
        request.expectedAfterFingerprint.trim().isEmpty) {
      return _compensation(
        request,
        FileMutationRuntimeCompensationDisposition.effectUncertain,
        'The compensation request did not match its rollback capture.',
      );
    }
    Future<FileMutationCompensationAcknowledgement> compensateFenced() async {
      final current = await fingerprint(identity);
      if (current.disposition !=
          FileMutationRuntimeAcknowledgementDisposition.completed) {
        return _compensation(
          request,
          FileMutationRuntimeCompensationDisposition.effectUncertain,
          current.message ?? 'The compensation precondition is unknown.',
        );
      }
      if (current.value != request.expectedAfterFingerprint) {
        return _compensation(
          request,
          FileMutationRuntimeCompensationDisposition.fingerprintConflict,
          'The target file changed after the mutation.',
        );
      }

      Object? restoreError;
      try {
        await _snapshotRestorer(
          path: capture.snapshot.path,
          existedBefore: capture.snapshot.exists,
          content: capture.snapshot.content,
        );
      } catch (error) {
        restoreError = error;
      }
      final restored = await fingerprint(identity);
      if (restored.disposition !=
          FileMutationRuntimeAcknowledgementDisposition.completed) {
        return _compensation(
          request,
          FileMutationRuntimeCompensationDisposition.effectUncertain,
          restored.message ?? 'The compensation postcondition is unknown.',
        );
      }
      if (restored.value != capture.beforeFingerprint) {
        return _compensation(
          request,
          restored.value == request.expectedAfterFingerprint
              ? FileMutationRuntimeCompensationDisposition.failed
              : FileMutationRuntimeCompensationDisposition.effectUncertain,
          restoreError == null
              ? 'The rollback snapshot was not restored.'
              : 'The rollback snapshot restore failed: $restoreError',
        );
      }

      final recordToken = request.recordToken;
      if (recordToken != null &&
          !_checkpointStore.removeRecordedMutation(
            identity.owner,
            recordToken: recordToken,
            compensationToken: capture.compensationToken,
          )) {
        return _compensation(
          request,
          FileMutationRuntimeCompensationDisposition.effectUncertain,
          'The exact rollback checkpoint could not be cleared.',
        );
      }
      return _compensation(
        request,
        FileMutationRuntimeCompensationDisposition.reverted,
      );
    }

    final settlement = await _checkpointStore.mutationPathFence
        .settleTransaction(
          path: identity.canonicalPath,
          transactionToken: capture.compensationToken,
          operation: compensateFenced,
          releaseWhen: (acknowledgement) =>
              acknowledgement.disposition ==
              FileMutationRuntimeCompensationDisposition.reverted,
        );
    if (settlement != null) {
      return settlement.value;
    }
    return _checkpointStore.mutationPathFence.runExclusive(
      identity.canonicalPath,
      compensateFenced,
    );
  }

  FileMutationCompensationAcknowledgement _compensation(
    FileMutationCompensationRequest<TextFileSnapshot> request,
    FileMutationRuntimeCompensationDisposition disposition, [
    String? message,
  ]) {
    return FileMutationCompensationAcknowledgement(
      identity: request.identity,
      compensationToken: request.capture.compensationToken,
      disposition: disposition,
      message: message,
    );
  }
}
