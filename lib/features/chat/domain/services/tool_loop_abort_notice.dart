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
///   successful edits and used to report only the failure that stopped it;
/// * what the turn already ran, for the same reason. File evidence alone was
///   blind to work done through the shell: in session 0e94a103 the whole task
///   — `fvm use 3.47.1`, exit 0, `.fvmrc` moved 3.47.0 → 3.47.1 — landed four
///   loops before an unrelated read aborted the turn, and the user was shown
///   only "check the path with the user" about a file that never mattered. A
///   turn that did the work must never report as a turn that did nothing.
final class ToolLoopAbortNotice {
  const ToolLoopAbortNotice({
    FileMutationEvidencePolicy mutations = const FileMutationEvidencePolicy(),
  }) : _mutations = mutations;

  final FileMutationEvidencePolicy _mutations;

  /// Longest command echoed into the notice.
  static const int _maxCommandChars = 120;

  /// Tools whose successful runs are worth reporting back to the user.
  static const Set<String> _commandToolNames = <String>{
    'local_execute_command',
    'git_execute_command',
  };

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
    final ran = completedCommands(executedToolResults);
    if (ran.isNotEmpty) {
      buffer.writeln(
        'Already ran successfully in this turn: ${ran.join(', ')}',
      );
    }
    return buffer.toString();
  }

  /// Commands this turn ran to a clean exit, in the order first issued.
  ///
  /// A command's file effects cannot be enumerated the way an `edit_file`
  /// result's can, so the command itself is reported rather than a path. The
  /// verdict comes from [ToolOutcome.exitCode] rather than from any phrase in
  /// the output: an absent status means the process never reached an exit — it
  /// was denied, timed out, or failed to spawn — and is left out, because an
  /// unknown result must never read as a clean one.
  ///
  /// Read-only commands are reported alongside mutating ones. Telling the two
  /// apart would mean classifying a command string, and the line claims only
  /// what is actually known: these ran, and they exited cleanly.
  List<String> completedCommands(List<ToolResultInfo> executedToolResults) {
    // Insertion-ordered, so a re-run keeps the position of its first issue
    // while the latest verdict decides whether it is reported at all.
    final succeededByCommand = <String, bool>{};
    for (final toolResult in executedToolResults) {
      if (!_commandToolNames.contains(toolResult.name.trim().toLowerCase())) {
        continue;
      }
      final rawCommand = toolResult.arguments['command']?.toString().trim();
      if (rawCommand == null || rawCommand.isEmpty) continue;
      // Last run wins: a command that failed and was then re-run cleanly has
      // landed, and one that succeeded and then broke has not.
      succeededByCommand[_normalizeCommand(rawCommand)] =
          toolResult.outcome?.exitCode == 0;
    }
    return [
      for (final entry in succeededByCommand.entries)
        if (entry.value) '`${entry.key}`',
    ];
  }

  static String _normalizeCommand(String command) {
    final normalized = command.replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length > _maxCommandChars
        ? '${normalized.substring(0, _maxCommandChars)}…'
        : normalized;
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
