import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/project_farm/application/roadmap_snapshot_service.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/domain/roadmap_next_task_extractor.dart';
import 'package:caverno/features/project_farm/presentation/providers/roadmap_snapshot_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Production file discovery, live extraction, quote verification and storage.
class FarmUnattendedSnapshotProbe {
  FarmUnattendedSnapshotProbe({
    required RoadmapSnapshotRepository repository,
    required ChatDataSource source,
    required String model,
    required String scratchRoot,
    required DateTime now,
  }) : service = RoadmapSnapshotService(
         repository: repository,
         // Fixture access replaces the host's bookmark authorization only.
         ensureAccess: (_) async => true,
         readFile: (path) async {
           if (!p.isWithin(scratchRoot, path)) {
             throw StateError('Snapshot read escaped the fixture');
           }
           final file = File(path);
           return await file.exists() ? file.readAsString() : null;
         },
         extractor: () => RoadmapNextTaskExtractor(
           complete: structuredRoadmapCompletion(source, model: model),
         ),
         model: () => model,
         now: () => now,
       );

  final RoadmapSnapshotService service;
  final evidence = <String, Object?>{};

  Future<RoadmapSnapshot?> refresh(CodingProject project) async {
    final snapshot = await service.refresh(
      projectId: project.id,
      projectRoot: project.rootPath,
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.status, RoadmapSnapshotStatus.verified);
    expect(snapshot.error, isNull);
    expect(snapshot.recommended?.verified, isTrue);
    expect(
      snapshot.recommended?.id,
      project.id == 'synthetic' ? 'GR1' : 'HUMAN',
    );
    expect(service.cachedSnapshot(project.id)?.toJson(), snapshot.toJson());
    evidence[project.id] = {
      'snapshot': snapshot.toJson(),
      'document': await File(
        '${project.rootPath}/${snapshot.roadmapPath}',
      ).readAsString(),
    };
    return snapshot;
  }
}
