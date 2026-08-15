import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/local_llm_endpoint_predicate.dart';
import 'pro_reasoning_candidate_explorer.dart';

/// Resolves the stage-three candidate pool from the Pro Reasoning route.
///
/// The selected role endpoint is always the anchor and receives the role model
/// override. Mesh peers keep their own configured models so a hosted model name
/// is never sent to an unrelated local endpoint.
final class ProReasoningCandidateEndpointResolver {
  const ProReasoningCandidateEndpointResolver();

  List<ProReasoningEndpointTarget> resolve({
    required AppSettings settings,
    required ProReasoningCandidateRouting routing,
  }) {
    final enabled = settings.enabledLlmEndpoints;
    final primary = settings.activeLlmEndpoint ?? _legacyPrimary(settings);
    final selected = _selectedEndpoint(settings, enabled) ?? primary;
    final targets = <ProReasoningEndpointTarget>[];
    final seenBaseUrls = <String>{};

    void add(LlmEndpoint endpoint, {required bool isAnchor}) {
      final baseUrl = endpoint.normalizedBaseUrl;
      if (baseUrl.isEmpty || !seenBaseUrls.add(baseUrl.toLowerCase())) return;
      final model = isAnchor
          ? settings.effectiveProReasoningModel
          : endpoint.normalizedModel.isEmpty
          ? settings.effectiveModel
          : endpoint.normalizedModel;
      targets.add(
        ProReasoningEndpointTarget(
          endpointId: endpoint.normalizedId,
          label: endpoint.displayLabel,
          baseUrl: baseUrl,
          apiKey: endpoint.apiKey,
          model: model,
        ),
      );
    }

    final localOnly = routing == ProReasoningCandidateRouting.localOnly;
    if (!localOnly || _isLocalEndpoint(selected)) {
      add(selected, isAnchor: true);
    }
    if (routing == ProReasoningCandidateRouting.selectedOnly) {
      return List.unmodifiable(targets);
    }

    if (!localOnly || _isLocalEndpoint(primary)) {
      add(primary, isAnchor: false);
    }
    for (final endpoint in enabled) {
      if (localOnly && !_isLocalEndpoint(endpoint)) continue;
      add(endpoint, isAnchor: false);
    }
    return List.unmodifiable(targets);
  }

  bool _isLocalEndpoint(LlmEndpoint endpoint) =>
      const LocalLlmEndpointPredicate().isLocal(
        endpoint.normalizedBaseUrl,
        discovered: endpoint.source == LlmEndpointSource.discovered,
      );

  LlmEndpoint? _selectedEndpoint(
    AppSettings settings,
    List<LlmEndpoint> enabled,
  ) {
    final selectedId = settings.proReasoningEndpointId.trim();
    if (selectedId.isEmpty) return settings.activeLlmEndpoint;
    for (final endpoint in enabled) {
      if (endpoint.normalizedId == selectedId) return endpoint;
    }
    return null;
  }

  LlmEndpoint _legacyPrimary(AppSettings settings) => LlmEndpoint(
    id: AppSettings.seededLlmEndpointId,
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
    model: settings.model,
  );
}
