import 'dart_project_tooling.dart';

/// How a `run_tests` invocation is spelled: which runner, which path, and how
/// both are quoted for a shell.
///
/// These were private methods on ChatNotifier's local-file handler part, which
/// made them part of the notifier library's ratchet aggregate even though not
/// one of them reads notifier state. They are pure functions of their
/// arguments, so they belong outside it — and outside it they can be tested
/// without standing up a notifier.
abstract final class RunTestsCommandBuilder {
  static String? normalizeRunner(Object? rawRunner) {
    final runner = rawRunner?.toString().trim().toLowerCase();
    if (runner == null || runner.isEmpty || runner == 'auto') {
      return 'auto';
    }
    if (runner == 'flutter' || runner == 'dart') {
      return runner;
    }
    return null;
  }

  static String buildCommand({
    required String runner,
    required String projectRoot,
    required String workingDirectory,
    String? testPath,
  }) {
    final effectiveRunner = runner == 'auto'
        ? inferRunner(
            projectRoot: projectRoot,
            workingDirectory: workingDirectory,
          )
        : runner;
    final hasFvmMetadata = DartProjectTooling.hasFvmMetadata(
      packageRoot: workingDirectory,
      projectRoot: projectRoot,
    );
    final executable = switch (effectiveRunner) {
      'dart' => hasFvmMetadata ? 'fvm dart' : 'dart',
      _ => hasFvmMetadata ? 'fvm flutter' : 'flutter',
    };
    final parts = <String>[executable, 'test'];
    if (testPath != null && testPath.trim().isNotEmpty) {
      parts.add(shellQuoteArgument(testPath.trim()));
    }
    return parts.join(' ');
  }

  static String inferRunner({
    required String projectRoot,
    required String workingDirectory,
  }) {
    return DartProjectTooling.isFlutterPackage(workingDirectory) ||
            DartProjectTooling.isFlutterPackage(projectRoot)
        ? 'flutter'
        : 'dart';
  }

  static String normalizePathForWorkingDirectory(
    String rawTestPath, {
    required String projectRoot,
    required String workingDirectory,
  }) {
    final trimmed = rawTestPath.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
      return trimmed;
    }

    final workingDirectoryFromProject = DartProjectPath.relativePath(
      workingDirectory,
      projectRoot,
    ).replaceAll('\\', '/');
    if (workingDirectoryFromProject.isEmpty ||
        workingDirectoryFromProject == '.') {
      return trimmed;
    }

    final normalizedTestPath = trimmed.replaceAll('\\', '/');
    if (normalizedTestPath == workingDirectoryFromProject) {
      return '.';
    }
    final workingDirectoryPrefix = '$workingDirectoryFromProject/';
    if (normalizedTestPath.startsWith(workingDirectoryPrefix)) {
      final stripped = normalizedTestPath.substring(
        workingDirectoryPrefix.length,
      );
      return stripped.isEmpty ? '.' : stripped;
    }
    return trimmed;
  }

  static String shellQuoteArgument(String value) {
    if (value.isEmpty) return "''";
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  static String normalizeAbsolutePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      return Uri.file(trimmed).normalizePath().toFilePath();
    } catch (_) {
      return trimmed;
    }
  }
}
