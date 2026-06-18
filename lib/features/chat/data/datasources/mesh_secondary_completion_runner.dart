import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/mesh_endpoint_router.dart';

/// A resolved data source target for a role: the [dataSource] to call, the
/// [model] to request, and which endpoint it is (empty [endpointId] / [isPrimary]
/// for the primary endpoint).
class ResolvedDataSource<D> {
  const ResolvedDataSource({
    required this.dataSource,
    required this.model,
    required this.endpointId,
    required this.isPrimary,
  });

  final D dataSource;
  final String model;
  final String endpointId;
  final bool isPrimary;
}

/// LL8: runs a secondary LLM call (memory extraction, subagent, goal
/// suggestion, approval auto-review) against a role-assigned mesh endpoint,
/// degrading to the primary endpoint so an active turn is never lost.
///
/// Resolution is delegated to [MeshEndpointRouter]; reachability is recorded in
/// [EndpointHealthTracker] so a flapping endpoint is demoted on the next call.
/// Within a single call, a thrown error also falls back to the primary endpoint.
///
/// Generic over the data-source type [D] so it stays a pure routing helper: it
/// only resolves an endpoint and hands the matching data source to the caller's
/// closure, never invoking the data source itself.
class MeshSecondaryCompletionRunner<D> {
  MeshSecondaryCompletionRunner({
    required this.router,
    required this.health,
    required this.buildEndpointDataSource,
  });

  final MeshEndpointRouter router;
  final EndpointHealthTracker health;

  /// Builds (and is cached for) a data source bound to a mesh endpoint.
  final D Function(String baseUrl, String apiKey) buildEndpointDataSource;

  final Map<String, D> _cache = <String, D>{};

  /// Resolve [endpointId] for a role and run [call] against the target endpoint.
  ///
  /// - [primary] is the settings-bound data source used when the role targets
  ///   the primary endpoint or when a mesh endpoint is unavailable.
  /// - [call] receives the resolved data source and the model to request.
  Future<T> run<T>({
    required D primary,
    required String primaryBaseUrl,
    required String primaryApiKey,
    required List<NamedEndpoint> endpoints,
    required String endpointId,
    required String model,
    required Future<T> Function(D dataSource, String model) call,
  }) async {
    final resolved = resolve(
      primary: primary,
      primaryBaseUrl: primaryBaseUrl,
      primaryApiKey: primaryApiKey,
      endpoints: endpoints,
      endpointId: endpointId,
      model: model,
    );

    if (resolved.isPrimary) {
      return call(resolved.dataSource, resolved.model);
    }

    try {
      final result = await call(resolved.dataSource, resolved.model);
      health.recordSuccess(resolved.endpointId);
      return result;
    } catch (_) {
      // The mesh endpoint failed mid-call: demote it for next time and retry on
      // the primary so the active turn still completes.
      health.recordFailure(resolved.endpointId);
      return call(primary, model);
    }
  }

  /// Resolve [endpointId] to a concrete data source + model without calling it.
  ///
  /// For multi-turn callers (e.g. subagents) that build their own execution
  /// loop: pick the data source here, run, then record the outcome via
  /// [health.recordSuccess] / [health.recordFailure] when not [isPrimary].
  ResolvedDataSource<D> resolve({
    required D primary,
    required String primaryBaseUrl,
    required String primaryApiKey,
    required List<NamedEndpoint> endpoints,
    required String endpointId,
    required String model,
  }) {
    final target = router.resolve(
      primaryBaseUrl: primaryBaseUrl,
      primaryApiKey: primaryApiKey,
      endpoints: endpoints,
      requestedEndpointId: endpointId,
      model: model,
      unhealthyEndpointIds: health.unhealthyEndpointIds,
    );
    return ResolvedDataSource<D>(
      dataSource: target.isPrimary
          ? primary
          : _dataSourceFor(target.baseUrl, target.apiKey),
      model: target.model,
      endpointId: target.endpointId,
      isPrimary: target.isPrimary,
    );
  }

  D _dataSourceFor(String baseUrl, String apiKey) {
    final key = '$baseUrl $apiKey';
    return _cache[key] ??= buildEndpointDataSource(baseUrl, apiKey);
  }
}
