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
    this.onDecision,
  });
  final Future<bool> Function(String, ProjectTaskCommitScope) prepare;
  final Future<bool> Function(String, ProjectTaskCommitScope) commit;
  final Future<ProjectTaskCommitSnapshot?> Function(ProjectTaskCommitScope)
  inspect;
  final ProjectTaskCommitTurnEvidence? Function() readEvidence;
  final bool Function() canContinue;
  final bool Function() canRecover;

  final void Function(Map<String, Object?> decision)? onDecision;

  Future<String?> run(
    String objective,
    ProjectTaskCommitScope scope,
    ProjectTaskCommitSnapshot baseline,
  ) async {
    final problem = await _run(objective, scope, baseline);
    onDecision?.call({
      'phase': 'commit_sequence',
      'decision': problem == null ? 'head_advanced' : 'stopped',
      'reason': ?problem,
    });
    return problem;
  }

  void _observed(
    String phase,
    int attempt,
    ProjectTaskCommitSnapshot before,
    ProjectTaskCommitSnapshot? after,
    ProjectTaskCommitTurnEvidence? evidence,
    String? problem,
  ) {
    onDecision?.call({
      'phase': phase,
      'attempt': attempt + 1,
      'decision': problem == null ? 'accepted' : 'rejected',
      'reason': ?problem,
      'nativeStateAvailable': after != null,
      if (after != null) ...{
        'headChanged': before.head != after.head,
        'indexChanged': before.indexFingerprint != after.indexFingerprint,
        'stagedPathCount': after.stagedPaths.length,
        'unstagedPathCount': after.unstagedPaths.length,
        'roadmapComplete': after.roadmapAlreadyDone,
        'roadmapIdentityMatched':
            before.roadmapEntryIdentity != null &&
            before.roadmapEntryIdentity == after.roadmapEntryIdentity,
      },
      'evidenceAvailable': evidence != null,
      if (evidence != null) ...{
        'completedNormally': evidence.completedNormally,
        'mutationAttempted': evidence.mutationAttempted,
        'toolFailed': evidence.failed,
      },
    });
  }

  Future<String?> _run(
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
      onDecision?.call({
        'phase': 'preparation',
        'decision': 'started',
        'attempt': attempt + 1,
      });
      if (!await prepare(prompt, scope)) {
        return 'the commit preparation turn did not complete';
      }
      final evidence = readEvidence();
      if (evidence?.completedNormally == false || evidence?.failed == true) {
        return 'commit preparation encountered an abnormal exit or tool failure';
      }
      if (!canContinue()) return 'the task is no longer continuable';
      prepared = await inspect(scope);
      final problem = prepared == null
          ? 'prepared commit state could not be read'
          : scope.preparationProblem(baseline, prepared);
      _observed('preparation', attempt, baseline, prepared, evidence, problem);
      if (prepared == null) return problem;
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
      onDecision?.call({
        'phase': 'commit',
        'decision': 'started',
        'attempt': attempt + 1,
      });
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
      _observed(
        'commit',
        attempt,
        prepared,
        after,
        evidence,
        after == null
            ? 'git state could not be read after the commit turn'
            : after.head != baseline.head
            ? null
            : authorized.commitProblem(after) ??
                  'the commit turn recorded no new commit',
      );
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
