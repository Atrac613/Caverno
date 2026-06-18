import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_host_resource_probe.dart';
import '../../data/model_remote_datasource.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/local_host_resources.dart';
import '../../domain/entities/local_model_lifecycle.dart';
import '../../domain/services/local_model_preparation_service.dart';
import '../../domain/services/local_stack_recommendation_service.dart';
import 'settings_notifier.dart';

class LocalModelLifecycleEndpointConfig {
  const LocalModelLifecycleEndpointConfig({
    required this.id,
    required this.baseUrl,
    required this.apiKey,
    required this.label,
    required this.isPrimary,
  });

  const LocalModelLifecycleEndpointConfig.primary({
    required String baseUrl,
    required String apiKey,
  }) : this(
         id: '',
         baseUrl: baseUrl,
         apiKey: apiKey,
         label: '',
         isPrimary: true,
       );

  final String id;
  final String baseUrl;
  final String apiKey;
  final String label;
  final bool isPrimary;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalModelLifecycleEndpointConfig &&
            id == other.id &&
            baseUrl == other.baseUrl &&
            apiKey == other.apiKey &&
            label == other.label &&
            isPrimary == other.isPrimary;
  }

  @override
  int get hashCode => Object.hash(id, baseUrl, apiKey, label, isPrimary);
}

final localModelLifecycleDataSourceProvider = Provider<ModelRemoteDataSource>((
  ref,
) {
  final settings = ref.watch(settingsNotifierProvider);
  return ModelRemoteDataSource(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
  );
});

typedef LocalModelLifecycleDataSourceFactory =
    ModelRemoteDataSource Function(LocalModelLifecycleEndpointConfig endpoint);

final localModelLifecycleDataSourceFactoryProvider =
    Provider<LocalModelLifecycleDataSourceFactory>((ref) {
      final primaryDataSource = ref.watch(
        localModelLifecycleDataSourceProvider,
      );
      return (endpoint) {
        if (endpoint.isPrimary) {
          return primaryDataSource;
        }
        return ModelRemoteDataSource(
          baseUrl: endpoint.baseUrl,
          apiKey: endpoint.apiKey,
        );
      };
    });

final localModelPreparationServiceProvider =
    Provider<LocalModelPreparationService>((ref) {
      return const LocalModelPreparationService();
    });

final localStackRecommendationServiceProvider =
    Provider<LocalStackRecommendationService>((ref) {
      return const LocalStackRecommendationService();
    });

final localHostResourceProbeProvider = Provider<LocalHostResourceProbe>((ref) {
  return LocalHostResourceProbe();
});

final localHostResourceProfileProvider =
    FutureProvider<LocalHostResourceProfile>((ref) async {
      return ref.watch(localHostResourceProbeProvider).probe();
    });

final localModelLifecycleEndpointOptionsProvider =
    Provider<List<LocalModelLifecycleEndpointConfig>>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      return [
        LocalModelLifecycleEndpointConfig.primary(
          baseUrl: settings.baseUrl,
          apiKey: settings.apiKey,
        ),
        for (final endpoint in settings.namedEndpoints)
          if (endpoint.isValid)
            LocalModelLifecycleEndpointConfig(
              id: endpoint.computedId,
              baseUrl: endpoint.normalizedBaseUrl,
              apiKey: endpoint.apiKey,
              label: endpoint.displayLabel,
              isPrimary: false,
            ),
      ];
    });

/// LL9 managed-model catalog for the primary OpenAI-compatible endpoint.
///
/// Unsupported endpoints intentionally return an unsupported catalog instead
/// of throwing so Settings can explain that lifecycle controls are unavailable.
final localModelLifecycleCatalogProvider =
    FutureProvider<LocalModelLifecycleCatalog>((ref) async {
      final primaryEndpoint = ref.watch(
        localModelLifecycleEndpointOptionsProvider.select(
          (endpoints) => endpoints.first,
        ),
      );
      return ref.watch(
        localModelLifecycleCatalogForEndpointProvider(primaryEndpoint).future,
      );
    });

final localModelLifecycleCatalogForEndpointProvider =
    FutureProvider.family<
      LocalModelLifecycleCatalog,
      LocalModelLifecycleEndpointConfig
    >((ref, endpoint) async {
      final settings = ref.watch(settingsNotifierProvider);
      if (settings.llmProvider != LlmProvider.openAiCompatible) {
        return const LocalModelLifecycleCatalog.unsupported(
          message:
              'Model lifecycle management is only available for '
              'OpenAI-compatible endpoints.',
        );
      }
      return ref
          .watch(localModelLifecycleDataSourceFactoryProvider)(endpoint)
          .listManagedModels();
    });
