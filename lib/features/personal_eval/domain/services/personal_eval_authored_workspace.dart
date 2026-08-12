import 'dart:io';

import '../entities/personal_eval_case.dart';

/// Materializes an isolated working directory for one authored fixture case.
///
/// LL19 has not shipped worktree isolation, so a replay edits whatever
/// directory it is handed. An authored case must therefore never be given the
/// repository tree: this copies the committed fixture into a fresh temporary
/// directory and overlays the case's seed there, so the model's edits, the
/// verifier, and any damage stay inside a throwaway copy.
class PersonalEvalAuthoredWorkspace {
  const PersonalEvalAuthoredWorkspace._(
    this.directory,
    this.caseId,
    this._verificationHarnessSnapshot,
  );

  final Directory directory;
  final String caseId;
  final Map<String, List<int>> _verificationHarnessSnapshot;

  String get path => directory.path;

  /// Prepares a workspace for [evalCase].
  ///
  /// [repositoryRoot] resolves the case's repo-relative fixture path. A missing
  /// fixture or seed throws rather than running: a replay against an
  /// unseeded copy would score a task that was never broken.
  static PersonalEvalAuthoredWorkspace prepare({
    required PersonalEvalCase evalCase,
    required String repositoryRoot,
    String seedRoot = 'seeds',
  }) {
    if (!evalCase.isAuthored) {
      throw ArgumentError.value(
        evalCase.caseId,
        'evalCase',
        'Only authored cases run in a materialized fixture workspace; a '
            'recorded case replays against its own repository state.',
      );
    }
    final fixture = Directory(
      '$repositoryRoot/${evalCase.normalizedFixtureDirectory}',
    );
    if (!fixture.existsSync()) {
      throw StateError(
        'Fixture ${evalCase.normalizedFixtureDirectory} for '
        '${evalCase.caseId} does not exist under $repositoryRoot.',
      );
    }
    final seed = Directory('${fixture.path}/$seedRoot/${evalCase.caseId}');
    if (!seed.existsSync()) {
      throw StateError(
        'Seed for ${evalCase.caseId} does not exist; without it the fixture '
        'is already green and the task would score as solved.',
      );
    }

    final work = Directory.systemTemp.createTempSync(
      'caverno_eval_${evalCase.caseId}_',
    );
    try {
      // The seed tree itself is excluded: shipping every task's answer key into
      // the workspace would hand the model the other cases' defects.
      _copyTree(fixture, work, skipDirectoryNames: {seedRoot});
      _copyTree(seed, work);
      return PersonalEvalAuthoredWorkspace._(
        work,
        evalCase.caseId,
        _snapshotVerificationHarness(work),
      );
    } catch (_) {
      if (work.existsSync()) {
        work.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  /// Returns an explanation when candidate edits changed the scoring harness.
  ///
  /// The candidate may edit package sources, but it must not be able to earn a
  /// pass by replacing the verifier or changing its package configuration.
  String? verificationHarnessIntegrityError() {
    final current = _snapshotVerificationHarness(directory);
    final expectedPaths = _verificationHarnessSnapshot.keys.toSet();
    final currentPaths = current.keys.toSet();
    if (!expectedPaths.containsAll(currentPaths) ||
        !currentPaths.containsAll(expectedPaths)) {
      return 'Verification harness files were added or removed.';
    }
    for (final path in expectedPaths) {
      final expected = _verificationHarnessSnapshot[path]!;
      final actual = current[path]!;
      if (!_bytesEqual(expected, actual)) {
        return 'Verification harness file changed: $path';
      }
    }
    return null;
  }

  /// Removes the workspace. Safe to call twice.
  void dispose() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }

  static void _copyTree(
    Directory from,
    Directory to, {
    Set<String> skipDirectoryNames = const {},
  }) {
    for (final entity in from.listSync()) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (entity is Directory) {
        if (skipDirectoryNames.contains(name)) {
          continue;
        }
        final target = Directory('${to.path}/$name');
        if (!target.existsSync()) {
          target.createSync(recursive: true);
        }
        _copyTree(entity, target, skipDirectoryNames: skipDirectoryNames);
      } else if (entity is File) {
        entity.copySync('${to.path}/$name');
      }
    }
  }

  static Map<String, List<int>> _snapshotVerificationHarness(Directory root) {
    final snapshot = <String, List<int>>{};
    final pubspec = File('${root.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      snapshot['pubspec.yaml'] = pubspec.readAsBytesSync();
    }
    final verifierDirectory = Directory('${root.path}/bin');
    if (verifierDirectory.existsSync()) {
      for (final entity in verifierDirectory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final relative = entity.path.substring(root.path.length + 1);
        snapshot[relative] = entity.readAsBytesSync();
      }
    }
    return Map.unmodifiable(snapshot);
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
