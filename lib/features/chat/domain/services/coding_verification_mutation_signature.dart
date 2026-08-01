import 'dart:convert';

import '../../data/datasources/filesystem_path_resolver.dart';
import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: coding-verification-mutation-signature

final class CodingVerificationMutationSignatureInput {
  CodingVerificationMutationSignatureInput({
    required List<ToolResultInfo> toolResults,
    required this.projectRoot,
  }) : toolResults = List<ToolResultInfo>.unmodifiable(
         toolResults.map(_freezeToolResult),
       );

  final List<ToolResultInfo> toolResults;
  final String? projectRoot;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) {
    return ToolResultInfo(
      id: result.id,
      name: result.name,
      arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
      result: result.result,
    );
  }
}

final class CodingVerificationMutationSignature {
  const CodingVerificationMutationSignature();

  static const _mutationEvidence = FileMutationEvidencePolicy();

  String? compute(CodingVerificationMutationSignatureInput input) {
    final entries = <Map<String, String>>[];
    for (final toolResult in input.toolResults) {
      if (!_mutationEvidence.isMutationToolName(toolResult.name)) {
        continue;
      }
      if (!_mutationEvidence.isSuccessfulResult(toolResult)) {
        continue;
      }
      final path = _mutationEvidence.pathForResult(toolResult);
      if (path == null || !path.toLowerCase().endsWith('.dart')) {
        continue;
      }
      final resolved = FilesystemPathResolver.resolve(
        path,
        defaultRoot: input.projectRoot,
      );
      entries.add({
        'id': toolResult.id,
        'name': toolResult.name,
        'path': resolved ?? path,
      });
    }
    if (entries.isEmpty) {
      return null;
    }
    return jsonEncode(entries);
  }
}
