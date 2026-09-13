import 'dart:io';

/// Makes the scenario workspace a real git repository on `main`.
///
/// Needed only by the worktree scenarios: a worktree child is a branch and a
/// second checkout, so it cannot exist in a plain temp directory. Every other
/// scenario leaves the workspace as it is, because a repository the model can see
/// changes what it does -- it starts reading git state and reporting diffs.
///
/// Commits the seeded files rather than leaving them untracked, so the branch the
/// child is cut from is the state the plan was written against. `-c` for identity
/// rather than `git config`, so a developer's global config is neither read for
/// required values nor written to.
Future<void> initializePlanModeGitRepository(Directory scenarioDir) async {
  Future<void> run(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: scenarioDir.path,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'git ${arguments.join(' ')} failed in ${scenarioDir.path}: '
        '${result.stderr}',
      );
    }
  }

  await run(['init', '--initial-branch=main']);
  await run(['add', '--all']);
  await run([
    '-c',
    'user.name=Caverno Canary',
    '-c',
    'user.email=canary@example.invalid',
    'commit',
    '--allow-empty',
    '--message',
    'chore: seed the scenario workspace',
  ]);
}
