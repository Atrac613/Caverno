import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/presentation/providers/chat_data_source_provider.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../application/roadmap_snapshot_service.dart';
import '../../data/roadmap_snapshot_repository.dart';
import '../../domain/roadmap_next_task_extractor.dart';

final roadmapSnapshotRepositoryProvider =
    Provider<RoadmapSnapshotRepositoryApi>(
      (ref) => RoadmapSnapshotRepository(ref.watch(sharedPreferencesProvider)),
    );

final roadmapSnapshotServiceProvider = Provider<RoadmapSnapshotService>((ref) {
  return RoadmapSnapshotService(
    repository: ref.watch(roadmapSnapshotRepositoryProvider),
    ensureAccess: (projectId) => ref
        .read(codingProjectsNotifierProvider.notifier)
        .ensureProjectAccess(projectId),
    readFile: _readFileIfPresent,
    // Resolved per refresh so a settings change reaches the next extraction.
    extractor: () => RoadmapNextTaskExtractor(
      complete: structuredRoadmapCompletion(
        ref.read(chatRemoteDataSourceProvider),
        model: ref.read(settingsNotifierProvider).effectiveModel,
      ),
    ),
    model: () => ref.read(settingsNotifierProvider).effectiveModel,
  );
});

Future<String?> _readFileIfPresent(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsString();
}

/// Adapts the app's structured-output datasource to the extractor's port.
///
/// Uses the primary datasource with its own model, like the run-log analyser:
/// a role-pinned endpoint with an empty model would otherwise be sent the
/// primary model's name.
RoadmapCompletionPort structuredRoadmapCompletion(
  ChatDataSource dataSource, {
  required String model,
}) {
  return ({
    required String system,
    required String user,
    required String schemaName,
    required Map<String, dynamic> schema,
    required int maxTokens,
  }) async {
    if (dataSource is! StructuredOutputChatDataSource) {
      throw StateError(
        'The configured endpoint does not support structured output.',
      );
    }
    final source = dataSource as StructuredOutputChatDataSource;
    final now = DateTime.now();
    final result = await source.createStructuredChatCompletion(
      messages: [
        Message(
          id: 'roadmap-$schemaName-system',
          role: MessageRole.system,
          content: system,
          timestamp: now,
        ),
        Message(
          id: 'roadmap-$schemaName-user',
          role: MessageRole.user,
          content: user,
          timestamp: now,
        ),
      ],
      responseFormat: StructuredOutputRequest.jsonSchema(
        name: schemaName,
        schema: schema,
      ),
      model: model,
      temperature: 0,
      maxTokens: maxTokens,
    );
    return RoadmapCompletion(
      content: result.content,
      finishReason: result.finishReason,
    );
  };
}
