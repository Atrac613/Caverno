import 'dart:async';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/maintenance/domain/entities/idle_maintenance_config.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_environment.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/project_farm/application/farm_unattended_runner.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/farm_run_record.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 9, 27, 2);

class _Environment implements IdleMaintenanceEnvironment {
  Duration idle = const Duration(hours: 1);

  @override
  DateTime now() => _now;

  @override
  Duration idleFor() => idle;

  @override
  bool onAcPower() => true;
}

CodingProject _project(String id) => CodingProject(
  id: id,
  name: id,
  rootPath: '/work/$id',
  createdAt: _now,
  updatedAt: _now,
);

ProjectFarmPolicy _policy(
  String projectId, {
  bool enabled = true,
  int limit = 1,
  List<String> unattended = const ['fvm flutter analyze'],
}) => ProjectFarmPolicy(
  projectId: projectId,
  allowedVerificationCommands: const [
    'fvm flutter analyze',
    'tool/flutter_test_quiet.sh',
  ],
  unattendedCommands: unattended,
  autoRunEnabled: enabled,
  dailyRunLimit: limit,
  updatedAt: _now,
);

RoadmapSnapshot _snapshot(String projectId) => RoadmapSnapshot(
  projectId: projectId,
  roadmapPath: 'docs/roadmap.md',
  contentSha256: 'sha',
  extractorVersion: 1,
  model: 'm',
  extractedAt: _now,
  status: RoadmapSnapshotStatus.verified,
  recommended: const RoadmapItemSnapshot(
    id: 'M6',
    title: 'PDF report',
    quote: 'start M6',
    line: 3,
  ),
);

ProjectProposal _proposal(String projectId, {String label = 'unattended'}) =>
    ProjectProposal(
      projectId: projectId,
      inputHash: 'h',
      proposedAt: _now,
      taskId: 'M6',
      automatability: label,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('policy picks only a declared, allowed non-executing command', () {
    expect(_policy('p').unattendedCommand, 'fvm flutter analyze');
    expect(_policy('p').allowsUnattendedRuns, isTrue);
    expect(_policy('p', enabled: false).allowsUnattendedRuns, isFalse);
    expect(_policy('p', unattended: const []).allowsUnattendedRuns, isFalse);
    expect(
      _policy('p', unattended: const ['make test']).unattendedCommand,
      isNull,
      reason: 'a command outside the allowed list is never used',
    );
  });

  group('FarmUnattendedRunner', () {
    late RoadmapSnapshotRepository repository;
    late List<CodingProject> projects;
    late Map<String, String> labels;
    late List<WorktreeAgentTask> tasks;
    late List<String> enqueued;
    late List<String> modelCalls;
    late List<String> startedRoots;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = RoadmapSnapshotRepository(
        await SharedPreferences.getInstance(),
      );
      projects = [_project('a'), _project('b'), _project('off')];
      labels = {'a': 'unattended', 'b': 'needsHuman'};
      tasks = [];
      enqueued = [];
      modelCalls = [];
      startedRoots = [];
      await repository.savePolicy(_policy('a'));
      await repository.savePolicy(_policy('b'));
      await repository.savePolicy(_policy('off', enabled: false));
    });

    FarmUnattendedRunner runner({Future<void> Function()? duringProposal}) =>
        FarmUnattendedRunner(
          repository: repository,
          projects: () => projects,
          refreshSnapshot: (project) async {
            modelCalls.add('snapshot ${project.id}');
            return _snapshot(project.id);
          },
          refreshProposal: (project, snapshot) async {
            modelCalls.add('proposal ${project.id}');
            await duringProposal?.call();
            return _proposal(
              project.id,
              label: labels[project.id] ?? 'unattended',
            );
          },
          tasks: () => tasks,
          enqueue:
              ({
                required title,
                required prompt,
                required codingProjectId,
                required projectRootPath,
                required verificationCommand,
                required acceptanceCriteria,
              }) async {
                enqueued.add('$codingProjectId $verificationCommand');
                return WorktreeAgentTask(
                  id: 't-$codingProjectId',
                  branchName: 'agent/$codingProjectId',
                  worktreePath: '/wt/$codingProjectId',
                  codingProjectId: codingProjectId,
                  createdAt: _now,
                  updatedAt: _now,
                );
              },
          startReady: startedRoots.add,
          now: () => _now,
        );

    test(
      'advances only opted-in projects whose proposal is unattended',
      () async {
        final summary = await runner().run(isCancelled: () => false);

        expect(enqueued, ['a fvm flutter analyze']);
        expect(summary.started, 1);
        expect(summary.skipped, 1);
        expect(
          modelCalls.where((call) => call.endsWith(' off')),
          isEmpty,
          reason: 'a project that did not opt in costs no model call',
        );
        final ledger = repository.farmRuns();
        expect(ledger.map((r) => '${r.projectId} ${r.outcome} ${r.detail}'), [
          'a enqueued ',
          'b skipped needsHuman',
        ]);
        expect(ledger.first.branch, 'agent/a');
        expect(ledger.every((r) => r.trigger == 'unattended'), isTrue);
      },
    );

    test('stops at the daily limit', () async {
      await runner().run(isCancelled: () => false);
      enqueued.clear();
      tasks = [];

      await runner().run(isCancelled: () => false);

      expect(enqueued, isEmpty);
      expect(
        repository.farmRuns().last.detail,
        anyOf('daily_limit', 'needsHuman'),
      );
      expect(
        repository.farmRuns().where(
          (r) => r.projectId == 'a' && r.detail == 'daily_limit',
        ),
        hasLength(1),
      );
    });

    for (final removeCommands in [false, true]) {
      test(
        'rechecks unattended permission after proposal: $removeCommands',
        () async {
          projects = [_project('a')];
          final summary = await runner(
            duringProposal: () async {
              await repository.savePolicy(
                _policy(
                  'a',
                  enabled: removeCommands,
                  unattended: removeCommands ? [] : ['fvm flutter analyze'],
                ),
              );
            },
          ).run(isCancelled: () => false);
          expect(summary.started, 0);
          expect(summary.skipped, 1);
          expect(enqueued, isEmpty);
          expect(startedRoots, isEmpty);
          expect(repository.farmRuns().single.detail, 'unattended_disabled');
        },
      );
    }

    test('uses the current authorized command after proposal', () async {
      projects = [_project('a')];
      await runner(
        duringProposal: () async {
          await repository.savePolicy(
            _policy('a', unattended: ['tool/flutter_test_quiet.sh']),
          );
        },
      ).run(isCancelled: () => false);
      expect(enqueued, ['a tool/flutter_test_quiet.sh']);
      expect(
        repository.farmRuns().single.command,
        'tool/flutter_test_quiet.sh',
      );
    });

    test('rechecks a daily limit spent while proposal is pending', () async {
      projects = [_project('a')];
      await runner(
        duringProposal: () async {
          await repository.appendFarmRun(
            FarmRunRecord(
              id: 'other-run',
              projectId: 'a',
              trigger: 'unattended',
              at: _now,
              outcome: 'enqueued',
            ),
          );
        },
      ).run(isCancelled: () => false);
      expect(enqueued, isEmpty);
      expect(startedRoots, isEmpty);
      expect(repository.farmRuns().last.detail, 'daily_limit');
    });

    test(
      'scheduler dispatches Farm once per idle window and records gates',
      () async {
        final farm = runner();
        final scheduler = IdleMaintenanceScheduler(
          environment: _Environment(),
          configProvider: () => const IdleMaintenanceConfig(
            enabled: true,
            windowStartMinutes: 120,
            windowEndMinutes: 360,
            minIdle: Duration(minutes: 10),
            requireAcPower: true,
          ),
          run: (handle) async {
            await farm.run(isCancelled: () => handle.isCancelled);
          },
        );
        addTearDown(scheduler.stop);
        await scheduler.tick();
        await scheduler.drain();
        await scheduler.tick();
        await scheduler.drain();
        expect(enqueued, ['a fvm flutter analyze']);
        expect(startedRoots, ['/work/a']);
        expect(repository.farmRuns().map((record) => record.outcome), [
          'enqueued',
          'skipped',
        ]);
        expect(repository.farmRuns().last.detail, 'needsHuman');
        expect(modelCalls, [
          'snapshot a',
          'proposal a',
          'snapshot b',
          'proposal b',
        ]);
      },
    );

    test(
      'scheduler cancels a pending Farm proposal when the user returns',
      () async {
        final proposalStarted = Completer<void>();
        final releaseProposal = Completer<void>();
        final farm = runner(
          duringProposal: () async {
            proposalStarted.complete();
            await releaseProposal.future;
          },
        );
        final environment = _Environment();
        final scheduler = IdleMaintenanceScheduler(
          environment: environment,
          configProvider: () => const IdleMaintenanceConfig(
            enabled: true,
            windowStartMinutes: 120,
            windowEndMinutes: 360,
            minIdle: Duration(minutes: 10),
            requireAcPower: true,
          ),
          run: (handle) async {
            await farm.run(isCancelled: () => handle.isCancelled);
          },
        );
        addTearDown(() async {
          scheduler.stop();
          if (!releaseProposal.isCompleted) releaseProposal.complete();
          await scheduler.drain();
        });
        await scheduler.tick();
        await proposalStarted.future;
        environment.idle = Duration.zero;
        await scheduler.tick();
        releaseProposal.complete();
        await scheduler.drain();
        expect(enqueued, isEmpty);
        expect(startedRoots, isEmpty);
        expect(repository.farmRuns(), isEmpty);
        expect(modelCalls, ['snapshot a', 'proposal a']);
        expect(scheduler.isRunning, isFalse);
      },
    );

    test('skips a project with an unfinished background task', () async {
      tasks = [
        WorktreeAgentTask(
          id: 'running',
          status: WorktreeAgentTaskStatus.running,
          branchName: 'agent/x',
          worktreePath: '/wt/x',
          codingProjectId: 'a',
          createdAt: _now,
          updatedAt: _now,
        ),
      ];
      await runner().run(isCancelled: () => false);
      expect(enqueued, isEmpty);
      expect(
        repository.farmRuns().first,
        isA<FarmRunRecord>().having((r) => r.detail, 'detail', 'busy'),
      );
    });

    test('stops promptly when the maintenance window closes', () async {
      final summary = await runner().run(isCancelled: () => true);
      expect(summary.started + summary.skipped, 0);
      expect(modelCalls, isEmpty);
    });
  });
}
