import '../entities/app_settings.dart';

/// A concrete, ready-to-call endpoint target resolved for a role: a base URL,
/// API key, and model. [endpointId] is empty for the primary endpoint.
class ResolvedEndpoint {
  const ResolvedEndpoint({
    required this.endpointId,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.isPrimary,
    required this.demotedToPrimary,
  });

  final String endpointId;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// True when this target is the primary (settings) endpoint.
  final bool isPrimary;

  /// True when a mesh endpoint was requested but it was missing, disabled, or
  /// unhealthy, so the router fell back to the primary endpoint.
  final bool demotedToPrimary;
}

/// LL8: resolves which endpoint a role should call, demoting an unreachable mesh
/// endpoint to the primary endpoint so an active turn never fails just because a
/// mesh member dropped (acceptance criterion).
///
/// Pure: it consumes a snapshot of registered endpoints and a set of unhealthy
/// endpoint ids (produced by [EndpointHealthTracker]); it performs no IO.
class MeshEndpointRouter {
  const MeshEndpointRouter();

  /// Resolve a target for a role.
  ///
  /// - [primaryBaseUrl] / [primaryApiKey]: the settings endpoint, always the
  ///   fallback.
  /// - [endpoints]: enabled registered mesh endpoints.
  /// - [requestedEndpointId]: the endpoint a role is assigned to; empty means
  ///   "use the primary endpoint".
  /// - [model]: the already-resolved role model to call.
  /// - [unhealthyEndpointIds]: ids currently considered unreachable.
  ResolvedEndpoint resolve({
    required String primaryBaseUrl,
    required String primaryApiKey,
    required List<NamedEndpoint> endpoints,
    required String requestedEndpointId,
    required String model,
    Set<String> unhealthyEndpointIds = const {},
  }) {
    final requested = requestedEndpointId.trim();
    if (requested.isEmpty) {
      return _primary(
        baseUrl: primaryBaseUrl,
        apiKey: primaryApiKey,
        model: model,
        demoted: false,
      );
    }

    NamedEndpoint? match;
    for (final endpoint in endpoints) {
      final normalized = endpoint.normalizedForPersistence();
      if (normalized.id == requested &&
          normalized.enabled &&
          normalized.isValid) {
        match = normalized;
        break;
      }
    }

    if (match == null || unhealthyEndpointIds.contains(match.id)) {
      return _primary(
        baseUrl: primaryBaseUrl,
        apiKey: primaryApiKey,
        model: model,
        demoted: true,
      );
    }

    return ResolvedEndpoint(
      endpointId: match.id,
      baseUrl: match.normalizedBaseUrl,
      apiKey: match.apiKey,
      model: model,
      isPrimary: false,
      demotedToPrimary: false,
    );
  }

  ResolvedEndpoint _primary({
    required String baseUrl,
    required String apiKey,
    required String model,
    required bool demoted,
  }) => ResolvedEndpoint(
    endpointId: '',
    baseUrl: baseUrl.trim(),
    apiKey: apiKey,
    model: model,
    isPrimary: true,
    demotedToPrimary: demoted,
  );
}

/// Health snapshot for a single endpoint.
class EndpointHealth {
  const EndpointHealth({
    this.consecutiveFailures = 0,
    this.lastSuccessAt,
    this.lastFailureAt,
  });

  final int consecutiveFailures;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  /// Unknown (never probed) endpoints are treated as healthy so they are tried
  /// at least once rather than pre-emptively demoted.
  bool isUnhealthy(int failureThreshold) =>
      consecutiveFailures >= failureThreshold;
}

/// LL8: tracks endpoint reachability from probe results and reports which
/// endpoints should currently be demoted. Pure and in-memory; the runtime
/// health-check loop (slice 4) feeds it [recordSuccess] / [recordFailure].
class EndpointHealthTracker {
  EndpointHealthTracker({this.failureThreshold = 2})
    : assert(failureThreshold >= 1);

  /// Consecutive failures before an endpoint is considered unhealthy.
  final int failureThreshold;

  final Map<String, EndpointHealth> _byId = <String, EndpointHealth>{};

  EndpointHealth healthFor(String endpointId) =>
      _byId[endpointId] ?? const EndpointHealth();

  void recordSuccess(String endpointId, {DateTime? at}) {
    final now = at ?? DateTime.now();
    _byId[endpointId] = EndpointHealth(
      consecutiveFailures: 0,
      lastSuccessAt: now,
      lastFailureAt: _byId[endpointId]?.lastFailureAt,
    );
  }

  /// Record a failed call for [endpointId].
  ///
  /// A [hard] failure is an unambiguous "endpoint is down" signal (e.g.
  /// connection refused / host unreachable) and demotes the endpoint
  /// immediately instead of waiting for [failureThreshold] consecutive
  /// failures. This avoids wasting a round-trip on a known-dead endpoint on the
  /// next secondary call. Ambiguous failures (timeouts, transient 5xx) still
  /// accrue gradually so a briefly flapping endpoint is not demoted on a single
  /// blip.
  void recordFailure(String endpointId, {DateTime? at, bool hard = false}) {
    final now = at ?? DateTime.now();
    final previous = _byId[endpointId] ?? const EndpointHealth();
    final nextFailures = hard
        ? (previous.consecutiveFailures + 1 < failureThreshold
              ? failureThreshold
              : previous.consecutiveFailures + 1)
        : previous.consecutiveFailures + 1;
    _byId[endpointId] = EndpointHealth(
      consecutiveFailures: nextFailures,
      lastSuccessAt: previous.lastSuccessAt,
      lastFailureAt: now,
    );
  }

  /// Forget an endpoint (e.g. when it is unregistered).
  void forget(String endpointId) => _byId.remove(endpointId);

  bool isUnhealthy(String endpointId) =>
      healthFor(endpointId).isUnhealthy(failureThreshold);

  /// Ids currently at or above the failure threshold.
  Set<String> get unhealthyEndpointIds => {
    for (final entry in _byId.entries)
      if (entry.value.isUnhealthy(failureThreshold)) entry.key,
  };
}
