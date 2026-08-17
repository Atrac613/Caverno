import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';

/// The message left for the user when the tool loop stops retrying a call.
///
/// The loop aborts after the same call fails twice, and the user then needs
/// two things the old single-sentence notice did not give them:
///
/// * why re-issuing will not help, attributed to whatever actually refused —
///   a built-in tool rejecting its own arguments is not a server problem, and
///   saying "check your server configuration" sends the reader to the LLM
///   endpoint for a local `edit_file` whose `old_text` was not in the file;
/// * what the turn already wrote to disk, because an abort can follow several
///   successful edits and used to report only the failure that stopped it.
final class ToolLoopAbortNotice {
  const ToolLoopAbortNotice({
    FileMutationEvidencePolicy mutations = const FileMutationEvidencePolicy(),
  }) : _mutations = mutations;

  final FileMutationEvidencePolicy _mutations;

  /// Builds the notice appended to the assistant message on abort.
  ///
  /// [executedToolResults] is the whole turn's results, not the failing
  /// batch's: the edits worth reporting usually happened several iterations
  /// earlier.
  String build({
    required String toolName,
    required String? errorMessage,
    required bool isApprovalDenial,
    required bool isExternalMcpResult,
    required List<ToolResultInfo> executedToolResults,
  }) {
    final buffer = StringBuffer('\n');
    if (isApprovalDenial) {
      buffer
        ..writeln(
          'The command ($toolName) was blocked by approval and will keep '
          'being blocked if re-issued unchanged. Approve it manually or take '
          'a different approach.',
        )
        ..writeln('Reason: $errorMessage');
    } else {
      buffer
        ..writeln(
          isExternalMcpResult
              ? 'The MCP tool ($toolName) failed twice with the same '
                    'arguments, so the turn stopped retrying it. Check that '
                    'the MCP server providing it is reachable and configured.'
              : 'The tool ($toolName) failed twice with the same arguments, '
                    'so the turn stopped retrying it. The tool rejected those '
                    'arguments; this is not a server or endpoint problem.',
        )
        ..writeln('Error: $errorMessage');
    }
    final changed = changedFilePaths(executedToolResults);
    if (changed.isNotEmpty) {
      buffer.writeln(
        'Already changed in this turn: ${changed.join(', ')}',
      );
    }
    return buffer.toString();
  }

  /// Paths this turn successfully mutated, in the order they were written.
  ///
  /// Read from the tool results themselves rather than from anything the
  /// model said, so the list cannot include a file the model only intended to
  /// change — which is exactly the file an abort is usually stuck on.
  List<String> changedFilePaths(List<ToolResultInfo> executedToolResults) {
    final paths = <String>[];
    for (final toolResult in executedToolResults) {
      if (!_mutations.isMutationToolName(toolResult.name)) continue;
      if (!_mutations.isSuccessfulResult(toolResult)) continue;
      final path =
          _mutations.resultPayloadPath(toolResult.result) ??
          _mutations.argumentPath(toolResult.arguments);
      if (path == null || path.isEmpty || paths.contains(path)) continue;
      paths.add(path);
    }
    return paths;
  }
}
