import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';

/// Detects fabricated terminal transcripts in a final answer: fenced code
/// blocks that present `$`-prefixed commands together with their output as if
/// they were executed, while no matching command-execution tool call ran in
/// the current turn.
///
/// Pure usage examples (command lines without interleaved output) are ignored
/// on purpose — only blocks that claim observed behavior are checked, which
/// keeps legitimate "how to run it" documentation out of scope.
class NarratedTranscriptClaimAssessment {
  const NarratedTranscriptClaimAssessment({required this.unexecutedCommands});

  /// Narrated command segments with no execution record, in narration order.
  final List<String> unexecutedCommands;

  bool get hasUnexecutedCommands => unexecutedCommands.isNotEmpty;

  static const int _maxListedCommands = 8;

  String buildNotice() {
    if (unexecutedCommands.isEmpty) {
      return '';
    }
    final listed = unexecutedCommands
        .take(_maxListedCommands)
        .map((command) => '`$command`')
        .join(', ');
    final omitted = unexecutedCommands.length - _maxListedCommands;
    final suffix = omitted > 0 ? ' (and $omitted more)' : '';
    return 'Transcript claim check: the response presents a terminal '
        'transcript, but the following command(s) have no execution record '
        'in this turn: $listed$suffix. Treat the transcript output shown for '
        'them as unverified.';
  }
}

class NarratedTranscriptClaimGuard {
  const NarratedTranscriptClaimGuard({
    this.toolCallExecutionPolicy = const ToolCallExecutionPolicy(),
  });

  final ToolCallExecutionPolicy toolCallExecutionPolicy;

  /// Shell prompt markers that mark a line as a narrated command. `>` is
  /// excluded on purpose: it collides with quotes, diffs, and continuation
  /// lines inside ordinary output.
  static final RegExp _promptLine = RegExp(r'^\s*[$%]\s+(\S.*)$');
  // Requires whitespace (or end of line) after `#` so program output such as
  // `#1 [ ] task` still counts as output rather than a shell comment.
  static final RegExp _commentLine = RegExp(r'^\s*#(?:\s|$)');
  static final RegExp _fenceLine = RegExp(r'^\s*(`{3,}|~{3,})');
  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _strippedRedirect = RegExp(
    r'(?:2>&1|[12]?>{1,2}\s*/dev/null)',
  );

  NarratedTranscriptClaimAssessment assess({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    List<String> additionalExecutedCommands = const [],
  }) {
    if (candidateResponse.trim().isEmpty) {
      return const NarratedTranscriptClaimAssessment(unexecutedCommands: []);
    }
    final narrated = _narratedTranscriptCommands(candidateResponse);
    if (narrated.isEmpty) {
      return const NarratedTranscriptClaimAssessment(unexecutedCommands: []);
    }

    final executedSegments = <String>{};
    for (final command in [
      ...executedCommandsFromToolResults(toolResults),
      ...additionalExecutedCommands,
    ]) {
      for (final segment in _splitCommandSegments(command)) {
        final normalized = _normalizeSegment(segment);
        if (normalized.isNotEmpty) {
          executedSegments.add(normalized);
        }
      }
    }

    final unexecuted = <String>[];
    final seen = <String>{};
    for (final narratedCommand in narrated) {
      for (final segment in _splitCommandSegments(narratedCommand)) {
        final normalized = _normalizeSegment(segment);
        if (normalized.isEmpty || _isIgnoredNarratedSegment(normalized)) {
          continue;
        }
        if (executedSegments.contains(normalized) ||
            !seen.add(normalized)) {
          continue;
        }
        unexecuted.add(normalized);
      }
    }
    return NarratedTranscriptClaimAssessment(
      unexecutedCommands: List<String>.unmodifiable(unexecuted),
    );
  }

  /// Commands issued through command-execution tools this turn. Denied or
  /// failed calls count as executed on purpose: this guard targets commands
  /// that were never issued at all, while failed-command success claims are
  /// covered by the dedicated failure-claim guards.
  List<String> executedCommandsFromToolResults(
    List<ToolResultInfo> toolResults,
  ) {
    final commands = <String>[];
    for (final toolResult in toolResults) {
      if (!toolCallExecutionPolicy.isCommandExecutionTool(toolResult.name)) {
        continue;
      }
      final command = toolCallExecutionPolicy.toolCommandArgument(
        toolResult.arguments,
      );
      if (command != null) {
        commands.add(command);
      }
    }
    return commands;
  }

  /// Extracts narrated command lines from fenced blocks that qualify as
  /// transcripts: at least one prompt-marked command line AND at least one
  /// output line (non-blank, not a command, not a comment).
  List<String> _narratedTranscriptCommands(String response) {
    final narrated = <String>[];
    var insideFence = false;
    var blockCommands = <String>[];
    var blockHasOutput = false;

    void closeBlock() {
      if (blockCommands.isNotEmpty && blockHasOutput) {
        narrated.addAll(blockCommands);
      }
      blockCommands = <String>[];
      blockHasOutput = false;
    }

    for (final line in response.split('\n')) {
      if (_fenceLine.hasMatch(line)) {
        if (insideFence) {
          closeBlock();
        }
        insideFence = !insideFence;
        continue;
      }
      if (!insideFence) {
        continue;
      }
      final promptMatch = _promptLine.firstMatch(line);
      if (promptMatch != null) {
        blockCommands.add(promptMatch.group(1)!.trim());
        continue;
      }
      if (line.trim().isEmpty || _commentLine.hasMatch(line)) {
        continue;
      }
      blockHasOutput = true;
    }
    // An unterminated trailing fence still counts: streamed answers may cut
    // the closing backticks off.
    closeBlock();
    return narrated;
  }

  /// Splits a shell command on `&&`, `||`, `;`, and newlines outside quotes,
  /// so one narrated line can be matched against segments of a compound
  /// executed command (and vice versa).
  List<String> _splitCommandSegments(String command) {
    final segments = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;

    void closeSegment() {
      final segment = current.toString().trim();
      if (segment.isNotEmpty) {
        segments.add(segment);
      }
      current.clear();
    }

    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (char == r'\' && !inSingle && i + 1 < command.length) {
        current.write(char);
        current.write(command[i + 1]);
        i++;
        continue;
      }
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
        current.write(char);
        continue;
      }
      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        current.write(char);
        continue;
      }
      if (!inSingle && !inDouble) {
        if (char == '\n' || char == ';') {
          closeSegment();
          continue;
        }
        if ((char == '&' || char == '|') &&
            i + 1 < command.length &&
            command[i + 1] == char) {
          closeSegment();
          i++;
          continue;
        }
      }
      current.write(char);
    }
    closeSegment();
    return segments;
  }

  String _normalizeSegment(String segment) {
    return segment
        .replaceAll(_strippedRedirect, ' ')
        .replaceAll(_whitespaceRun, ' ')
        .trim();
  }

  /// Narrated segments that must not be flagged: `cd` is routinely narrated
  /// while the harness passes `working_directory` as a tool argument instead.
  bool _isIgnoredNarratedSegment(String segment) {
    return segment == 'cd' || segment.startsWith('cd ');
  }
}
