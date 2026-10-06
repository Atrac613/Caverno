import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/project_farm/application/farm_unattended_runner.dart';
import 'package:caverno/features/project_farm/application/project_proposal_service.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/presentation/providers/roadmap_snapshot_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'farm_unattended_snapshot_probe.dart';

/// Real production structured proposals from live verified snapshots.
class FarmUnattendedProposalProbe {
  FarmUnattendedProposalProbe({
    required this.repository,
    required ChatDataSource source,
    required String model,
    required this.now,
    required this.snapshots,
  }) : service = ProjectProposalService(
         repository: repository,
         complete: () => structuredRoadmapCompletion(source, model: model),
         model: () => model,
         now: () => now,
       );

  final RoadmapSnapshotRepository repository;
  final ProjectProposalService service;
  final DateTime now;
  final FarmUnattendedSnapshotProbe snapshots;
  ProjectProposal? positive;

  Future<ProjectProposal?> refresh(
    CodingProject project,
    RoadmapSnapshot? snapshot,
  ) async {
    final proposal = await service.refresh(
      project: project,
      snapshot: snapshot,
      threads: [],
    );
    positive = proposal;
    return proposal;
  }

  Future<Map<String, Object?>> checkHumanGate(CodingProject original) async {
    expect(positive?.error, isNull);
    expect(positive?.taskId, 'GR1');
    expect(positive?.automatability, 'unattended');
    final humanRoot = await Directory(
      '${Directory(original.rootPath).parent.path}/human-project',
    ).create();
    await File('${humanRoot.path}/roadmap.md').writeAsString(
      '# Physical device roadmap\n\nNext: HUMAN\n\n'
      '- [ ] HUMAN: A person must connect a physical phone and speak into '
      'its microphone to verify recorded audio. File edits or a test command '
      'cannot complete this physical device check.\n',
    );
    final human = original.copyWith(
      id: 'human-fixture',
      name: 'physical-device-fixture',
      rootPath: humanRoot.path,
    );
    await repository.savePolicy(
      ProjectFarmPolicy(
        projectId: human.id,
        allowedVerificationCommands: ['./python verify.py'],
        unattendedCommands: ['./python verify.py'],
        autoRunEnabled: true,
        dailyRunLimit: 1,
        updatedAt: now,
      ),
    );
    ProjectProposal? negative;
    var enqueueCalls = 0;
    var startCalls = 0;
    final runner = FarmUnattendedRunner(
      repository: repository,
      projects: () => [human],
      refreshSnapshot: snapshots.refresh,
      refreshProposal: (project, snapshot) async {
        negative = await service.refresh(
          project: project,
          snapshot: snapshot,
          threads: [],
        );
        return negative;
      },
      tasks: () => [],
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
            throw StateError('Physical-device fixture must never enqueue');
          },
      admit: (task, canStart, start) async {
        if (!canStart()) return false;
        start();
        return true;
      },
      startReady: (_) {
        startCalls++;
      },
      now: () => now,
    );
    final summary = await runner.run(isCancelled: () => false);
    expect(negative?.error, isNull);
    // The production contract permits abstention for a human-only task.
    expect(negative?.taskId, anyOf('', 'HUMAN'));
    expect(negative?.automatability, 'needsHuman');
    expect(summary.started, 0);
    expect(summary.skipped, 1);
    expect(enqueueCalls, 0);
    expect(startCalls, 0);
    final ledger = repository
        .farmRuns()
        .where((r) => r.projectId == human.id)
        .single;
    expect(ledger.detail, 'needsHuman');
    return {
      'positive': positive!.toJson(),
      'negative': negative!.toJson(),
      'negativeEnqueueCalls': enqueueCalls,
      'negativeStartCalls': startCalls,
      'negativeLedger': ledger.toJson(),
    };
  }
}
