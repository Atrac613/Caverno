import 'dart:async';

import 'package:caverno/features/chat/data/repositories/worktree_agent_task_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/project_farm/application/farm_unattended_runner.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds a valid proposal in flight; any dispatch is a test failure.
class FarmForegroundCancellationFixture {
  FarmForegroundCancellationFixture({this.holdRegistration = false});
  final bool holdRegistration;
  ProviderContainer? registryContainer;
  final registrationStarted = Completer<void>();
  WorktreeAgentTask? heldTask;
  final proposalStarted = Completer<void>();
  final releaseProposal = Completer<void>();
  int enqueueCalls = 0;
  int startCalls = 0;
  late final FarmUnattendedRunner runner;

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    final repository = RoadmapSnapshotRepository(
      await SharedPreferences.getInstance(),
    );
    if (holdRegistration) {
      registryContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
    }
    final now = DateTime.now();
    final project = CodingProject(
      id: 'cancel-fixture',
      name: 'cancel-fixture',
      rootPath: '/synthetic',
      createdAt: now,
      updatedAt: now,
    );
    await repository.savePolicy(
      ProjectFarmPolicy(
        projectId: project.id,
        autoRunEnabled: true,
        dailyRunLimit: 1,
        allowedVerificationCommands: ['python verify.py'],
        unattendedCommands: ['python verify.py'],
        updatedAt: now,
      ),
    );
    runner = FarmUnattendedRunner(
      repository: repository,
      projects: () => [project],
      tasks: () => [],
      refreshSnapshot: (_) async => RoadmapSnapshot(
        projectId: project.id,
        roadmapPath: 'roadmap.md',
        contentSha256: 'fixture',
        extractorVersion: 3,
        model: 'fixture',
        extractedAt: now,
        status: RoadmapSnapshotStatus.verified,
        recommended: const RoadmapItemSnapshot(
          id: 'GR1',
          title: 'Greeting',
          quote: 'GR1: Update greeting.txt',
          line: 1,
        ),
      ),
      refreshProposal: (_, _) async {
        proposalStarted.complete();
        if (!holdRegistration) await releaseProposal.future;
        return ProjectProposal(
          projectId: project.id,
          inputHash: 'fixture',
          proposedAt: now,
          taskId: 'GR1',
          automatability: 'unattended',
        );
      },
      enqueue:
          ({
            required title,
            required prompt,
            required codingProjectId,
            required projectRootPath,
            required verificationCommand,
            required acceptanceCriteria,
          }) async {
            enqueueCalls++;
            if (!holdRegistration) {
              throw StateError('Cancelled fixture must never enqueue');
            }
            heldTask = await registryContainer!
                .read(worktreeAgentTaskRegistryNotifierProvider.notifier)
                .registerTask(
                  deferStart: true,
                  title: title,
                  prompt: prompt,
                  codingProjectId: codingProjectId,
                  branchName: 'feature/held-fixture',
                  worktreePath: '/synthetic/held-fixture',
                  verificationCommand: verificationCommand,
                );
            registrationStarted.complete();
            await releaseProposal.future;
            return heldTask!;
          },
      admit: (task, canStart, start) async {
        if (holdRegistration) {
          return registryContainer!
              .read(worktreeAgentTaskRegistryNotifierProvider.notifier)
              .admitHeldTask(task.id, canStart: canStart, start: start);
        }
        if (!canStart()) return false;
        start();
        return true;
      },
      startReady: (_) => startCalls++,
    );
  }

  String get heldStatus => registryContainer!
      .read(worktreeAgentTaskRegistryNotifierProvider)
      .tasks
      .single
      .status
      .name;
  String get persistedStatus => registryContainer!
      .read(worktreeAgentTaskRepositoryProvider)
      .loadAll()
      .single
      .status
      .name;
  void dispose() => registryContainer?.dispose();

  void release() {
    if (!releaseProposal.isCompleted) releaseProposal.complete();
  }
}
