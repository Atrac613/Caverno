import '../domain/entities/project_task_commit_scope.dart';
import 'project_task_commit_preparation.dart';
import 'project_task_commit_turn_evidence.dart';

/// One recovery per phase, only when no mutation was attempted and native
/// state stayed identical. A changed HEAD can never trigger another commit.
final class ProjectTaskCommitSequence {
  const ProjectTaskCommitSequence({
    required this.prepare,
    required this.commit,
    required this.inspect,
    required this.readEvidence,
    required this.canContinue,
    required this.canRecover,
  });
  final Future<bool> Function(String, ProjectTaskCommitScope) prepare;
  final Future<bool> Function(String, ProjectTaskCommitScope) commit;
  final Future<ProjectTaskCommitSnapshot?> Function(ProjectTaskCommitScope)
  inspect;
  final ProjectTaskCommitTurnEvidence? Function() readEvidence;
  final bool Function() canContinue;
  final bool Function() canRecover;

  Future<String?> run(
    String objective,
    ProjectTaskCommitScope scope,
    ProjectTaskCommitSnapshot baseline,
  ) async {
    const prompts = ProjectTaskCommitPreparation();
    ProjectTaskCommitSnapshot? prepared;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!canContinue()) return 'the task is no longer continuable';
      final prompt = prompts.prompt(
        objective,
        scope,
        snapshot: baseline,
        recovery: attempt == 1,
      );
      if (!await prepare(prompt, scope)) {
        return 'the commit preparation turn did not complete';
      }
      final evidence = readEvidence();
      if (evidence?.completedNormally == false || evidence?.failed == true) {
        return 'commit preparation encountered an abnormal exit or tool failure';
      }
      if (!canContinue()) return 'the task is no longer continuable';
      prepared = await inspect(scope);
      if (prepared == null) return 'prepared commit state could not be read';
      final problem = scope.preparationProblem(baseline, prepared);
      if (problem == null) break;
      if (attempt != 0 ||
          evidence?.mayRecover != true ||
          !scope.sameCapturedState(baseline, prepared) ||
          !canRecover()) {
        return problem;
      }
    }
    final authorized = scope.authorize(prepared!);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!canContinue()) return 'the task is no longer continuable';
      if (!await commit(
        prompts.commitPrompt(objective, authorized, recovery: attempt == 1),
        authorized,
      )) {
        return 'the commit turn did not complete';
      }
      final evidence = readEvidence();
      if (evidence?.completedNormally == false || evidence?.failed == true) {
        return 'the commit turn encountered an abnormal exit or tool failure';
      }
      if (!canContinue()) return 'the task is no longer continuable';
      final after = await inspect(authorized);
      if (after == null) {
        return 'git state could not be read after the commit turn';
      }
      if (after.head != baseline.head) return null;
      final changed = authorized.commitProblem(after);
      if (changed != null) return changed;
      if (attempt != 0 || evidence?.mayRecover != true || !canRecover()) {
        return 'the commit turn recorded no new commit';
      }
    }
    return 'the commit turn recorded no new commit';
  }
}
