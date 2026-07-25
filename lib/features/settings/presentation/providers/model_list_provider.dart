import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model_remote_datasource.dart';
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

final modelCatalogProvider = FutureProvider.autoDispose
    .family<List<ModelCatalogEntry>, ModelListConfig>((ref, config) async {
      final dataSource = ModelRemoteDataSource(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
      );
      return dataSource.listModelCatalog(
        selectedModelId: config.selectedModelId,
      );
    });

/// Server-reported context window for [ModelListConfig.selectedModelId], or
/// null when the endpoint advertises none.
///
/// The catalog already resolves this per server family (llama.cpp `/props` +
/// `/slots`, LM Studio loaded instances, Ollama `num_ctx`, OpenAI
/// `context_length`), so capability probing reads ground truth here instead of
/// estimating a context budget. Never throws: an unreachable or silent endpoint
/// is reported as "unmeasured" (null), never as a guessed number.
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
