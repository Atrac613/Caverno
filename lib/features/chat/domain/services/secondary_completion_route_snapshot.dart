import '../../../settings/domain/entities/app_settings.dart';
import '../entities/model_usage_role.dart';

/// Immutable routing facts captured before a secondary completion starts.
final class SecondaryCompletionRouteSnapshot {
  SecondaryCompletionRouteSnapshot({
    required this.provider,
    required this.primaryBaseUrl,
    required this.primaryApiKey,
    required this.primaryModel,
    required List<LlmEndpoint> enabledEndpoints,
    required this.selectedEndpointId,
    required this.selectedModel,
    String? fallbackModel,
    this.usageRole = ModelUsageRole.unknown,
  }) : enabledEndpoints = List<LlmEndpoint>.unmodifiable(enabledEndpoints),
       fallbackModel = fallbackModel ?? primaryModel;

  final LlmProvider provider;
  final String primaryBaseUrl;
  final String primaryApiKey;
  final String primaryModel;
  final List<LlmEndpoint> enabledEndpoints;
  final String selectedEndpointId;
  final String selectedModel;
  final String fallbackModel;

  /// Which role this secondary completion serves, for per-model usage
  /// accounting. Carried on the route because the route is the only thing that
  /// already distinguishes planning from memory extraction from auto-review.
  final ModelUsageRole usageRole;
}

/// One planning-completion route attempt exposed for narrow logging.
final class SecondaryCompletionRouteMetadata {
  const SecondaryCompletionRouteMetadata({
    required this.model,
    required this.endpoint,
    required this.isFallback,
  });

  final String model;
  final String endpoint;
  final bool isFallback;
}
