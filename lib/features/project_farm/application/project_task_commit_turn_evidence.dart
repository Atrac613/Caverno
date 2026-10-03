import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../chat/data/datasources/git_tools.dart';
import '../../chat/domain/entities/tool_call_info.dart';

/// Current owner-bound observations, never inferred from completion prose.
final class ProjectTaskCommitTurnEvidence {
  const ProjectTaskCommitTurnEvidence({
    required this.completedNormally,
    required this.mutationAttempted,
    required this.failed,
  });
  final bool completedNormally;
  final bool mutationAttempted;
  final bool failed;
  bool get mayRecover => completedNormally && !mutationAttempted && !failed;

  factory ProjectTaskCommitTurnEvidence.fromResults({
    required bool completedNormally,
    required Iterable<ToolResultInfo> results,
  }) {
    var mutationAttempted = false;
    var failed = false;
    for (final result in results) {
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(result.result);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } on FormatException {
        // Read tools can return plain text. Native process outcomes are typed.
      }
      final origin = ToolResultOrigin.fromPayload(payload);
      final exitCode = result.outcome?.exitCode ?? payload?['exit_code'];
      // Harness feedback declares that no tool ran. It is not a native
      // execution failure; the originating call still counts as an attempt.
      if (origin != ToolResultOrigin.harness) {
        failed |=
            origin == ToolResultOrigin.refusal ||
            origin == ToolResultOrigin.malformed ||
            payload?['ok'] == false ||
            payload?['success'] == false ||
            payload?['isSuccess'] == false ||
            payload?.containsKey('errorMessage') == true ||
            payload?.containsKey('error') == true ||
            result.result.trimLeft().startsWith('Error:');
      }
      failed |=
          (exitCode is num && exitCode != 0) ||
          (result.outcome?.diagnosticErrorCount ?? 0) > 0 ||
          (result.outcome?.testFailedCount ?? 0) > 0;
      final command = result.arguments['command'];
      final readOnly =
          const {
            'read_file',
            'inspect_file',
            'list_directory',
            'find_files',
            'search_files',
          }.contains(result.name) ||
          result.name == 'git_execute_command' &&
              command is String &&
              GitTools.isReadOnly(command);
      mutationAttempted |= !readOnly;
    }
    return ProjectTaskCommitTurnEvidence(
      completedNormally: completedNormally,
      mutationAttempted: mutationAttempted,
      failed: failed,
    );
  }
}
