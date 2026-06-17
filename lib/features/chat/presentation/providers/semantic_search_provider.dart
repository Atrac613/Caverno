import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/app_database.dart';
import '../../data/datasources/embeddings_client.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/drift_embedding_store.dart';
import '../../data/repositories/semantic_indexing_service.dart';
import '../../data/repositories/semantic_search_service.dart';

/// The drift database opened at bootstrap, or null when drift is unavailable
/// (Hive fallback). Overridden in main on a successful drift init.
final appDatabaseProvider = Provider<AppDatabase?>((ref) => null);

/// LL5 embeddings client for the active endpoint, or null when semantic search
/// is off, no embeddings model is configured, or the provider is on-device.
final embeddingsClientProvider = Provider<EmbeddingsClient?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (settings.llmProvider != LlmProvider.openAiCompatible) return null;
  if (!settings.enableSemanticSearch) return null;
  if (settings.embeddingsModel.trim().isEmpty) return null;
  final client = EmbeddingsClient(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
  );
  ref.onDispose(client.close);
  return client;
});

/// LL5 vector store over the drift database, or null when drift is unavailable.
final driftEmbeddingStoreProvider = Provider<DriftEmbeddingStore?>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database == null ? null : DriftEmbeddingStore(database);
});

/// LL5 indexing service, or null when semantic search is unavailable.
final semanticIndexingServiceProvider = Provider<SemanticIndexingService?>((
  ref,
) {
  final client = ref.watch(embeddingsClientProvider);
  final store = ref.watch(driftEmbeddingStoreProvider);
  if (client == null || store == null) return null;
  final model = ref.watch(settingsNotifierProvider).embeddingsModel;
  return SemanticIndexingService(
    embed: (inputs) => client.embed(inputs: inputs, model: model),
    store: store,
    model: model,
  );
});

/// LL5 history search service (semantic with lexical FTS fallback), or null when
/// semantic search is unavailable — callers then use lexical search directly.
final semanticSearchServiceProvider = Provider<SemanticSearchService?>((ref) {
  final client = ref.watch(embeddingsClientProvider);
  final store = ref.watch(driftEmbeddingStoreProvider);
  if (client == null || store == null) return null;
  final model = ref.watch(settingsNotifierProvider).embeddingsModel;
  final repository = ref.watch(conversationRepositoryProvider);
  return SemanticSearchService(
    embed: (inputs) => client.embed(inputs: inputs, model: model),
    store: store,
    lexicalFallback: (query) async =>
        (await repository.search(query)).map((c) => c.id).toList(),
  );
});
