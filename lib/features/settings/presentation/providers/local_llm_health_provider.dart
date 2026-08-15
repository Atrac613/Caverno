import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/local_llm_health.dart';
import '../../domain/services/local_llm_endpoint_predicate.dart';
import '../../domain/services/local_llm_health_service.dart';
import 'local_model_lifecycle_provider.dart';
import 'settings_notifier.dart';

/// How often the panel re-checks while it is open.
///
/// A local server is started and stopped by hand, so the answer changes on a
/// human timescale. Long enough that the panel is not a load generator, short
/// enough that "I just started LM Studio" shows up without a manual refresh.
///
/// The ticker lives in the panel widget rather than in the provider below: a
/// timer owned by a provider outlives the widget tree in tests and leaks into
/// whatever runs next, while a widget's `dispose` is deterministic.
const localLlmHealthRefreshInterval = Duration(seconds: 30);

final localLlmHealthServiceProvider = Provider<LocalLlmHealthService>((ref) {
  return const LocalLlmHealthService();
});

/// The registered endpoints served from this machine or the local network.
///
/// Hosted endpoints are excluded rather than shown as permanently online: the
/// panel answers "is my local stack up and what is loaded", which a hosted API
/// cannot be asked.
final localLlmHealthEndpointsProvider =
    Provider<List<LocalModelLifecycleEndpointConfig>>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      if (settings.llmProvider != LlmProvider.openAiCompatible) {
        return const <LocalModelLifecycleEndpointConfig>[];
      }
      const predicate = LocalLlmEndpointPredicate();
      final discoveredBaseUrls = {
        for (final endpoint in settings.enabledLlmEndpoints)
          if (endpoint.source == LlmEndpointSource.discovered)
            endpoint.normalizedBaseUrl.toLowerCase(),
      };
      return [
        for (final endpoint in ref.watch(
          localModelLifecycleEndpointOptionsProvider,
        ))
          if (predicate.isLocal(
            endpoint.baseUrl,
            discovered: discoveredBaseUrls.contains(
              LlmEndpoint.normalizeBaseUrl(endpoint.baseUrl).toLowerCase(),
            ),
          ))
            endpoint,
      ];
    });

/// Liveness and loaded models for one registered local endpoint.
///
/// Never throws: an unreachable server is a result ("offline"), not an error,
/// because that is exactly what the panel exists to show.
final localLlmHealthProvider = FutureProvider.autoDispose
    .family<LocalLlmHealthSnapshot, LocalModelLifecycleEndpointConfig>((
      ref,
      endpoint,
    ) async {
      final dataSource = ref.watch(
        localModelLifecycleDataSourceFactoryProvider,
      )(endpoint);
      return ref
          .watch(localLlmHealthServiceProvider)
          .probe(
            endpointId: endpoint.id,
            label: endpoint.label,
            baseUrl: endpoint.baseUrl,
            isPrimary: endpoint.isPrimary,
            listModelIds: dataSource.listModelIds,
            listManagedModels: dataSource.listManagedModels,
          );
    });
