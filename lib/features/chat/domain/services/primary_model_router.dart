import '../../../../core/types/assistant_mode.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/mesh_endpoint_router.dart';

enum PrimaryRouteReason {
  primaryDefault,
  explicitModeModel,
  endpointDefaultModel,
  explicitEndpointModel,
  endpointUnavailable,
  endpointModelMissing,
  appleFoundationModels,
}

final class PrimaryRouteContext {
  const PrimaryRouteContext({
    required this.settings,
    required this.assistantMode,
    this.unhealthyEndpointIds = const <String>{},
  });

  final AppSettings settings;
  final AssistantMode assistantMode;
  final Set<String> unhealthyEndpointIds;
}

final class PrimaryRouteResolution {
  const PrimaryRouteResolution({
    required this.context,
    required this.endpoint,
    required this.fallbackModel,
    required this.reason,
    required this.requestedEndpointId,
    required this.requestedModel,
    this.escalationRequested = false,
  });

  final PrimaryRouteContext context;
  final ResolvedEndpoint endpoint;
  final String fallbackModel;
  final PrimaryRouteReason reason;
  final String requestedEndpointId;
  final String requestedModel;

  /// Reserved LL25 seam. LL24's default checkpoint always returns false.
  final bool escalationRequested;

  bool get isDemoted => endpoint.demotedToPrimary;
}

abstract interface class PrimaryRouteEscalationCheckpoint {
  bool shouldEscalate({
    required PrimaryRouteContext context,
    required ResolvedEndpoint resolvedEndpoint,
  });
}

final class NoopPrimaryRouteEscalationCheckpoint
    implements PrimaryRouteEscalationCheckpoint {
  const NoopPrimaryRouteEscalationCheckpoint();

  @override
  bool shouldEscalate({
    required PrimaryRouteContext context,
    required ResolvedEndpoint resolvedEndpoint,
  }) => false;
}

/// LL24's single decision point for primary conversation turns.
///
/// The service is pure: endpoint health is supplied as a snapshot, and the
/// resolved route can be captured by a turn owner without reading providers or
/// mutable settings again. LL25 can replace the no-op escalation checkpoint
/// without changing request call sites.
final class PrimaryModelRouter {
  const PrimaryModelRouter({
    MeshEndpointRouter meshRouter = const MeshEndpointRouter(),
    PrimaryRouteEscalationCheckpoint escalationCheckpoint =
        const NoopPrimaryRouteEscalationCheckpoint(),
  }) : _meshRouter = meshRouter,
       _escalationCheckpoint = escalationCheckpoint;

  final MeshEndpointRouter _meshRouter;
  final PrimaryRouteEscalationCheckpoint _escalationCheckpoint;

  PrimaryRouteResolution resolve(PrimaryRouteContext context) {
    final settings = context.settings;
    final fallbackModel = settings.effectiveModel;
    if (settings.llmProvider == LlmProvider.appleFoundationModels) {
      final endpoint = _primaryEndpoint(
        settings: settings,
        model: fallbackModel,
      );
      return _result(
        context: context,
        endpoint: endpoint,
        fallbackModel: fallbackModel,
        reason: PrimaryRouteReason.appleFoundationModels,
        requestedEndpointId: '',
        requestedModel: fallbackModel,
      );
    }

    final requestedEndpointId = settings
        .primaryEndpointIdFor(context.assistantMode)
        .trim();
    final explicitModel = settings
        .primaryModelOverrideFor(context.assistantMode)
        .trim();
    final assignedEndpoint = _enabledEndpoint(
      settings.enabledLlmEndpoints,
      requestedEndpointId,
    );
    final endpointDefaultModel = assignedEndpoint?.normalizedModel ?? '';
    final requestedModel = explicitModel.isNotEmpty
        ? explicitModel
        : endpointDefaultModel.isNotEmpty
        ? endpointDefaultModel
        : fallbackModel;

    if (requestedEndpointId.isEmpty) {
      return _result(
        context: context,
        endpoint: _primaryEndpoint(settings: settings, model: requestedModel),
        fallbackModel: fallbackModel,
        reason: explicitModel.isEmpty
            ? PrimaryRouteReason.primaryDefault
            : PrimaryRouteReason.explicitModeModel,
        requestedEndpointId: requestedEndpointId,
        requestedModel: requestedModel,
      );
    }

    if (assignedEndpoint != null &&
        explicitModel.isEmpty &&
        endpointDefaultModel.isEmpty) {
      return _result(
        context: context,
        endpoint: _primaryEndpoint(
          settings: settings,
          model: fallbackModel,
          demoted: true,
        ),
        fallbackModel: fallbackModel,
        reason: PrimaryRouteReason.endpointModelMissing,
        requestedEndpointId: requestedEndpointId,
        requestedModel: fallbackModel,
      );
    }

    final resolved = _meshRouter.resolve(
      primaryBaseUrl: settings.baseUrl,
      primaryApiKey: settings.apiKey,
      endpoints: settings.enabledLlmEndpoints,
      requestedEndpointId: requestedEndpointId,
      model: requestedModel,
      unhealthyEndpointIds: context.unhealthyEndpointIds,
    );
    if (resolved.demotedToPrimary) {
      return _result(
        context: context,
        endpoint: _primaryEndpoint(
          settings: settings,
          model: fallbackModel,
          demoted: true,
        ),
        fallbackModel: fallbackModel,
        reason: PrimaryRouteReason.endpointUnavailable,
        requestedEndpointId: requestedEndpointId,
        requestedModel: requestedModel,
      );
    }

    return _result(
      context: context,
      endpoint: resolved,
      fallbackModel: fallbackModel,
      reason: explicitModel.isEmpty
          ? PrimaryRouteReason.endpointDefaultModel
          : PrimaryRouteReason.explicitEndpointModel,
      requestedEndpointId: requestedEndpointId,
      requestedModel: requestedModel,
    );
  }

  PrimaryRouteResolution _result({
    required PrimaryRouteContext context,
    required ResolvedEndpoint endpoint,
    required String fallbackModel,
    required PrimaryRouteReason reason,
    required String requestedEndpointId,
    required String requestedModel,
  }) => PrimaryRouteResolution(
    context: context,
    endpoint: endpoint,
    fallbackModel: fallbackModel,
    reason: reason,
    requestedEndpointId: requestedEndpointId,
    requestedModel: requestedModel,
    escalationRequested: _escalationCheckpoint.shouldEscalate(
      context: context,
      resolvedEndpoint: endpoint,
    ),
  );

  LlmEndpoint? _enabledEndpoint(
    List<LlmEndpoint> endpoints,
    String endpointId,
  ) {
    if (endpointId.isEmpty) return null;
    for (final endpoint in endpoints) {
      final normalized = endpoint.normalizedForPersistence();
      if (normalized.id == endpointId &&
          normalized.enabled &&
          normalized.isValid) {
        return normalized;
      }
    }
    return null;
  }

  ResolvedEndpoint _primaryEndpoint({
    required AppSettings settings,
    required String model,
    bool demoted = false,
  }) => ResolvedEndpoint(
    endpointId: '',
    baseUrl: settings.baseUrl.trim(),
    apiKey: settings.apiKey,
    model: model,
    isPrimary: true,
    demotedToPrimary: demoted,
  );
}
