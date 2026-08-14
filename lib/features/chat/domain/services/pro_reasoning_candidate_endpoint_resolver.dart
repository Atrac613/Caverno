import 'dart:io';

import '../../../settings/domain/entities/app_settings.dart';
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

  bool _isLocalEndpoint(LlmEndpoint endpoint) {
    if (endpoint.source == LlmEndpointSource.discovered) return true;
    final uri = Uri.tryParse(endpoint.normalizedBaseUrl);
    final host = uri?.host.trim().toLowerCase() ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return true;
    }

    final address = InternetAddress.tryParse(host);
    if (address != null) return _isLocalAddress(address);

    // A single-label hostname is resolved by the local DNS/search domain.
    return !host.contains('.');
  }

  bool _isLocalAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return _isPrivateIpv4(bytes);
    }
    if ((bytes[0] & 0xfe) == 0xfc) return true;
    final isIpv4Mapped =
        bytes.length == 16 &&
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    return isIpv4Mapped && _isPrivateIpv4(bytes.sublist(12));
  }

  bool _isPrivateIpv4(List<int> bytes) =>
      bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168);

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
