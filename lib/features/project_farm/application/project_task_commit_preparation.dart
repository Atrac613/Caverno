import '../domain/entities/project_task_commit_scope.dart';

/// Phase-specific handoff; earlier implementation and review instructions are
/// not replayed as instructions for preparing or committing the index.
final class ProjectTaskCommitPreparation {
  const ProjectTaskCommitPreparation();

  String _task(String objective, ProjectTaskCommitScope scope) =>
      '''Task: ${objective.trim().split('\n').first}
Source: ${scope.roadmapPath}${scope.sourceLine == null ? '' : ':${scope.sourceLine}'}
${scope.sourceQuote == null ? '' : 'Quoted task: "${scope.sourceQuote}"'}''';

  String _state(ProjectTaskCommitSnapshot? snapshot) => snapshot == null
      ? ''
      : '''Native HEAD: ${snapshot.head}
Native index fingerprint: ${snapshot.indexFingerprint}
Staged paths: ${snapshot.stagedPaths.isEmpty ? '(none)' : snapshot.stagedPaths.join(', ')}''';

  String _recovery(bool recovery) => recovery
      ? 'This is the one permitted recovery for this phase. The prior turn ended without a mutation attempt and native state is unchanged. Its completion prose is not execution evidence. Issue the required tools now; do not repeat the prior completion report.\n\n'
      : '';

  String prompt(
    String objective,
    ProjectTaskCommitScope scope, {
    ProjectTaskCommitSnapshot? snapshot,
    bool recovery = false,
  }) =>
      '''${_recovery(recovery)}The dedicated code review is complete. Your current phase is commit preparation.

${_task(objective, scope)}
${_state(snapshot)}

1. Read the cited roadmap entry and mark only this task done using its existing conventions. Preserve an already complete entry. Do not change the reviewed implementation.
2. Inspect status and the task diff. Wait for the roadmap edit to finish, then use git_execute_command add -- <named paths> to stage only the task files below.
3. Inspect the staged diff with git_execute_command diff --cached and report the observed preparation result.

Do not commit, push, amend, reset, rewrite history or use shell commands in this phase. The harness verifies the actual index and files before starting a separate commit phase. Respect approval gates and report any blocker.

Task files:
${scope.paths.map((file) => '- $file').join('\n')}''';

  String commitPrompt(
    String objective,
    ProjectTaskCommitScope scope, {
    bool recovery = false,
  }) =>
      '''${_recovery(recovery)}Your current phase is local commit execution. Native inspection accepted the roadmap and staged task files.

${_task(objective, scope)}
${_state(scope.prepared)}

The index is already prepared. Read the staged diff with git_execute_command diff --cached, then issue git_execute_command commit with a Conventional Commit subject of at most 72 characters and a concise body in a second -m paragraph. Report only the observed result. Read-only status inspection is also permitted.

Do not edit files, change staging, push, publish, amend, rewrite history or use shell commands. The harness rechecks HEAD, the complete index and task files immediately before execution. Respect approval gates. If a command is denied or state changed, report the blocker.

Prepared task files:
${scope.paths.map((file) => '- $file').join('\n')}''';
}
