import '../domain/entities/project_task_commit_scope.dart';

/// Prepares bookkeeping and index state before any commit turn can begin.
final class ProjectTaskCommitPreparation {
  const ProjectTaskCommitPreparation();

  String prompt(String objective, ProjectTaskCommitScope scope) =>
      '''The dedicated code review is complete. Prepare this task for a later commit:

$objective

Read the cited roadmap entry and mark only this task done using its existing conventions. If it is already complete, preserve its contents. Do not change the reviewed implementation. Inspect the current status and diff, then stage only the reviewed task files and the roadmap file listed below with git_execute_command add -- <named paths>. Wait for each edit to finish before staging. Inspect the staged diff. Do not commit, push, amend, reset or rewrite history during this preparation turn. The harness will inspect the actual index and files before it permits a separate commit turn. If preparation cannot finish, explain the blocker.

Task files:
${scope.paths.map((file) => '- $file').join('\n')}''';

  String commitPrompt(String objective, ProjectTaskCommitScope scope) =>
      '''Native inspection accepted the roadmap and staged task files. Create the local commit for this task:

$objective

The index is already prepared. Read the staged diff with git_execute_command diff --cached before committing. Read-only status inspection is also permitted. Do not edit files or change staging. Use git_execute_command commit with a Conventional Commit subject of at most 72 characters and a concise body in a second -m paragraph. Do not push, publish, amend or rewrite history. The harness checks HEAD, the complete index and task files again immediately before execution. Respect approval gates. If the commit is denied or state changed, report the blocker; do not bypass it with shell commands.

Prepared task files:
${scope.paths.map((file) => '- $file').join('\n')}''';
}
