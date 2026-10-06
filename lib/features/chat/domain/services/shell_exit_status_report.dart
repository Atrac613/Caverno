import 'literal_shell_words.dart';

/// A trailing echo that reports the preceding literal command's exit status.
/// The shell's own exit code belongs to echo and cannot prove that command ran
/// successfully. This recognizes evidence only, without changing approval.
final class ShellExitStatusReport {
  const ShellExitStatusReport._(this.command, this.label);

  final String command;
  final String label;

  static final _reporter = RegExp(
    r';\s*echo\s+"([A-Za-z_][A-Za-z0-9_]*)='
    r'(\$\{PIPESTATUS\[0\](?::-[A-Za-z0-9_./-]+)?\}|\$\?|\$\{\?\})"\s*$',
  );
  static final _outputLimiter = RegExp(
    r'\s*(?:2>&1\s*)?\|\s*(?:head|tail)\s+-(?:n\s*)?[1-9]\d*\s*$',
  );

  static ShellExitStatusReport? parse(String source) {
    if (source.contains('\n') || source.contains('\r')) return null;
    final reporter = _reporter.firstMatch(source);
    if (reporter == null) return null;
    final command = source.substring(0, reporter.start).trim();
    final limiter = _outputLimiter.firstMatch(command);
    // $? after a pipeline belongs to the pipeline, not necessarily its first
    // command. Only PIPESTATUS[0] identifies that command across shell options.
    if (limiter != null && !reporter[2]!.contains('PIPESTATUS')) return null;
    final invocation =
        (limiter == null ? command : command.substring(0, limiter.start))
            .trim()
            .replaceFirst(RegExp(r'\s+2>&1\s*$'), '');
    final words = LiteralShellWords.parse(invocation);
    // A negated check owns its expected-failure verdict, not PIPESTATUS[0].
    if (words == null || words.first == '!') return null;
    return ShellExitStatusReport._(command, reporter[1]!);
  }

  /// The final report line is emitted by the shell after the command finishes.
  /// Missing, truncated or nonnumeric reports never establish success.
  int? exitCode(String stdout) {
    final lines = stdout.trimRight().split(RegExp(r'\r?\n'));
    final last = lines.last;
    final prefix = '$label=';
    if (!last.startsWith(prefix)) return null;
    final value = last.substring(prefix.length);
    if (!RegExp(r'^\d+$').hasMatch(value)) return null;
    final code = int.tryParse(value);
    return code != null && code >= 0 && code <= 255 ? code : null;
  }

  /// Removes only a recognized shell report, so runner summaries stay terminal.
  String commandOutput(String stdout) {
    if (exitCode(stdout) == null) return stdout;
    final trimmed = stdout.trimRight();
    final lastNewline = trimmed.lastIndexOf('\n');
    return lastNewline < 0 ? '' : trimmed.substring(0, lastNewline).trimRight();
  }
}
