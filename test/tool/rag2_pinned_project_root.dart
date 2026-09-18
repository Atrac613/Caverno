import 'dart:io';

/// The commit that froze the explicit-source-roots declarations, their
/// evaluation fixtures, and the tests that replay them.
///
/// Everything the frozen evaluations depend on landed in this one commit and
/// nothing has touched it since, so it is the checkout those fixtures' expected
/// counts were measured against.
const String rag2ExplicitSourceRootsPinnedCommit =
    '491aa6700f9e1acf7af759c6b652b08689e39726';

/// A checkout of [rag2ExplicitSourceRootsPinnedCommit] for a frozen evaluation
/// to acquire its corpus from.
///
/// The explicit-source-roots evaluations were replaying against the live
/// working tree, which made a frozen contract depend on a growing repository:
/// the declared chat roots reached exactly the frozen 512-file cap on
/// 2026-09-14, so the next file added under `lib/features/chat/domain/services`
/// (329 files and the repository's most active directory), `domain/entities`,
/// or `presentation/providers` failed a blocked track's evaluation with
/// `file_count_exceeded` plus two RAG-shaped blockers that hid the cause.
/// A declaration frozen on 2026-08-26 cannot be validated against files written
/// after it, so the corpus is pinned to the commit that froze it.
///
/// A real worktree rather than an export: acquisition attests every admitted
/// source with `git status`, `git ls-files`, and `git rev-parse HEAD:<path>`,
/// so the pinned corpus has to answer git about itself.
final class Rag2PinnedProjectRoot {
  Rag2PinnedProjectRoot._(this.path);

  /// Absolute path to the pinned checkout, for use as a `projectRoot`.
  final String path;

  /// Checks the pinned commit out into its own detached worktree.
  ///
  /// Fails rather than falling back to the live tree: a frozen evaluation that
  /// silently measures the current checkout is the defect this replaces.
  static Future<Rag2PinnedProjectRoot> checkOut() async {
    final repoRoot = Directory.current.path;
    final target = Directory.systemTemp.createTempSync('rag2_pinned_root_');
    // `git worktree add` requires a path it can create or an empty directory.
    final worktreePath = '${target.path}/tree';

    // Clear registry entries left by a run that died before its teardown.
    await _git(repoRoot, const ['worktree', 'prune']);

    final added = await _git(repoRoot, [
      'worktree',
      'add',
      '--detach',
      worktreePath,
      rag2ExplicitSourceRootsPinnedCommit,
    ]);
    if (added.exitCode != 0) {
      target.deleteSync(recursive: true);
      throw StateError(
        'Could not check out the pinned RAG2 corpus at '
        '$rag2ExplicitSourceRootsPinnedCommit: ${added.stderr}',
      );
    }
    return Rag2PinnedProjectRoot._(worktreePath);
  }

  /// Removes the worktree and its registry entry.
  Future<void> dispose() async {
    final repoRoot = Directory.current.path;
    await _git(repoRoot, ['worktree', 'remove', '--force', path]);
    await _git(repoRoot, const ['worktree', 'prune']);
    final parent = Directory(path).parent;
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  }

  static Future<ProcessResult> _git(String repoRoot, List<String> arguments) =>
      Process.run('git', arguments, workingDirectory: repoRoot);
}
