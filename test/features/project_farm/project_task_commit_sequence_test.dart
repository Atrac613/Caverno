import 'package:caverno/features/project_farm/application/project_task_commit_preparation.dart';
import 'package:caverno/features/project_farm/application/project_task_commit_sequence.dart';
import 'package:caverno/features/project_farm/application/project_task_commit_turn_evidence.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_commit_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scope = ProjectTaskCommitScope(
    conversationId: 'task',
    projectRoot: '/repo',
    roadmapPath: '/repo/roadmap.md',
    reviewedPaths: ['/repo/task.py'],
    sourceLine: 4,
    sourceQuote: '- [ ] Handle "quoted" values',
  );
  const idle = ProjectTaskCommitTurnEvidence(
    completedNormally: true,
    mutationAttempted: false,
    failed: false,
  );
  const mutation = ProjectTaskCommitTurnEvidence(
    completedNormally: true,
    mutationAttempted: true,
    failed: false,
  );
  ProjectTaskCommitSnapshot snapshot({
    bool ready = false,
    String head = 'before',
    String? index,
    String task = 'reviewed',
    String? roadmap,
  }) => ProjectTaskCommitSnapshot(
    head: head,
    indexFingerprint: index ?? (ready ? 'staged' : 'baseline'),
    fileFingerprints: {
      '/repo/task.py': task,
      '/repo/roadmap.md': roadmap ?? (ready ? 'done' : 'pending'),
    },
    stagedPaths: ready ? scope.paths : {},
    unstagedPaths: ready ? {} : {'/repo/task.py'},
    roadmapAlreadyDone: ready,
  );
  late List<Map<String, Object?>> decisions;
  late List<String> prompts;
  late List<ProjectTaskCommitScope> permits;
  late ProjectTaskCommitTurnEvidence? evidence;
  late int preparations;
  late int commits;
  var continuable = true;
  var recoverable = true;
  setUp(() {
    decisions = [];
    prompts = [];
    permits = [];
    evidence = idle;
    preparations = commits = 0;
    continuable = recoverable = true;
  });
  Future<String?> run(
    List<ProjectTaskCommitSnapshot?> inspections, {
    ProjectTaskCommitTurnEvidence? preparationEvidence = idle,
    ProjectTaskCommitTurnEvidence? commitEvidence = idle,
    bool Function()? continuing,
  }) => ProjectTaskCommitSequence(
    onDecision: decisions.add,
    prepare: (prompt, scope) async {
      preparations++;
      prompts.add(prompt);
      evidence = preparationEvidence;
      return true;
    },
    commit: (prompt, scope) async {
      commits++;
      prompts.add(prompt);
      permits.add(scope);
      evidence = commitEvidence;
      return true;
    },
    inspect: (_) async => inspections.removeAt(0),
    readEvidence: () => evidence,
    canContinue: continuing ?? () => continuable,
    canRecover: () => recoverable,
  ).run('Handle quoted values\nSource: roadmap.md:4', scope, snapshot());

  test('recovers unchanged preparation once and then commits once', () async {
    expect(
      await run([
        snapshot(),
        snapshot(ready: true),
        snapshot(ready: true, head: 'after'),
      ]),
      isNull,
    );
    expect(preparations, 2);
    expect(commits, 1);
    expect(prompts[1], contains('one permitted recovery'));
    expect(prompts.last, isNot(contains('one permitted recovery')));
  });
  test('recovers an idle commit once using the same native permit', () async {
    expect(
      await run([
        snapshot(ready: true),
        snapshot(ready: true),
        snapshot(ready: true, head: 'after'),
      ]),
      isNull,
    );
    expect(preparations, 1);
    expect(commits, 2);
    expect(permits.first, same(permits.last));
    expect(prompts.last, contains('one permitted recovery'));
  });
  test('each phase has its own single recovery', () async {
    expect(
      await run([
        snapshot(),
        snapshot(ready: true),
        snapshot(ready: true),
        snapshot(ready: true, head: 'after'),
      ]),
      isNull,
    );
    expect(preparations, 2);
    expect(commits, 2);
  });
  test('does not repeat a commit after native HEAD advances', () async {
    expect(
      await run([
        snapshot(ready: true),
        snapshot(ready: true, head: 'after'),
      ], commitEvidence: mutation),
      isNull,
    );
    expect(commits, 1);
  });
  test('preparation and commit exhaustion stop after two turns', () async {
    expect(await run([snapshot(), snapshot()]), contains('no task changes'));
    expect(preparations, 2);
    expect(commits, 0);
    preparations = 0;
    expect(
      await run([
        snapshot(ready: true),
        snapshot(ready: true),
        snapshot(ready: true),
      ]),
      contains('no new commit'),
    );
    expect(preparations, 1);
    expect(commits, 2);
  });
  for (final observation in [
    null,
    mutation,
    const ProjectTaskCommitTurnEvidence(
      completedNormally: true,
      mutationAttempted: false,
      failed: true,
    ),
    const ProjectTaskCommitTurnEvidence(
      completedNormally: false,
      mutationAttempted: false,
      failed: false,
    ),
  ]) {
    test(
      'unsafe or unknown evidence stops without recovery: $observation',
      () async {
        expect(
          await run([snapshot()], preparationEvidence: observation),
          isNotNull,
        );
        expect(preparations, 1);
        expect(commits, 0);
        preparations = 0;
        expect(
          await run([
            snapshot(ready: true),
            snapshot(ready: true),
          ], commitEvidence: observation),
          isNotNull,
        );
        expect(preparations, 1);
        expect(commits, 1);
      },
    );
  }
  for (final changed in [
    snapshot(head: 'elsewhere'),
    snapshot(index: 'changed'),
    snapshot(task: 'changed'),
    snapshot(roadmap: 'changed'),
    null,
  ]) {
    test(
      'changed or unreadable native state stops preparation: $changed',
      () async {
        expect(await run([changed]), isNotNull);
        expect(preparations, 1);
        expect(commits, 0);
      },
    );
  }
  test('changed index or task files stop an idle commit', () async {
    for (final changed in [
      snapshot(ready: true, index: 'changed'),
      snapshot(ready: true, task: 'changed'),
      null,
    ]) {
      commits = 0;
      expect(await run([snapshot(ready: true), changed]), isNotNull);
      expect(commits, 1);
    }
  });
  test('native refusal logs its cause and never starts a commit', () async {
    final reason = await run([
      snapshot(ready: true, task: 'changed'),
    ], preparationEvidence: mutation);
    expect(reason, contains('reviewed task files changed'));
    expect(commits, 0);
    expect(decisions.where((entry) => entry['phase'] == 'commit'), isEmpty);
    expect(
      decisions,
      contains(
        allOf(
          containsPair('phase', 'preparation'),
          containsPair('decision', 'rejected'),
          containsPair('nativeStateAvailable', true),
          containsPair('reason', reason),
        ),
      ),
    );
    expect(decisions.last, containsPair('decision', 'stopped'));
  });

  test('budget or admission gate blocks recovery', () async {
    recoverable = false;
    expect(await run([snapshot()]), isNotNull);
    expect(preparations, 1);
    expect(commits, 0);
  });
  test('selection or pending input changes prevent the next turn', () async {
    var checks = 0;
    expect(await run([snapshot()], continuing: () => ++checks < 2), isNotNull);
    expect(preparations, 1);
    expect(commits, 0);
  });
  test(
    'handoff retains the quoted task and native state, not old instructions',
    () {
      const prompts = ProjectTaskCommitPreparation();
      const objective =
          'Handle values\nSource: roadmap.md:4\n\nOld review instructions.\nPROJECT_TASK_REVIEW_CLEAN';
      for (final prompt in [
        prompts.prompt(objective, scope, snapshot: snapshot()),
        prompts.commitPrompt(objective, scope.authorize(snapshot(ready: true))),
      ]) {
        expect(prompt, contains('Source: /repo/roadmap.md:4'));
        expect(prompt, contains('- [ ] Handle "quoted" values'));
        expect(prompt, contains('Native HEAD: before'));
        expect(prompt, isNot(contains('Old review instructions')));
        expect(prompt, isNot(contains('PROJECT_TASK_REVIEW_CLEAN')));
      }
    },
  );
}
