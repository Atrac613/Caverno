import 'dart_project_tooling.dart';

/// A verification target the turn that asked for it also wrote.
class MutatedVerificationTarget {
  const MutatedVerificationTarget({
    required this.packageRoot,
    required this.target,
    required this.absolutePath,
  });

  final String packageRoot;

  /// Package-relative target as the test command would receive it.
  final String target;

  final String absolutePath;
}

/// Decides when a verification run would execute code the model just wrote.
///
/// `dart test <path>` runs that file's `main()` whether or not it declares a
/// single test -- verified 2026-08-26 on a file whose `main()` wrote a
/// sentinel: it was written, and the runner still reported "No tests were
/// found". So a `test/**_test.dart` the current turn mutated is arbitrary code
/// with the app's own authority, reached without the fresh approval SEC4.4g
/// requires of any command the model asks to run itself.
///
/// This only names those targets. Whether to ask a person, and what to do when
/// nobody can be asked, belongs to the caller: an interactive turn has someone
/// to ask, an unattended one does not and withholds them instead.
abstract final class VerificationTargetAuthority {
  /// Targets in [batches] whose file is among [changedDartFiles].
  ///
  /// A whole-directory target (`test`) counts when any changed file lives
  /// under that package's `test/`, because running the directory runs it.
  static List<MutatedVerificationTarget> mutatedTargets({
    required List<CodingVerificationTargetBatchView> batches,
    required List<DartChangedFile> changedDartFiles,
  }) {
    final mutated = <MutatedVerificationTarget>[];
    for (final batch in batches) {
      for (final target in batch.targets) {
        final targetRoot = _join(batch.packageRoot, target);
        for (final changed in changedDartFiles) {
          final changedPath = _normalize(changed.absolutePath);
          final isTargetItself = changedPath == _normalize(targetRoot);
          final isInsideTargetDirectory = changedPath.startsWith(
            '${_normalize(targetRoot)}/',
          );
          if (!isTargetItself && !isInsideTargetDirectory) {
            continue;
          }
          mutated.add(
            MutatedVerificationTarget(
              packageRoot: batch.packageRoot,
              target: target,
              absolutePath: changed.absolutePath,
            ),
          );
          break;
        }
      }
    }
    return List<MutatedVerificationTarget>.unmodifiable(mutated);
  }

  /// The sentence a person is asked to authorize.
  ///
  /// Names the files rather than the command: what the approval is really
  /// about is that this run executes code that was just written, not which of
  /// `flutter`, `dart`, or `fvm` ends up carrying it.
  static String approvalMessageFor(List<MutatedVerificationTarget> targets) {
    final paths = {for (final target in targets) target.target}.toList()
      ..sort();
    return 'Verification would run ${paths.join(', ')}, which this turn just '
        'wrote. A test file runs as ordinary code, so this executes what was '
        'written, not only what it asserts.';
  }

  static String _join(String root, String relative) =>
      '${_normalize(root)}/${relative.replaceAll(r'\', '/')}';

  static String _normalize(String path) {
    var normalized = path.replaceAll(r'\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

/// The part of a target batch this policy reads.
///
/// Declared here so the policy does not depend on the verification service
/// that owns the batch type, which depends on this policy in turn.
abstract interface class CodingVerificationTargetBatchView {
  String get packageRoot;
  List<String> get targets;
}
