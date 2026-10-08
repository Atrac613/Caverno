import '../../../data/datasources/filesystem_tools.dart';
import '../../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';

/// Resolves unique mutation paths against the captured project root.
final class ChangedFileEvidence {
  const ChangedFileEvidence();
  static const _fileMutationEvidencePolicy = FileMutationEvidencePolicy();
  List<String> callPaths(
    List<ToolCallInfo> toolCalls, {
    bool dartOnly = true,
    required String? projectRoot,
  }) {
    final paths = <String>[];
    final seen = <String>{};
    for (final toolCall in toolCalls) {
      if (!_fileMutationEvidencePolicy.isMutationToolName(toolCall.name)) {
        continue;
      }
      final path = _fileMutationEvidencePolicy.argumentPath(toolCall.arguments);
      if (path == null || (dartOnly && !path.toLowerCase().endsWith('.dart'))) {
        continue;
      }
      final resolved = FilesystemTools.resolvePath(
        path,
        defaultRoot: projectRoot,
      );
      final normalized = resolved ?? path;
      if (seen.add(normalized)) {
        paths.add(normalized);
      }
    }
    return paths;
  }

  List<String> resultPaths(
    List<ToolResultInfo> toolResults, {
    bool dartOnly = true,
    required String? projectRoot,
  }) {
    final paths = <String>[];
    final seen = <String>{};
    for (final toolResult in toolResults) {
      if (!_fileMutationEvidencePolicy.isMutationToolName(toolResult.name)) {
        continue;
      }
      if (!_fileMutationEvidencePolicy.isSuccessfulResult(toolResult)) {
        continue;
      }
      final path = _fileMutationEvidencePolicy.pathForResult(toolResult);
      if (path == null || (dartOnly && !path.toLowerCase().endsWith('.dart'))) {
        continue;
      }
      final resolved = FilesystemTools.resolvePath(
        path,
        defaultRoot: projectRoot,
      );
      final normalized = resolved ?? path;
      if (seen.add(normalized)) {
        paths.add(normalized);
      }
    }
    return paths;
  }
}
