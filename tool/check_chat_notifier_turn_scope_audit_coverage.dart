import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

const String _targetPath = 'tool/audit_chat_notifier_turn_scope.dart';
const String _testPath = 'test/tool/audit_chat_notifier_turn_scope_test.dart';
const double _minimumCoveragePercent = 90;

/// Measures the audit tool through unscoped VM coverage.
///
/// Flutter's package-scoped LCOV output omits scripts loaded from `tool/`.
/// Run this file from the repository root to collect those file-URI scripts,
/// isolate the audit target, and enforce its direct-test threshold.
Future<void> main() async {
  try {
    final result = await measureAuditCoverage(root: Directory.current);
    stdout.writeln(
      '$_targetPath: ${result.hitLines}/${result.executableLines} lines '
      '(${result.percent.toStringAsFixed(2)}%), minimum '
      '${_minimumCoveragePercent.toStringAsFixed(2)}%',
    );
    if (result.percent < _minimumCoveragePercent) {
      stderr.writeln(
        'Target coverage is below the required '
        '${_minimumCoveragePercent.toStringAsFixed(2)}%.',
      );
      exitCode = 1;
    }
  } on CoverageMeasurementException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

final class TargetCoverageResult {
  const TargetCoverageResult({
    required this.hitLines,
    required this.executableLines,
  });

  final int hitLines;
  final int executableLines;

  double get percent =>
      executableLines == 0 ? 0 : hitLines * 100 / executableLines;
}

final class CoverageMeasurementException implements Exception {
  const CoverageMeasurementException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<TargetCoverageResult> measureAuditCoverage({
  required Directory root,
}) async {
  _requireRepositoryFile(root, _targetPath);
  _requireRepositoryFile(root, _testPath);
  _requireRepositoryFile(root, '.dart_tool/package_config.json');

  final temporaryDirectory = Directory.systemTemp.createTempSync(
    'caverno-turn-scope-coverage-',
  );
  Process? testProcess;
  var testProcessExited = false;
  try {
    final rawCoveragePath = path.join(temporaryDirectory.path, 'coverage.json');
    final lcovPath = path.join(temporaryDirectory.path, 'lcov.info');
    final serviceUri = Completer<Uri>();
    testProcess = await Process.start(Platform.resolvedExecutable, [
      'run',
      '--pause-isolates-on-exit',
      '--disable-service-auth-codes',
      '--enable-vm-service=0',
      'test',
      _testPath,
    ], workingDirectory: root.path);
    final stdoutComplete = Completer<void>();
    final stderrComplete = Completer<void>();
    testProcess.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            stdout.writeln(line);
            if (!serviceUri.isCompleted) {
              final match = RegExp(
                r'https?://(?:127\.0\.0\.1|localhost):\d+/',
              ).firstMatch(line);
              if (match != null) {
                serviceUri.complete(Uri.parse(match.group(0)!));
              }
            }
          },
          onError: stdoutComplete.completeError,
          onDone: stdoutComplete.complete,
        );
    testProcess.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          stderr.writeln,
          onError: stderrComplete.completeError,
          onDone: stderrComplete.complete,
        );

    final uri = await serviceUri.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw const CoverageMeasurementException(
          'Timed out waiting for the test VM service.',
        );
      },
    );
    final collector = await Process.run(Platform.resolvedExecutable, [
      'run',
      'coverage:collect_coverage',
      '--wait-paused',
      '--resume-isolates',
      '--uri=$uri',
      '--out=$rawCoveragePath',
    ], workingDirectory: root.path);
    _requireSuccessfulProcess('coverage collection', collector);

    final testExitCode = await testProcess.exitCode;
    testProcessExited = true;
    await Future.wait([stdoutComplete.future, stderrComplete.future]);
    if (testExitCode != 0) {
      throw CoverageMeasurementException(
        'Focused audit tests failed with exit code $testExitCode.',
      );
    }

    final formatter = await Process.run(Platform.resolvedExecutable, [
      'run',
      'coverage:format_coverage',
      '--packages=.dart_tool/package_config.json',
      '--lcov',
      '--in=$rawCoveragePath',
      '--out=$lcovPath',
      '--report-on=$_targetPath',
    ], workingDirectory: root.path);
    _requireSuccessfulProcess('LCOV formatting', formatter);
    return parseTargetCoverage(
      File(lcovPath).readAsStringSync(),
      targetPath: path.join(root.path, _targetPath),
    );
  } on TimeoutException {
    throw const CoverageMeasurementException(
      'Timed out while measuring audit coverage.',
    );
  } finally {
    if (testProcess != null && !testProcessExited) {
      testProcess.kill();
    }
    temporaryDirectory.deleteSync(recursive: true);
  }
}

TargetCoverageResult parseTargetCoverage(
  String lcov, {
  required String targetPath,
}) {
  final normalizedTarget = path.normalize(targetPath);
  var inTarget = false;
  final lineHits = <int, int>{};
  for (final line in const LineSplitter().convert(lcov)) {
    if (line.startsWith('SF:')) {
      inTarget =
          path.normalize(line.substring('SF:'.length)) == normalizedTarget;
      continue;
    }
    if (line == 'end_of_record') {
      inTarget = false;
      continue;
    }
    if (!inTarget || !line.startsWith('DA:')) {
      continue;
    }
    final fields = line.substring('DA:'.length).split(',');
    if (fields.length < 2) {
      throw CoverageMeasurementException(
        'Malformed LCOV data for $_targetPath: $line',
      );
    }
    final lineNumber = int.tryParse(fields[0]);
    final hits = int.tryParse(fields[1]);
    if (lineNumber == null || hits == null) {
      throw CoverageMeasurementException(
        'Malformed LCOV data for $_targetPath: $line',
      );
    }
    lineHits[lineNumber] = hits;
  }
  if (lineHits.isEmpty) {
    throw const CoverageMeasurementException(
      'LCOV did not contain executable lines for $_targetPath.',
    );
  }
  return TargetCoverageResult(
    hitLines: lineHits.values.where((hits) => hits > 0).length,
    executableLines: lineHits.length,
  );
}

void _requireRepositoryFile(Directory root, String relativePath) {
  if (!File(path.join(root.path, relativePath)).existsSync()) {
    throw CoverageMeasurementException(
      'Run this command from the repository root; missing $relativePath.',
    );
  }
}

void _requireSuccessfulProcess(String operation, ProcessResult result) {
  if (result.exitCode == 0) {
    return;
  }
  final details = [
    result.stdout.toString().trim(),
    result.stderr.toString().trim(),
  ].where((value) => value.isNotEmpty).join('\n');
  throw CoverageMeasurementException(
    '$operation failed with exit code ${result.exitCode}.'
    '${details.isEmpty ? '' : '\n$details'}',
  );
}
