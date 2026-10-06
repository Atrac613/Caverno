import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'command_verification_reconciliation.dart';
import 'file_mutation_evidence_policy.dart';

/// Exact successful runners offered as hints, never as fresh review evidence.
final class ProjectTaskVerificationContext {
  ProjectTaskVerificationContext(
    List<({String command, String directory})> runs,
  ) : runs = List.unmodifiable(runs);

  final List<({String command, String directory})> runs;

  factory ProjectTaskVerificationContext.fromResults(
    List<ToolResultInfo> results,
  ) {
    var latestMutation = -1;
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final typed = result.outcome?.fileMutations;
      final mutated = typed?.isNotEmpty == true
          ? typed!.any((file) => file.changed == true)
          : const FileMutationEvidencePolicy().isMutationToolName(
                  result.name,
                ) &&
                const FileMutationEvidencePolicy().isSuccessfulResult(result);
      if (mutated) {
        latestMutation = index;
      }
    }
    final runs = <({String command, String directory})>[];
    final stale = CommandVerificationReconciliation.staleBackgroundResultIds(
      results,
    );
    for (final result in results.skip(latestMutation + 1)) {
      if (result.fromEarlierLoop ||
          result.changesSinceCapture.isNotEmpty ||
          stale.contains(result.id) ||
          CommandVerificationReconciliation.scopeOf(result)?.passed != true) {
        continue;
      }
      try {
        final decoded = jsonDecode(result.result);
        if (decoded is! Map<String, dynamic> ||
            decoded['execution_reused'] == true) {
          continue;
        }
        final command = decoded['command'] ?? result.arguments['command'];
        final directory =
            decoded['working_directory'] ??
            result.arguments['working_directory'];
        if (command is! String ||
            directory is! String ||
            command.isEmpty ||
            directory.isEmpty ||
            command.length > 2000 ||
            directory.length > 512) {
          continue;
        }
        final run = (command: command, directory: directory);
        if (!runs.contains(run)) runs.add(run);
      } on FormatException {
        continue;
      }
    }
    return ProjectTaskVerificationContext(runs.reversed.take(3).toList());
  }

  String get prompt => runs.isEmpty
      ? ''
      : '''Successful implementation verification commands (historical evidence):
${runs.map((run) => jsonEncode({'command': run.command, 'working_directory': run.directory})).join('\n')}
If rerunning verification, reuse the exact project interpreter and working directory unless current inspection shows they are unavailable. Inspect an existing project environment before proposing dependency installation. These successes do not establish current review inspection or settle a new failure.''';
}
