import '../entities/local_llm_health.dart';
import '../entities/local_model_lifecycle.dart';

/// Lists the model ids an endpoint advertises. Throws when unreachable, which
/// is the liveness signal.
typedef LocalLlmModelIdProbe = Future<List<String>> Function();

/// Reports per-model lifecycle state, or an unsupported catalog when the
/// server has no lifecycle API.
typedef LocalLlmManagedModelProbe =
    Future<LocalModelLifecycleCatalog> Function();

/// Builds the liveness view of one registered local LLM.
///
/// Liveness and loaded models are two questions and are asked separately: a
/// server can answer `/v1/models` while exposing no lifecycle API, and a
/// lifecycle call that fails must not be read as "the server is down". The
/// advertised list is only used as a fallback for the model names, never as
/// the liveness answer.
class LocalLlmHealthService {
  const LocalLlmHealthService();

  Future<LocalLlmHealthSnapshot> probe({
    required String endpointId,
    required String label,
    required String baseUrl,
    required bool isPrimary,
    required LocalLlmModelIdProbe listModelIds,
    required LocalLlmManagedModelProbe listManagedModels,
    DateTime Function()? clock,
  }) async {
    final now = clock ?? DateTime.now;
    final List<String> advertised;
    try {
      advertised = await listModelIds();
    } on Object catch (error) {
      return LocalLlmHealthSnapshot.offline(
        endpointId: endpointId,
        label: label,
        baseUrl: baseUrl,
        isPrimary: isPrimary,
        checkedAt: now(),
        detail: _describe(error),
      );
    }

    LocalModelLifecycleCatalog? catalog;
    String? lifecycleError;
    try {
      catalog = await listManagedModels();
    } on Object catch (error) {
      // The endpoint answered a moment ago, so this is a lifecycle-API
      // problem, not a dead server.
      lifecycleError = _describe(error);
    }

    if (catalog != null && catalog.supported) {
      final loaded = [
        for (final model in catalog.models)
          if (model.isLoaded) model.id,
      ];
      return LocalLlmHealthSnapshot(
        endpointId: endpointId,
        label: label,
        baseUrl: baseUrl,
        isPrimary: isPrimary,
        reachability: LocalLlmReachability.online,
        modelEvidence: loaded.isEmpty
            ? LocalLlmModelEvidence.none
            : LocalLlmModelEvidence.loaded,
        modelIds: List.unmodifiable(loaded),
        checkedAt: now(),
        detail: catalog.message,
      );
    }

    return LocalLlmHealthSnapshot(
      endpointId: endpointId,
      label: label,
      baseUrl: baseUrl,
      isPrimary: isPrimary,
      reachability: LocalLlmReachability.online,
      modelEvidence: advertised.isEmpty
          ? LocalLlmModelEvidence.none
          : LocalLlmModelEvidence.advertised,
      modelIds: List.unmodifiable(advertised),
      checkedAt: now(),
      detail: lifecycleError ?? catalog?.message,
    );
  }

  static String _describe(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    const maxChars = 160;
    return text.length <= maxChars ? text : '${text.substring(0, maxChars)}...';
  }
}
