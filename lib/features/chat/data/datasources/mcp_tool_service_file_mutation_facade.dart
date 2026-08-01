import 'built_in_filesystem_tool_handler.dart';
import 'file_mutation_runtime_contract.dart';
import 'filesystem_tools.dart';

/// Exact effect boundary for owner-scoped file mutation runtimes.
mixin McpToolServiceFileMutationFacade {
  BuiltInFilesystemToolHandler get filesystemToolHandler;

  Future<
    FileMutationRuntimeAcknowledgement<
      FileMutationRollbackCapture<TextFileSnapshot>
    >
  >
  captureFileMutationBefore(FileMutationRuntimeIdentity identity) =>
      filesystemToolHandler.captureFileMutationBefore(identity);

  Future<FileMutationRuntimeAcknowledgement<String>>
  readFileMutationFingerprint(FileMutationRuntimeIdentity identity) =>
      filesystemToolHandler.readFileMutationFingerprint(identity);

  Future<FileMutationExecutionAcknowledgement> executeRawFileMutation(
    FileMutationEffectRequest<TextFileSnapshot> request,
    FileMutationEffectAuthorization authorization,
  ) => filesystemToolHandler.executeRawFileMutation(request, authorization);

  Future<FileMutationRuntimeAcknowledgement<FileMutationRollbackRecordReceipt>>
  recordFileMutation(
    FileMutationRollbackRecordRequest<TextFileSnapshot> request,
  ) => filesystemToolHandler.recordFileMutation(request);

  Future<FileMutationCompensationAcknowledgement> compensateFileMutation(
    FileMutationCompensationRequest<TextFileSnapshot> request,
  ) => filesystemToolHandler.compensateFileMutation(request);
}
