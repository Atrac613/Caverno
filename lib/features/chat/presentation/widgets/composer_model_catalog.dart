import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/model_list_provider.dart';

/// The local endpoint's model list, as the composer's model menu reads it.
abstract final class ComposerModelCatalog {
  /// Keyed identically to the one the chat header uses for the token-usage
  /// indicator, so the two share a cached `/v1/models` fetch rather than
  /// issuing separate ones.
  static ModelListConfig configFor(AppSettings settings) {
    return ModelListConfig(
      baseUrl: settings.baseUrl.trim().isEmpty
          ? ApiConstants.defaultBaseUrl
          : settings.baseUrl.trim(),
      apiKey: settings.apiKey.trim().isEmpty
          ? ApiConstants.defaultApiKey
          : settings.apiKey.trim(),
      selectedModelId: settings.model.trim(),
    );
  }

  static Future<List<String>> load(WidgetRef ref, AppSettings settings) async {
    final config = configFor(settings);
    // Hold a listener while the request is in flight: the catalog provider is
    // autoDispose, and a bare read would let it drop mid-fetch.
    final subscription = ref.listenManual<AsyncValue<List<String>>>(
      modelListProvider(config),
      (_, _) {},
    );
    try {
      return await ref.read(modelListProvider(config).future);
    } finally {
      subscription.close();
    }
  }

  static void invalidate(WidgetRef ref, AppSettings settings) =>
      ref.invalidate(modelCatalogProvider(configFor(settings)));
}
