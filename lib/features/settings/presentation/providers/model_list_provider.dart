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

final modelListProvider = FutureProvider.autoDispose
    .family<List<String>, ModelListConfig>((ref, config) async {
      final catalog = await ref.watch(modelCatalogProvider(config).future);
      return catalog.map((model) => model.id).toSet().toList()..sort();
    });
