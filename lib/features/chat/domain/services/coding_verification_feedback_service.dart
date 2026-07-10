import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../entities/conversation_workflow.dart';
import '../entities/tool_call_info.dart';
import 'coding_diagnostic_feedback_service.dart';
import 'dart_project_tooling.dart';

typedef CodingVerificationCommandRunner =
    Future<CodingVerificationCommandOutput> Function(
      CodingVerificationCommand command,
      Duration timeout,
    );

enum CodingVerificationTrigger { completionClaim, explicitRequest, quietPeriod }

class CodingVerificationCommand {
  const CodingVerificationCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

class CodingVerificationCommandOutput {
  const CodingVerificationCommandOutput({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    this.startError,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final String? startError;

  bool get ran => !timedOut && startError == null;
}

class CodingVerificationTargetBatch {
  const CodingVerificationTargetBatch({
    required this.packageRoot,
    required this.targets,
  });

  final String packageRoot;
  final List<String> targets;

  Map<String, dynamic> toJson({required String projectRoot}) {
    return {
      'package_root': packageRoot,
      'package_relative_path': DartProjectPath.relativePath(
        packageRoot,
        projectRoot,
      ),
      'targets': targets,
    };
  }
}

class CodingVerificationFailure {
  const CodingVerificationFailure({
    required this.testName,
    required this.message,
    this.absolutePath,
    this.line,
    this.column,
    this.stackTrace,
  });

  final String testName;
  final String message;
  final String? absolutePath;
  final int? line;
  final int? column;
  final String? stackTrace;

  String get dedupeKey {
    return [
      testName,
      absolutePath == null ? '' : DartProjectPath.pathKey(absolutePath!),
      line ?? '',
      column ?? '',
      message,
    ].join('|');
  }

  Map<String, dynamic> toJson({
    required String projectRoot,
    required int maxStackChars,
  }) {
    final stack = stackTrace?.trim();
    return {
      'test_name': testName,
      if (absolutePath != null) 'path': absolutePath,
      if (absolutePath != null)
        'relative_path': DartProjectPath.relativePath(
          absolutePath!,
          projectRoot,
        ),
      if (line != null) 'line': line,
      if (column != null) 'column': column,
      'message': message,
      if (stack != null && stack.isNotEmpty)
        'stack_trace': stack.length <= maxStackChars
            ? stack
            : '${stack.substring(0, maxStackChars)}...',
    };
  }
}

class CodingVerificationSnapshot {
  const CodingVerificationSnapshot({
    required this.providerName,
    required this.projectRoot,
    required this.changedPaths,
    required this.trigger,
    required this.validationStatus,
    required this.targetBatches,
    required this.failures,
    required this.telemetry,
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    this.reason,
    this.selectedAttempt,
  });

  final String providerName;
  final String projectRoot;
  final List<String> changedPaths;
  final CodingVerificationTrigger trigger;
  final ConversationExecutionValidationStatus validationStatus;
  final List<CodingVerificationTargetBatch> targetBatches;
  final List<CodingVerificationFailure> failures;
  final CodingVerificationTelemetry telemetry;
  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final String? reason;
  final CodingVerificationCommandAttempt? selectedAttempt;
}

class CodingVerificationFeedbackRun {
  const CodingVerificationFeedbackRun({
    required this.snapshot,
    required this.toolResult,
    this.evidenceToolResult,
  });

  final CodingVerificationSnapshot? snapshot;

  /// Failure-only feedback that may be sent to the model for repair.
  final ToolResultInfo? toolResult;

  /// Non-blocking evidence for final-answer claim validation.
  ///
  /// Unlike [toolResult], this is available for every collected verification
  /// run so callers can retain the exact command, targets, and observed test
  /// counts without changing repair-loop behavior.
  final ToolResultInfo? evidenceToolResult;
}

class CodingVerificationTelemetry {
  const CodingVerificationTelemetry({
    required this.durationMs,
    required this.attempts,
  });

  final int durationMs;
  final List<CodingVerificationCommandAttempt> attempts;

  int get commandAttemptCount => attempts.length;

  int get fallbackCommandCount =>
      commandAttemptCount == 0 ? 0 : commandAttemptCount - 1;

  int get timedOutCommandCount =>
      attempts.where((attempt) => attempt.timedOut).length;

  int get startErrorCommandCount =>
      attempts.where((attempt) => attempt.startError != null).length;

  Map<String, dynamic> toJson() {
    return {
      'duration_ms': durationMs,
      'command_attempt_count': commandAttemptCount,
      'fallback_command_count': fallbackCommandCount,
      'timed_out_command_count': timedOutCommandCount,
      'start_error_command_count': startErrorCommandCount,
      'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
    };
  }
}

class CodingVerificationCommandAttempt {
  const CodingVerificationCommandAttempt({
    required this.command,
    required this.exitCode,
    required this.durationMs,
    required this.timedOut,
    required this.validationStatus,
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    this.startError,
  });

  final CodingVerificationCommand command;
  final int exitCode;
  final int durationMs;
  final bool timedOut;
  final ConversationExecutionValidationStatus validationStatus;
  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final String? startError;

  Map<String, dynamic> toJson() {
    return {
      'executable': command.executable,
      'arguments': command.arguments,
      'working_directory': command.workingDirectory,
      'exit_code': exitCode,
      'duration_ms': durationMs,
      'timed_out': timedOut,
      'validation_status': validationStatus.name,
      'passed_count': passedCount,
      'failed_count': failedCount,
      'skipped_count': skippedCount,
      if (startError != null) 'start_error': startError,
    };
  }
}

class CodingVerificationFeedbackService {
  CodingVerificationFeedbackService({
    CodingVerificationCommandRunner? commandRunner,
    this.timeout = const Duration(seconds: 90),
    this.maxFailures = 5,
    this.maxStackChars = 1200,
  }) : _commandRunner = commandRunner ?? _runTestCommand;

  static const toolName = 'dart_test_feedback';
  static const schemaName = 'caverno_dart_test_feedback';
  static const evidenceToolName = 'dart_test_verification_evidence';
  static const evidenceSchemaName = 'caverno_dart_test_verification_evidence';
  static const providerName = 'dart_test_runner';

  final CodingVerificationCommandRunner _commandRunner;
  final Duration timeout;
  final int maxFailures;
  final int maxStackChars;

  Future<ToolResultInfo?> buildFeedbackToolResult({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required CodingVerificationTrigger trigger,
    DateTime? now,
  }) async {
    final run = await buildFeedbackRun(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
      trigger: trigger,
      now: now,
    );
    return run.toolResult;
  }

  Future<CodingVerificationFeedbackRun> buildFeedbackRun({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required CodingVerificationTrigger trigger,
    DateTime? now,
  }) async {
    final snapshot = await collectSnapshot(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
      trigger: trigger,
    );
    return CodingVerificationFeedbackRun(
      snapshot: snapshot,
      toolResult: _buildFeedbackToolResultFromSnapshot(snapshot, now: now),
      evidenceToolResult: _buildEvidenceToolResultFromSnapshot(
        snapshot,
        now: now,
      ),
    );
  }

  ToolResultInfo? _buildEvidenceToolResultFromSnapshot(
    CodingVerificationSnapshot? snapshot, {
    DateTime? now,
  }) {
    if (snapshot == null) {
      return null;
    }

    return ToolResultInfo(
      id: '${evidenceToolName}_${(now ?? DateTime.now()).microsecondsSinceEpoch}',
      name: evidenceToolName,
      arguments: {
        'project_root': snapshot.projectRoot,
        'changed_paths': snapshot.changedPaths,
        'trigger': snapshot.trigger.name,
      },
      result: jsonEncode({
        'schema': evidenceSchemaName,
        ..._snapshotEvidencePayload(snapshot),
      }),
    );
  }

  ToolResultInfo? _buildFeedbackToolResultFromSnapshot(
    CodingVerificationSnapshot? snapshot, {
    DateTime? now,
  }) {
    if (snapshot == null ||
        snapshot.validationStatus !=
            ConversationExecutionValidationStatus.failed ||
        snapshot.failures.isEmpty) {
      return null;
    }

    final limitedFailures = _limitFailures(snapshot.failures);
    final payload = {
      'schema': schemaName,
      'instruction':
          'These tests failed after the latest Dart file edits. Fix the failures before claiming the coding task is complete.',
      ..._snapshotEvidencePayload(snapshot),
      'failing_tests': limitedFailures
          .map(
            (failure) => failure.toJson(
              projectRoot: snapshot.projectRoot,
              maxStackChars: maxStackChars,
            ),
          )
          .toList(growable: false),
      if (limitedFailures.length < snapshot.failures.length)
        'truncated_failure_count':
            snapshot.failures.length - limitedFailures.length,
    };

    return ToolResultInfo(
      id: '${toolName}_${(now ?? DateTime.now()).microsecondsSinceEpoch}',
      name: toolName,
      arguments: {
        'project_root': snapshot.projectRoot,
        'changed_paths': snapshot.changedPaths,
        'trigger': snapshot.trigger.name,
      },
      result: jsonEncode(payload),
    );
  }

  Map<String, dynamic> _snapshotEvidencePayload(
    CodingVerificationSnapshot snapshot,
  ) {
    final selectedAttempt = snapshot.selectedAttempt;
    return {
      'provider': snapshot.providerName,
      'project_root': snapshot.projectRoot,
      'changed_paths': snapshot.changedPaths,
      'trigger': snapshot.trigger.name,
      'validation_status': snapshot.validationStatus.name,
      'target_batches': snapshot.targetBatches
          .map((batch) => batch.toJson(projectRoot: snapshot.projectRoot))
          .toList(growable: false),
      'counts': {
        'passed': snapshot.passedCount,
        'failed': snapshot.failedCount,
        'skipped': snapshot.skippedCount,
      },
      'telemetry': snapshot.telemetry.toJson(),
      if (selectedAttempt != null)
        'verification': {
          'executable': selectedAttempt.command.executable,
          'arguments': selectedAttempt.command.arguments,
          'working_directory': selectedAttempt.command.workingDirectory,
          'exit_code': selectedAttempt.exitCode,
          'duration_ms': selectedAttempt.durationMs,
          'timed_out': selectedAttempt.timedOut,
        },
      if (snapshot.reason != null) 'reason': snapshot.reason,
    };
  }

  Future<CodingVerificationSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required CodingVerificationTrigger trigger,
  }) async {
    if (!CodingDiagnosticFeedbackService.isDesktopPlatform) {
      return null;
    }

    final root = Directory(projectRoot).absolute.path;
    final changedDartFiles = DartProjectTooling.changedDartFiles(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    if (changedDartFiles.isEmpty) {
      return null;
    }

    final stopwatch = Stopwatch()..start();
    final attempts = <CodingVerificationCommandAttempt>[];
    final targetBatches = _resolveTargetBatches(root, changedDartFiles);
    if (targetBatches.isEmpty) {
      stopwatch.stop();
      return _snapshot(
        projectRoot: root,
        changedDartFiles: changedDartFiles,
        trigger: trigger,
        validationStatus: ConversationExecutionValidationStatus.unknown,
        targetBatches: const [],
        failures: const [],
        attempts: const [],
        durationMs: stopwatch.elapsedMilliseconds,
        reason: 'no_test_target',
      );
    }

    var passedCount = 0;
    var failedCount = 0;
    var skippedCount = 0;
    CodingVerificationCommandAttempt? lastAttempt;

    for (final batch in targetBatches) {
      var batchPassed = false;
      for (final command in _buildTestCommands(root, batch)) {
        final attemptStopwatch = Stopwatch()..start();
        final output = await _commandRunner(command, timeout);
        attemptStopwatch.stop();
        final parsed = _parseTestOutput(
          '${output.stdout}\n${output.stderr}',
          packageRoot: command.workingDirectory,
        );
        final status = _statusForOutput(output, parsed);
        final attempt = CodingVerificationCommandAttempt(
          command: command,
          exitCode: output.exitCode,
          durationMs: attemptStopwatch.elapsedMilliseconds,
          timedOut: output.timedOut,
          startError: output.startError,
          validationStatus: status,
          passedCount: parsed.passedCount,
          failedCount: parsed.failedCount,
          skippedCount: parsed.skippedCount,
        );
        attempts.add(attempt);
        lastAttempt = attempt;

        if (status == ConversationExecutionValidationStatus.failed) {
          stopwatch.stop();
          return _snapshot(
            projectRoot: root,
            changedDartFiles: changedDartFiles,
            trigger: trigger,
            validationStatus: status,
            targetBatches: targetBatches,
            failures: parsed.failures,
            attempts: attempts,
            durationMs: stopwatch.elapsedMilliseconds,
            selectedAttempt: attempt,
            passedCount: passedCount + parsed.passedCount,
            failedCount: failedCount + parsed.failedCount,
            skippedCount: skippedCount + parsed.skippedCount,
          );
        }

        if (status == ConversationExecutionValidationStatus.passed) {
          passedCount += parsed.passedCount;
          skippedCount += parsed.skippedCount;
          batchPassed = true;
          break;
        }
      }

      if (!batchPassed) {
        stopwatch.stop();
        return _snapshot(
          projectRoot: root,
          changedDartFiles: changedDartFiles,
          trigger: trigger,
          validationStatus: ConversationExecutionValidationStatus.unknown,
          targetBatches: targetBatches,
          failures: const [],
          attempts: attempts,
          durationMs: stopwatch.elapsedMilliseconds,
          selectedAttempt: lastAttempt,
          passedCount: passedCount,
          failedCount: failedCount,
          skippedCount: skippedCount,
          reason: 'verification_unavailable',
        );
      }
    }

    stopwatch.stop();
    return _snapshot(
      projectRoot: root,
      changedDartFiles: changedDartFiles,
      trigger: trigger,
      validationStatus: ConversationExecutionValidationStatus.passed,
      targetBatches: targetBatches,
      failures: const [],
      attempts: attempts,
      durationMs: stopwatch.elapsedMilliseconds,
      selectedAttempt: lastAttempt,
      passedCount: passedCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
    );
  }

  CodingVerificationSnapshot _snapshot({
    required String projectRoot,
    required List<DartChangedFile> changedDartFiles,
    required CodingVerificationTrigger trigger,
    required ConversationExecutionValidationStatus validationStatus,
    required List<CodingVerificationTargetBatch> targetBatches,
    required List<CodingVerificationFailure> failures,
    required List<CodingVerificationCommandAttempt> attempts,
    required int durationMs,
    int passedCount = 0,
    int failedCount = 0,
    int skippedCount = 0,
    String? reason,
    CodingVerificationCommandAttempt? selectedAttempt,
  }) {
    return CodingVerificationSnapshot(
      providerName: providerName,
      projectRoot: projectRoot,
      changedPaths: changedDartFiles
          .map((file) => file.relativePath)
          .toList(growable: false),
      trigger: trigger,
      validationStatus: validationStatus,
      targetBatches: List<CodingVerificationTargetBatch>.unmodifiable(
        targetBatches,
      ),
      failures: List<CodingVerificationFailure>.unmodifiable(failures),
      telemetry: CodingVerificationTelemetry(
        durationMs: durationMs,
        attempts: List<CodingVerificationCommandAttempt>.unmodifiable(attempts),
      ),
      selectedAttempt: selectedAttempt,
      passedCount: passedCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      reason: reason,
    );
  }

  List<CodingVerificationFailure> _limitFailures(
    List<CodingVerificationFailure> failures,
  ) {
    final limited = <CodingVerificationFailure>[];
    final seen = <String>{};
    for (final failure in failures) {
      if (limited.length >= maxFailures) {
        break;
      }
      if (!seen.add(failure.dedupeKey)) {
        continue;
      }
      limited.add(failure);
    }
    return limited;
  }

  List<CodingVerificationTargetBatch> _resolveTargetBatches(
    String projectRoot,
    List<DartChangedFile> changedDartFiles,
  ) {
    final directTargetsByPackage = <String, Set<String>>{};
    final packageNeedsFullTestDir = <String>{};

    for (final file in changedDartFiles) {
      final packageRoot = DartProjectTooling.nearestPackageRoot(
        file.absolutePath,
        projectRoot,
      );
      final packageRelativePath = DartProjectPath.relativePath(
        file.absolutePath,
        packageRoot,
      );
      final directTarget = _directTestTarget(packageRoot, packageRelativePath);
      if (directTarget != null) {
        directTargetsByPackage
            .putIfAbsent(packageRoot, () => <String>{})
            .add(directTarget);
        continue;
      }
      if (_packageHasTests(packageRoot)) {
        packageNeedsFullTestDir.add(packageRoot);
      }
    }

    final packageRoots = {
      ...directTargetsByPackage.keys,
      ...packageNeedsFullTestDir,
    }.toList()..sort();

    return packageRoots
        .map((packageRoot) {
          final targets = packageNeedsFullTestDir.contains(packageRoot)
              ? <String>['test']
              : (directTargetsByPackage[packageRoot]!.toList()..sort());
          return CodingVerificationTargetBatch(
            packageRoot: packageRoot,
            targets: targets,
          );
        })
        .toList(growable: false);
  }

  String? _directTestTarget(String packageRoot, String packageRelativePath) {
    final normalized = packageRelativePath.replaceAll(r'\', '/');
    if (normalized.startsWith('test/') && normalized.endsWith('_test.dart')) {
      return File.fromUri(
            Directory(packageRoot).uri.resolve(normalized),
          ).existsSync()
          ? normalized
          : null;
    }
    if (!normalized.startsWith('lib/') || !normalized.endsWith('.dart')) {
      return null;
    }
    final withoutLibPrefix = normalized.substring('lib/'.length);
    final withoutExtension = withoutLibPrefix.substring(
      0,
      withoutLibPrefix.length - '.dart'.length,
    );
    final target = 'test/${withoutExtension}_test.dart';
    return File.fromUri(Directory(packageRoot).uri.resolve(target)).existsSync()
        ? target
        : null;
  }

  bool _packageHasTests(String packageRoot) {
    final testDirectory = Directory.fromUri(
      Directory(packageRoot).uri.resolve('test/'),
    );
    if (!testDirectory.existsSync()) {
      return false;
    }
    return testDirectory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .any((file) => file.path.endsWith('_test.dart'));
  }

  List<CodingVerificationCommand> _buildTestCommands(
    String projectRoot,
    CodingVerificationTargetBatch batch,
  ) {
    final flutterArgs = ['test', '--machine', ...batch.targets];
    final dartArgs = ['test', '--reporter=json', ...batch.targets];
    final fvmFlutterArgs = ['flutter', ...flutterArgs];
    final fvmDartArgs = ['dart', ...dartArgs];
    final hasFvmMetadata = DartProjectTooling.hasFvmMetadata(
      packageRoot: batch.packageRoot,
      projectRoot: projectRoot,
    );

    final commandSpecs = hasFvmMetadata
        ? [
            ('fvm', fvmFlutterArgs),
            ('flutter', flutterArgs),
            ('fvm', fvmDartArgs),
            ('dart', dartArgs),
          ]
        : [
            ('flutter', flutterArgs),
            ('dart', dartArgs),
            ('fvm', fvmFlutterArgs),
            ('fvm', fvmDartArgs),
          ];

    return commandSpecs
        .map(
          (spec) => CodingVerificationCommand(
            executable: spec.$1,
            arguments: spec.$2,
            workingDirectory: batch.packageRoot,
          ),
        )
        .toList(growable: false);
  }

  ConversationExecutionValidationStatus _statusForOutput(
    CodingVerificationCommandOutput output,
    _ParsedTestOutput parsed,
  ) {
    if (parsed.failedCount > 0 || parsed.failures.isNotEmpty) {
      return ConversationExecutionValidationStatus.failed;
    }
    if (output.ran && output.exitCode == 0) {
      return ConversationExecutionValidationStatus.passed;
    }
    return ConversationExecutionValidationStatus.unknown;
  }

  _ParsedTestOutput _parseTestOutput(
    String output, {
    required String packageRoot,
  }) {
    final suites = <int, String>{};
    final tests = <int, _TestMetadata>{};
    final errorsByTest = <int, List<_TestError>>{};
    final runnerFailures = <CodingVerificationFailure>[];
    var passedCount = 0;
    var failedCount = 0;
    var skippedCount = 0;

    for (final line in const LineSplitter().convert(output)) {
      final event = _decodeJsonLine(line);
      if (event == null) {
        continue;
      }
      final type = event['type'];
      if (type == 'suite') {
        final suite = event['suite'];
        if (suite is Map) {
          final id = _asInt(suite['id']);
          final path = suite['path'];
          if (id != null && path is String) {
            suites[id] = path;
          }
        }
        continue;
      }
      if (type == 'testStart') {
        final test = event['test'];
        if (test is Map) {
          final id = _asInt(test['id']);
          if (id == null) {
            continue;
          }
          tests[id] = _TestMetadata(
            name: test['name'] is String
                ? test['name'] as String
                : 'Unnamed test',
            suitePath: suites[_asInt(test['suiteID'])],
            url: test['url'] is String ? test['url'] as String : null,
            line: _asInt(test['line']),
            column: _asInt(test['column']),
          );
        }
        continue;
      }
      if (type == 'error') {
        final testId = _asInt(event['testID']);
        final error = _TestError(
          message: event['error'] is String
              ? event['error'] as String
              : 'Test runner error',
          stackTrace: event['stackTrace'] is String
              ? event['stackTrace'] as String
              : null,
        );
        if (testId == null) {
          runnerFailures.add(
            CodingVerificationFailure(
              testName: 'Test runner',
              message: error.message,
              stackTrace: error.stackTrace,
            ),
          );
        } else {
          errorsByTest.putIfAbsent(testId, () => <_TestError>[]).add(error);
        }
        continue;
      }
      if (type == 'testDone') {
        final testId = _asInt(event['testID']);
        if (testId == null) {
          continue;
        }
        final hidden = event['hidden'] == true;
        final skipped = event['skipped'] == true;
        final result = event['result'];
        final errors = errorsByTest[testId] ?? const <_TestError>[];
        if (hidden && errors.isEmpty) {
          continue;
        }
        if (skipped) {
          skippedCount += 1;
          continue;
        }
        if (result == 'success' && errors.isEmpty) {
          passedCount += 1;
          continue;
        }
        if (result == 'failure' || errors.isNotEmpty) {
          failedCount += 1;
          runnerFailures.addAll(
            _failuresForTest(tests[testId], errors, packageRoot: packageRoot),
          );
        }
      }
    }

    return _ParsedTestOutput(
      passedCount: passedCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      failures: _dedupeFailures(runnerFailures),
    );
  }

  Map<String, dynamic>? _decodeJsonLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<CodingVerificationFailure> _failuresForTest(
    _TestMetadata? test,
    List<_TestError> errors, {
    required String packageRoot,
  }) {
    final absolutePath = test?.absolutePath(packageRoot);
    if (errors.isEmpty) {
      return [
        CodingVerificationFailure(
          testName: test?.name ?? 'Unnamed test',
          absolutePath: absolutePath,
          line: test?.line,
          column: test?.column,
          message: 'Test failed without a structured error message.',
        ),
      ];
    }
    return errors
        .map(
          (error) => CodingVerificationFailure(
            testName: test?.name ?? 'Unnamed test',
            absolutePath: absolutePath,
            line: test?.line,
            column: test?.column,
            message: error.message,
            stackTrace: error.stackTrace,
          ),
        )
        .toList(growable: false);
  }

  List<CodingVerificationFailure> _dedupeFailures(
    List<CodingVerificationFailure> failures,
  ) {
    final seen = <String>{};
    final deduped = <CodingVerificationFailure>[];
    for (final failure in failures) {
      if (seen.add(failure.dedupeKey)) {
        deduped.add(failure);
      }
    }
    return deduped;
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static Future<CodingVerificationCommandOutput> _runTestCommand(
    CodingVerificationCommand command,
    Duration timeout,
  ) async {
    Process? process;
    try {
      process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory: command.workingDirectory,
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      return CodingVerificationCommandOutput(
        exitCode: exitCode,
        stdout: await stdout,
        stderr: await stderr,
      );
    } on TimeoutException {
      process?.kill();
      return const CodingVerificationCommandOutput(
        exitCode: -1,
        timedOut: true,
      );
    } on ProcessException catch (error) {
      return CodingVerificationCommandOutput(
        exitCode: -1,
        startError: error.message,
      );
    } catch (error) {
      return CodingVerificationCommandOutput(
        exitCode: -1,
        startError: error.toString(),
      );
    }
  }
}

class _ParsedTestOutput {
  const _ParsedTestOutput({
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.failures,
  });

  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final List<CodingVerificationFailure> failures;
}

class _TestMetadata {
  const _TestMetadata({
    required this.name,
    required this.suitePath,
    required this.url,
    required this.line,
    required this.column,
  });

  final String name;
  final String? suitePath;
  final String? url;
  final int? line;
  final int? column;

  String? absolutePath(String packageRoot) {
    final parsedUrl = url == null ? null : Uri.tryParse(url!);
    if (parsedUrl != null && parsedUrl.scheme == 'file') {
      return File.fromUri(parsedUrl).absolute.path;
    }
    if (suitePath == null || suitePath!.trim().isEmpty) {
      return null;
    }
    return DartProjectPath.resolvePath(suitePath, projectRoot: packageRoot);
  }
}

class _TestError {
  const _TestError({required this.message, this.stackTrace});

  final String message;
  final String? stackTrace;
}
