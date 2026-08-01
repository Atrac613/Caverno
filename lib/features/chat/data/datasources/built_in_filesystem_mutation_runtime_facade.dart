part of 'built_in_filesystem_tool_handler.dart';

extension BuiltInFilesystemMutationRuntimeFacade
    on BuiltInFilesystemToolHandler {
  Future<
    FileMutationRuntimeAcknowledgement<
      FileMutationRollbackCapture<TextFileSnapshot>
    >
  >
  captureFileMutationBefore(FileMutationRuntimeIdentity identity) =>
      _mutationEffectBoundary.captureBefore(identity);

  Future<FileMutationRuntimeAcknowledgement<String>>
  readFileMutationFingerprint(FileMutationRuntimeIdentity identity) =>
      _mutationEffectBoundary.fingerprint(identity);

  Future<FileMutationExecutionAcknowledgement> executeRawFileMutation(
    FileMutationEffectRequest<TextFileSnapshot> request,
    FileMutationEffectAuthorization authorization,
  ) => _mutationEffectBoundary.executeRaw(request, authorization);

  Future<FileMutationRuntimeAcknowledgement<FileMutationRollbackRecordReceipt>>
  recordFileMutation(
    FileMutationRollbackRecordRequest<TextFileSnapshot> request,
  ) => _mutationEffectBoundary.recordMutation(request);

  Future<FileMutationCompensationAcknowledgement> compensateFileMutation(
    FileMutationCompensationRequest<TextFileSnapshot> request,
  ) => _mutationEffectBoundary.compensate(request);
}
