import 'dart:async';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/project_farm/application/farm_unattended_runner.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds a valid proposal in flight; any dispatch is a test failure.
class FarmForegroundCancellationFixture {
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
        await releaseProposal.future;
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
            throw StateError('Cancelled fixture must never enqueue');
          },
      startReady: (_) => startCalls++,
    );
  }

  void release() {
    if (!releaseProposal.isCompleted) releaseProposal.complete();
  }
}
