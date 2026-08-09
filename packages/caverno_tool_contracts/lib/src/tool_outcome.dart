/// Lifecycle state reported by a single background-process tool result.
enum ToolProcessState { running, exited }

/// A single file effect reported by a first-party mutation tool.
class ToolFileMutation {
  const ToolFileMutation({
    required this.path,
    this.contentHash,
    this.byteSize,
    this.changed,
  }) : assert(byteSize == null || byteSize >= 0);

  final String path;
  final String? contentHash;
  final int? byteSize;
  final bool? changed;

  Map<String, dynamic> toJson() => {
    'path': path,
    if (contentHash != null) 'content_hash': contentHash,
    if (byteSize != null) 'byte_size': byteSize,
    if (changed != null) 'changed': changed,
  };

  static ToolFileMutation? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final path = json['path'];
    if (path is! String || path.trim().isEmpty) return null;
    final rawHash = json['content_hash'];
    final rawByteSize = json['byte_size'];
    final rawChanged = json['changed'];
    return ToolFileMutation(
      path: path,
      contentHash: rawHash is String && rawHash.isNotEmpty ? rawHash : null,
      byteSize: ToolOutcome._nonNegativeInt(rawByteSize),
      changed: rawChanged is bool ? rawChanged : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolFileMutation &&
          other.path == path &&
          other.contentHash == contentHash &&
          other.byteSize == byteSize &&
          other.changed == changed;

  @override
  int get hashCode => Object.hash(path, contentHash, byteSize, changed);

  @override
  String toString() =>
      'ToolFileMutation(path: $path, contentHash: $contentHash, '
      'byteSize: $byteSize, changed: $changed)';
}

/// Whole-file identity reported by a first-party read tool.
class ToolReadOutcome {
  const ToolReadOutcome({
    required this.path,
    required this.contentHash,
    required this.byteSize,
    required this.lineCount,
  }) : assert(byteSize >= 0),
       assert(lineCount >= 0);

  final String path;
  final String contentHash;
  final int byteSize;
  final int lineCount;

  Map<String, dynamic> toJson() => {
    'path': path,
    'content_hash': contentHash,
    'byte_size': byteSize,
    'line_count': lineCount,
  };

  static ToolReadOutcome? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final path = json['path'];
    final contentHash = json['content_hash'];
    final byteSize = ToolOutcome._nonNegativeInt(json['byte_size']);
    final lineCount = ToolOutcome._nonNegativeInt(json['line_count']);
    if (path is! String ||
        path.trim().isEmpty ||
        contentHash is! String ||
        contentHash.isEmpty ||
        byteSize == null ||
        lineCount == null) {
      return null;
    }
    return ToolReadOutcome(
      path: path,
      contentHash: contentHash,
      byteSize: byteSize,
      lineCount: lineCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolReadOutcome &&
          other.path == path &&
          other.contentHash == contentHash &&
          other.byteSize == byteSize &&
          other.lineCount == lineCount;

  @override
  int get hashCode => Object.hash(path, contentHash, byteSize, lineCount);

  @override
  String toString() =>
      'ToolReadOutcome(path: $path, contentHash: $contentHash, '
      'byteSize: $byteSize, lineCount: $lineCount)';
}

/// Counts reported by a recognized first-party test runner.
class ToolTestOutcome {
  const ToolTestOutcome({
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.command,
  }) : assert(passedCount >= 0),
       assert(failedCount >= 0),
       assert(skippedCount >= 0);

  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final String command;

  Map<String, dynamic> toJson() => {
    'passed_count': passedCount,
    'failed_count': failedCount,
    'skipped_count': skippedCount,
    'command': command,
  };

  static ToolTestOutcome? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final passedCount = ToolOutcome._nonNegativeInt(json['passed_count']);
    final failedCount = ToolOutcome._nonNegativeInt(json['failed_count']);
    final skippedCount = ToolOutcome._nonNegativeInt(json['skipped_count']);
    final command = json['command'];
    if (passedCount == null ||
        failedCount == null ||
        skippedCount == null ||
        command is! String ||
        command.trim().isEmpty) {
      return null;
    }
    return ToolTestOutcome(
      passedCount: passedCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      command: command,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolTestOutcome &&
          other.passedCount == passedCount &&
          other.failedCount == failedCount &&
          other.skippedCount == skippedCount &&
          other.command == command;

  @override
  int get hashCode =>
      Object.hash(passedCount, failedCount, skippedCount, command);

  @override
  String toString() =>
      'ToolTestOutcome(passedCount: $passedCount, failedCount: $failedCount, '
      'skippedCount: $skippedCount, command: $command)';
}

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
    this.fileMutations = const [],
    this.readOutcome,
    this.testOutcome,
    this.fileChanged,
    this.contentHash,
    this.diagnosticCount,
    this.diagnosticErrorCount,
    this.diagnosticWarningCount,
    this.testPassedCount,
    this.testFailedCount,
    this.testSkippedCount,
  }) : assert(diagnosticCount == null || diagnosticCount >= 0),
       assert(diagnosticErrorCount == null || diagnosticErrorCount >= 0),
       assert(diagnosticWarningCount == null || diagnosticWarningCount >= 0),
       assert(testPassedCount == null || testPassedCount >= 0),
       assert(testFailedCount == null || testFailedCount >= 0),
       assert(testSkippedCount == null || testSkippedCount >= 0);

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

  /// Files this tool attempted to mutate, with their resulting identities.
  final List<ToolFileMutation> fileMutations;

  /// Whole-file identity reported by a read operation.
  final ToolReadOutcome? readOutcome;

  /// Complete counts and command reported by a recognized test runner.
  final ToolTestOutcome? testOutcome;

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

  /// Number of tests the recognized verification runner observed as passed.
  final int? testPassedCount;

  /// Number of tests the recognized verification runner observed as failed.
  final int? testFailedCount;

  /// Number of tests the recognized verification runner observed as skipped.
  final int? testSkippedCount;

  /// Whether a mutation ran and left the file exactly as it was.
  bool get isNoOpMutation => effectiveFileChanged == false;

  /// Mutation status from the rich contract, with legacy scalar fallback.
  bool? get effectiveFileChanged {
    if (fileMutations.isNotEmpty) {
      final states = fileMutations.map((mutation) => mutation.changed);
      if (states.any((changed) => changed == true)) return true;
      if (states.every((changed) => changed == false)) return false;
    }
    return fileChanged;
  }

  /// Whole-file hash from the rich read contract, with legacy fallback.
  String? get effectiveContentHash => readOutcome?.contentHash ?? contentHash;

  int? get effectiveTestPassedCount =>
      testOutcome?.passedCount ?? testPassedCount;

  int? get effectiveTestFailedCount =>
      testOutcome?.failedCount ?? testFailedCount;

  int? get effectiveTestSkippedCount =>
      testOutcome?.skippedCount ?? testSkippedCount;

  /// Whether this outcome carries any fact at all.
  ///
  /// An outcome with nothing populated is equivalent to no outcome, and
  /// consumers should fall back to their existing text handling.
  bool get isEmpty =>
      exitCode == null &&
      processState == null &&
      fileMutations.isEmpty &&
      readOutcome == null &&
      testOutcome == null &&
      fileChanged == null &&
      contentHash == null &&
      diagnosticCount == null &&
      diagnosticErrorCount == null &&
      diagnosticWarningCount == null &&
      testPassedCount == null &&
      testFailedCount == null &&
      testSkippedCount == null;

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

  /// Whether all counts needed to verify a test-count claim are present.
  bool get hasCompleteTestCounts =>
      effectiveTestPassedCount != null &&
      effectiveTestFailedCount != null &&
      effectiveTestSkippedCount != null;

  Map<String, dynamic> toJson() => {
    if (exitCode != null) 'exit_code': exitCode,
    if (processState != null) 'process_state': processState!.name,
    if (fileMutations.isNotEmpty)
      'file_mutations': fileMutations
          .map((mutation) => mutation.toJson())
          .toList(growable: false),
    if (readOutcome != null) 'read_outcome': readOutcome!.toJson(),
    if (testOutcome != null) 'test_outcome': testOutcome!.toJson(),
    if (fileChanged != null) 'changed': fileChanged,
    if (contentHash != null) 'content_hash': contentHash,
    if (diagnosticCount != null) 'diagnostic_count': diagnosticCount,
    if (diagnosticErrorCount != null)
      'diagnostic_error_count': diagnosticErrorCount,
    if (diagnosticWarningCount != null)
      'diagnostic_warning_count': diagnosticWarningCount,
    if (testPassedCount != null) 'test_passed_count': testPassedCount,
    if (testFailedCount != null) 'test_failed_count': testFailedCount,
    if (testSkippedCount != null) 'test_skipped_count': testSkippedCount,
  };

  static ToolOutcome? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final rawExitCode = json['exit_code'];
    final rawProcessState = json['process_state'];
    final rawFileMutations = json['file_mutations'];
    final rawReadOutcome = json['read_outcome'];
    final rawTestOutcome = json['test_outcome'];
    final rawChanged = json['changed'];
    final rawHash = json['content_hash'];
    final rawDiagnosticCount = json['diagnostic_count'];
    final rawDiagnosticErrorCount = json['diagnostic_error_count'];
    final rawDiagnosticWarningCount = json['diagnostic_warning_count'];
    final rawTestPassedCount = json['test_passed_count'];
    final rawTestFailedCount = json['test_failed_count'];
    final rawTestSkippedCount = json['test_skipped_count'];
    final outcome = ToolOutcome(
      exitCode: rawExitCode is num ? rawExitCode.toInt() : null,
      processState: switch (rawProcessState) {
        'running' => ToolProcessState.running,
        'exited' => ToolProcessState.exited,
        _ => null,
      },
      fileMutations: rawFileMutations is List
          ? rawFileMutations
                .whereType<Map>()
                .map(
                  (item) =>
                      ToolFileMutation.fromJson(item.cast<String, dynamic>()),
                )
                .whereType<ToolFileMutation>()
                .toList(growable: false)
          : const [],
      readOutcome: rawReadOutcome is Map
          ? ToolReadOutcome.fromJson(rawReadOutcome.cast<String, dynamic>())
          : null,
      testOutcome: rawTestOutcome is Map
          ? ToolTestOutcome.fromJson(rawTestOutcome.cast<String, dynamic>())
          : null,
      fileChanged: rawChanged is bool ? rawChanged : null,
      contentHash: rawHash is String && rawHash.isNotEmpty ? rawHash : null,
      diagnosticCount: _nonNegativeInt(rawDiagnosticCount),
      diagnosticErrorCount: _nonNegativeInt(rawDiagnosticErrorCount),
      diagnosticWarningCount: _nonNegativeInt(rawDiagnosticWarningCount),
      testPassedCount: _nonNegativeInt(rawTestPassedCount),
      testFailedCount: _nonNegativeInt(rawTestFailedCount),
      testSkippedCount: _nonNegativeInt(rawTestSkippedCount),
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
          _listEquals(other.fileMutations, fileMutations) &&
          other.readOutcome == readOutcome &&
          other.testOutcome == testOutcome &&
          other.fileChanged == fileChanged &&
          other.contentHash == contentHash &&
          other.diagnosticCount == diagnosticCount &&
          other.diagnosticErrorCount == diagnosticErrorCount &&
          other.diagnosticWarningCount == diagnosticWarningCount &&
          other.testPassedCount == testPassedCount &&
          other.testFailedCount == testFailedCount &&
          other.testSkippedCount == testSkippedCount;

  @override
  int get hashCode => Object.hash(
    exitCode,
    processState,
    Object.hashAll(fileMutations),
    readOutcome,
    testOutcome,
    fileChanged,
    contentHash,
    diagnosticCount,
    diagnosticErrorCount,
    diagnosticWarningCount,
    testPassedCount,
    testFailedCount,
    testSkippedCount,
  );

  @override
  String toString() =>
      'ToolOutcome(exitCode: $exitCode, processState: $processState, '
      'fileMutations: $fileMutations, readOutcome: $readOutcome, '
      'testOutcome: $testOutcome, '
      'fileChanged: $fileChanged, '
      'contentHash: $contentHash, diagnosticCount: $diagnosticCount, '
      'diagnosticErrorCount: $diagnosticErrorCount, '
      'diagnosticWarningCount: $diagnosticWarningCount, '
      'testPassedCount: $testPassedCount, testFailedCount: $testFailedCount, '
      'testSkippedCount: $testSkippedCount)';

  static bool _listEquals<T>(List<T> left, List<T> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
