import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/project_farm/application/background_task_runner.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/presentation/pages/projects_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = DateTime.utc(2026, 9, 26);
const _item = RoadmapItemSnapshot(
  id: 'M6',
  title: 'PDF report',
  quote: 'start M6',
  line: 3,
);
final _policy = ProjectFarmPolicy(
  projectId: 'p1',
  allowedVerificationCommands: const ['fvm flutter analyze'],
  updatedAt: _t,
);
ProjectProposal _proposal({
  String taskId = 'M6',
  String label = 'unattended',
}) => ProjectProposal(
  projectId: 'p1',
  inputHash: 'h',
  proposedAt: _t,
  taskId: taskId,
  automatability: label,
);
WorktreeAgentTask _task(
  WorktreeAgentTaskStatus status, {
  String projectId = 'p1',
  DateTime? at,
}) => WorktreeAgentTask(
  id: '${status.name}-$projectId-${at?.millisecond ?? 0}',
  status: status,
  branchName: 'agent/m6',
  worktreePath: '/wt/m6',
  codingProjectId: projectId,
  createdAt: at ?? _t,
  updatedAt: at ?? _t,
);

void main() {
  group('backgroundRunBlocker', () {
    BackgroundRunBlocker? blocker({
      ProjectFarmPolicy? policy,
      ProjectProposal? proposal,
      RoadmapItemSnapshot? item = _item,
      List<WorktreeAgentTask> tasks = const [],
    }) => backgroundRunBlocker(
      policy: policy,
      proposal: proposal,
      item: item,
      projectTasks: tasks,
    );

    test('allows a verified, unattended, proposed task under a policy', () {
      expect(blocker(policy: _policy, proposal: _proposal()), isNull);
    });

    test('each gate refuses on its own', () {
      expect(blocker(proposal: _proposal()), BackgroundRunBlocker.noPolicy);
      expect(
        blocker(
          policy: _policy.copyWith(allowedVerificationCommands: const []),
          proposal: _proposal(),
        ),
        BackgroundRunBlocker.noPolicy,
      );
      expect(
        blocker(policy: _policy, proposal: _proposal(), item: null),
        BackgroundRunBlocker.noTask,
      );
      expect(
        blocker(
          policy: _policy,
          proposal: _proposal(),
          item: _item.copyWith(verified: false),
        ),
        BackgroundRunBlocker.noTask,
      );
      expect(
        blocker(
          policy: _policy,
          proposal: _proposal(label: 'needsHuman'),
        ),
        BackgroundRunBlocker.needsHuman,
      );
      expect(
        blocker(
          policy: _policy,
          proposal: _proposal(taskId: 'OTHER'),
        ),
        BackgroundRunBlocker.needsHuman,
        reason: 'the label must be about this very item',
      );
      expect(
        blocker(
          policy: _policy,
          proposal: _proposal(),
          tasks: [_task(WorktreeAgentTaskStatus.running)],
        ),
        BackgroundRunBlocker.busy,
      );
      expect(
        blocker(
          policy: _policy,
          proposal: _proposal(),
          tasks: [_task(WorktreeAgentTaskStatus.completed)],
        ),
        isNull,
      );
    });
  });

  group('runProjectTaskInBackground', () {
    final project = CodingProject(
      id: 'p1',
      name: 'ledger',
      rootPath: '/repo',
      createdAt: _t,
      updatedAt: _t,
    );

    test(
      'enqueues with the declared command and starts the scheduler',
      () async {
        final calls = <String>[];
        await runProjectTaskInBackground(
          enqueue:
              ({
                required title,
                required prompt,
                required codingProjectId,
                required projectRootPath,
                required verificationCommand,
                required acceptanceCriteria,
              }) async {
                calls.add('enqueue $title $verificationCommand');
                expect(prompt, contains('docs/roadmap.md:3'));
                expect(prompt, contains('Do not merge'));
                return _task(WorktreeAgentTaskStatus.queued);
              },
          startReady: (root) => calls.add('start $root'),
          project: project,
          policy: _policy,
          item: _item,
          roadmapPath: 'docs/roadmap.md',
          verificationCommand: 'fvm   flutter analyze',
        );
        expect(calls, [
          'enqueue M6: PDF report fvm flutter analyze',
          'start /repo',
        ]);
      },
    );

    test('refuses a command the policy does not allow', () async {
      var enqueued = false;
      await expectLater(
        runProjectTaskInBackground(
          enqueue:
              ({
                required title,
                required prompt,
                required codingProjectId,
                required projectRootPath,
                required verificationCommand,
                required acceptanceCriteria,
              }) async {
                enqueued = true;
                return _task(WorktreeAgentTaskStatus.queued);
              },
          startReady: (_) {},
          project: project,
          policy: _policy,
          item: _item,
          roadmapPath: 'docs/roadmap.md',
          verificationCommand: 'rm -rf /',
        ),
        throwsStateError,
      );
      expect(enqueued, isFalse);
    });
  });

  test('latestTaskFor picks the newest task of the project', () {
    final older = _task(WorktreeAgentTaskStatus.completed, at: _t);
    final newer = _task(
      WorktreeAgentTaskStatus.running,
      at: _t.add(const Duration(minutes: 1)),
    );
    final other = _task(
      WorktreeAgentTaskStatus.running,
      projectId: 'p2',
      at: _t.add(const Duration(hours: 1)),
    );
    expect(latestTaskFor([older, newer, other], 'p1'), newer);
    expect(latestTaskFor([other], 'p1'), isNull);
  });

  testWidgets('the overview row offers Run in background only when allowed', (
    tester,
  ) async {
    Future<void> pump(BackgroundRunBlocker? blocker) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectOverviewTile(
            project: CodingProject(
              id: 'p1',
              name: 'ledger',
              rootPath: '/repo',
              createdAt: _t,
              updatedAt: _t,
            ),
            snapshot: RoadmapSnapshot(
              projectId: 'p1',
              roadmapPath: 'docs/roadmap.md',
              contentSha256: 's',
              extractorVersion: 1,
              model: 'm',
              extractedAt: _t,
              status: RoadmapSnapshotStatus.verified,
              recommended: _item,
            ),
            refreshing: false,
            running: 0,
            needsApproval: 0,
            onOpenDashboard: () {},
            onStartWork: (_, _) {},
            backgroundBlocker: blocker,
            onRunInBackground: (_, _) {},
          ),
        ),
      ),
    );
    const key = ValueKey('projects-overview-p1-run-bg');

    await pump(null);
    expect(find.byKey(key), findsOneWidget);
    await pump(BackgroundRunBlocker.needsHuman);
    expect(find.byKey(key), findsNothing);
  });

  testWidgets('the overview row cancels only a running background task', (
    tester,
  ) async {
    WorktreeAgentTask? cancelled;
    Future<void> pump(WorktreeAgentTask task) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectOverviewTile(
            project: CodingProject(
              id: 'p1',
              name: 'ledger',
              rootPath: '/repo',
              createdAt: _t,
              updatedAt: _t,
            ),
            snapshot: null,
            refreshing: false,
            running: 0,
            needsApproval: 0,
            onOpenDashboard: () {},
            onStartWork: (_, _) {},
            latestBackgroundTask: task,
            onCancelBackground: (task) => cancelled = task,
          ),
        ),
      ),
    );
    const key = ValueKey('projects-overview-p1-bg-cancel');

    final running = _task(WorktreeAgentTaskStatus.running);
    await pump(running);
    await tester.tap(find.byKey(key));
    expect(cancelled, running);

    await pump(_task(WorktreeAgentTaskStatus.completed));
    expect(find.byKey(key), findsNothing);
  });
}
