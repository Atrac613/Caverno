/// Lifecycle state reported by a single background-process tool result.
enum ToolProcessState { running, exited }

/// Structured outcome a first-party tool reports about its own execution.
///
/// Tool results travel as an opaque `result` string plus a coarse success
/// flag, so every consumer that needs a fact about what happened re-derives it
/// by parsing that string. `ToolFailureClassifier`, the workflow failure
/// detector, and the coding output guardrail each decode the same JSON
/// independently, and phrases in tool output end up load-bearing.
///
/// A `ToolOutcome` carries those facts alongside the string instead. The
/// string stays authoritative for the model — this is what the *harness*
/// reads.
///
/// Only fields a tool genuinely knows belong here. A tool that cannot
/// determine its own outcome reports nothing rather than a guessed value: a
/// fabricated fact is worse than an absent one, because consumers are entitled
/// to trust what they find.
///
/// Fields are added alongside the producer and consumer that need them, so an
/// outcome never carries a field nothing populates. See LL34 in
/// `docs/local_llm_agent_roadmap.md`.
class ToolOutcome {
  const ToolOutcome({
    this.exitCode,
    this.processState,
    this.fileChanged,
    this.contentHash,
    this.diagnosticCount,
    this.diagnosticErrorCount,
    this.diagnosticWarningCount,
  }) : assert(diagnosticCount == null || diagnosticCount >= 0),
       assert(diagnosticErrorCount == null || diagnosticErrorCount >= 0),
       assert(diagnosticWarningCount == null || diagnosticWarningCount >= 0);

  /// Process exit status for tools that run a command.
  ///
  /// `0` means the command ran and succeeded; a non-zero value means it ran
  /// and failed. `null` means the tool does not run commands, or the process
  /// never reached an exit (it was denied, timed out, or failed to spawn) —
  /// those are distinct from a failing exit status and must not be flattened
  /// into one.
  final int? exitCode;

  /// Whether a background process is still running or has reached an exit.
  ///
  /// This is independent of [exitCode]: a running process has no exit status,
  /// while an exited process carries one when the process backend reports it.
  /// Null means the tool did not report a single-process lifecycle state.
  final ToolProcessState? processState;

  /// Whether a write actually altered the file's content.
  ///
  /// A byte-identical write succeeds and reports the same byte count as a real
  /// one, so without this a no-op edit is indistinguishable from progress —
  /// the condition that lets an edit, re-read, edit loop run forever. Null
  /// when the tool does not mutate files, or could not determine it.
  final bool? fileChanged;

  /// Hash of the whole file a read returned content from.
  ///
  /// A read has no pass/fail outcome, but it has an identity. Two reads of the
  /// same file through *different* paging windows return different text while
  /// describing the same unchanged file, so comparing the returned bodies calls
  /// that a change; comparing hashes does not. Null when the tool does not read
  /// files, or the file was too large to hash — absent means unknown, never
  /// unchanged.
  final String? contentHash;

  /// Number of diagnostics a diagnostics producer observed.
  ///
  /// This is counted before the rendered payload is capped, so prompt
  /// budgeting cannot turn omitted diagnostics into an apparent clean result.
  /// Null when the tool does not produce diagnostics.
  final int? diagnosticCount;

  /// Number of Error-severity diagnostics in [diagnosticCount].
  final int? diagnosticErrorCount;

  /// Number of Warning-severity diagnostics in [diagnosticCount].
  final int? diagnosticWarningCount;

  /// Whether a mutation ran and left the file exactly as it was.
  bool get isNoOpMutation => fileChanged == false;

  /// Whether this outcome carries any fact at all.
  ///
  /// An outcome with nothing populated is equivalent to no outcome, and
  /// consumers should fall back to their existing text handling.
  bool get isEmpty =>
      exitCode == null &&
      processState == null &&
      fileChanged == null &&
      contentHash == null &&
      diagnosticCount == null &&
      diagnosticErrorCount == null &&
      diagnosticWarningCount == null;

  bool get isNotEmpty => !isEmpty;

  /// Whether a command ran to completion and reported failure.
  ///
  /// False when no command ran, so a caller cannot mistake "no exit status"
  /// for success.
  bool get hasFailingExitCode => exitCode != null && exitCode != 0;

  /// Whether a command ran to completion and reported success.
  bool get hasSucceedingExitCode => exitCode == 0;

  bool get isProcessRunning => processState == ToolProcessState.running;

  bool get isProcessTerminal => processState == ToolProcessState.exited;

  Map<String, dynamic> toJson() => {
    if (exitCode != null) 'exit_code': exitCode,
    if (processState != null) 'process_state': processState!.name,
    if (fileChanged != null) 'changed': fileChanged,
    if (contentHash != null) 'content_hash': contentHash,
    if (diagnosticCount != null) 'diagnostic_count': diagnosticCount,
    if (diagnosticErrorCount != null)
      'diagnostic_error_count': diagnosticErrorCount,
    if (diagnosticWarningCount != null)
      'diagnostic_warning_count': diagnosticWarningCount,
  };

  static ToolOutcome? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final rawExitCode = json['exit_code'];
    final rawProcessState = json['process_state'];
    final rawChanged = json['changed'];
    final rawHash = json['content_hash'];
    final rawDiagnosticCount = json['diagnostic_count'];
    final rawDiagnosticErrorCount = json['diagnostic_error_count'];
    final rawDiagnosticWarningCount = json['diagnostic_warning_count'];
    final outcome = ToolOutcome(
      exitCode: rawExitCode is num ? rawExitCode.toInt() : null,
      processState: switch (rawProcessState) {
        'running' => ToolProcessState.running,
        'exited' => ToolProcessState.exited,
        _ => null,
      },
      fileChanged: rawChanged is bool ? rawChanged : null,
      contentHash: rawHash is String && rawHash.isNotEmpty ? rawHash : null,
      diagnosticCount: _nonNegativeInt(rawDiagnosticCount),
      diagnosticErrorCount: _nonNegativeInt(rawDiagnosticErrorCount),
      diagnosticWarningCount: _nonNegativeInt(rawDiagnosticWarningCount),
    );
    return outcome.isEmpty ? null : outcome;
  }

  static int? _nonNegativeInt(Object? value) {
    if (value is! num) {
      return null;
    }
    final integer = value.toInt();
    return integer >= 0 ? integer : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolOutcome &&
          other.exitCode == exitCode &&
          other.processState == processState &&
          other.fileChanged == fileChanged &&
          other.contentHash == contentHash &&
          other.diagnosticCount == diagnosticCount &&
          other.diagnosticErrorCount == diagnosticErrorCount &&
          other.diagnosticWarningCount == diagnosticWarningCount;

  @override
  int get hashCode => Object.hash(
    exitCode,
    processState,
    fileChanged,
    contentHash,
    diagnosticCount,
    diagnosticErrorCount,
    diagnosticWarningCount,
  );

  @override
  String toString() =>
      'ToolOutcome(exitCode: $exitCode, processState: $processState, '
      'fileChanged: $fileChanged, '
      'contentHash: $contentHash, diagnosticCount: $diagnosticCount, '
      'diagnosticErrorCount: $diagnosticErrorCount, '
      'diagnosticWarningCount: $diagnosticWarningCount)';
}
