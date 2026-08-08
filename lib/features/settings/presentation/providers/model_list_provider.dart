import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model_remote_datasource.dart';
import '../../data/published_model_context_windows.dart';
import '../../domain/entities/model_catalog_entry.dart';

class ModelListConfig {
  const ModelListConfig({
    required this.baseUrl,
    required this.apiKey,
    this.selectedModelId,
  });

  final String baseUrl;
  final String apiKey;
  final String? selectedModelId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ModelListConfig &&
            baseUrl == other.baseUrl &&
            apiKey == other.apiKey &&
            selectedModelId == other.selectedModelId;
  }

  @override
  int get hashCode => Object.hash(baseUrl, apiKey, selectedModelId);
}

/// Model catalog for [ModelListConfig], with published context windows filled in
/// for entries the endpoint left silent.
///
/// The datasource reports only what the endpoint said; composing that with
/// bundled vendor specs happens here so the two sources stay distinguishable.
final modelCatalogProvider = FutureProvider.autoDispose
    .family<List<ModelCatalogEntry>, ModelListConfig>((ref, config) async {
      final dataSource = ModelRemoteDataSource(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
      );
      final catalog = await dataSource.listModelCatalog(
        selectedModelId: config.selectedModelId,
      );
      return PublishedModelContextWindows.fill(catalog);
    });

/// Context window for [ModelListConfig.selectedModelId], or null when neither
/// the endpoint nor the bundled published specs know one.
///
/// The catalog resolves this per server family first (llama.cpp `/props` +
/// `/slots`, LM Studio loaded instances, Ollama `num_ctx`, a gateway's
/// `context_length`), then falls back to the vendor's published figure for
/// models whose endpoint advertises nothing — OpenAI's `/v1/models` never does.
/// Either way the number is documented rather than estimated; check
/// `ModelCatalogEntry.contextWindowSource` when the distinction matters. Never
/// throws: an unreachable endpoint with an unlisted model is reported as
/// "unmeasured" (null), never as a guess.
final modelContextWindowProvider = FutureProvider.autoDispose
    .family<int?, ModelListConfig>((ref, config) async {
      final selectedModelId = config.selectedModelId?.trim();
      if (selectedModelId == null || selectedModelId.isEmpty) return null;
      try {
        final catalog = await ref.watch(modelCatalogProvider(config).future);
        for (final entry in catalog) {
          if (entry.id.trim() == selectedModelId) {
            return entry.contextWindowTokens;
          }
        }
      } on Object {
        return null;
      }
      return null;
    });

final modelListProvider = FutureProvider.autoDispose
    .family<List<String>, ModelListConfig>((ref, config) async {
      final catalog = await ref.watch(modelCatalogProvider(config).future);
      return catalog.map((model) => model.id).toSet().toList()..sort();
    });
