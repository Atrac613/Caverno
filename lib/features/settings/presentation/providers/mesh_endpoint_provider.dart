import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lan_endpoint_discovery.dart';
import '../../../../core/services/lan_scan_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/services/mesh_endpoint_router.dart';

/// LL8 discovery probe over the LAN. Closed on dispose.
final lanEndpointDiscoveryProvider = Provider<LanEndpointDiscovery>((ref) {
  final discovery = LanEndpointDiscovery();
  ref.onDispose(discovery.close);
  return discovery;
});

/// LL8 endpoint health tracker, shared across the app so demotion decisions
/// persist across turns. Kept alive for the app session.
final endpointHealthTrackerProvider = Provider<EndpointHealthTracker>((ref) {
  return EndpointHealthTracker();
});

/// LL8 pure role -> endpoint resolver.
final meshEndpointRouterProvider = Provider<MeshEndpointRouter>((ref) {
  return const MeshEndpointRouter();
});

/// Enumerates candidate LAN hosts to probe for inference endpoints. Defaults to
/// a LAN ping/port sweep on the known local-LLM ports; overridable in tests.
typedef MeshHostEnumerator = Future<List<String>> Function();

final meshHostEnumeratorProvider = Provider<MeshHostEnumerator>((ref) {
  final scan = ref.watch(lanScanServiceProvider);
  return () async {
    final json = await scan.startScan(
      ports: LanEndpointDiscovery.knownPorts.keys.toList(),
    );
    return meshHostsFromScanJson(json);
  };
});

/// Extract host IP strings from a [LanScanService.startScan] JSON payload.
/// Returns an empty list on an error payload or any parse failure.
List<String> meshHostsFromScanJson(String scanJson) {
  try {
    final decoded = jsonDecode(scanJson);
    if (decoded is! Map || decoded['error'] == true) return const [];
    final hosts = decoded['hosts'];
    if (hosts is! List) return const [];
    return [
      for (final host in hosts)
        if (host is Map && host['ip'] is String) host['ip'] as String,
    ];
  } on FormatException {
    return const [];
  }
}

/// LL8 discovery notifier: runs a LAN scan, verifies OpenAI-compatible endpoints,
/// and exposes the result for the settings UI. Starts empty; [scan] populates it.
class MeshDiscoveryNotifier
    extends Notifier<AsyncValue<List<DiscoveredEndpoint>>> {
  @override
  AsyncValue<List<DiscoveredEndpoint>> build() =>
      const AsyncValue.data(<DiscoveredEndpoint>[]);

  /// Sweep the LAN and verify which hosts expose an OpenAI-compatible API.
  Future<void> scan() async {
    state = const AsyncValue.loading();
    try {
      final hosts = await ref.read(meshHostEnumeratorProvider)();
      if (hosts.isEmpty) {
        state = const AsyncValue.data(<DiscoveredEndpoint>[]);
        return;
      }
      final discovery = ref.read(lanEndpointDiscoveryProvider);
      final endpoints = await discovery.discover(hosts: hosts);
      state = AsyncValue.data(endpoints);
    } catch (error, stackTrace) {
      appLog('[LL8] endpoint discovery failed: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Clear discovery results (e.g. after registering the desired endpoints).
  void clear() => state = const AsyncValue.data(<DiscoveredEndpoint>[]);
}

final meshDiscoveryProvider =
    NotifierProvider<
      MeshDiscoveryNotifier,
      AsyncValue<List<DiscoveredEndpoint>>
    >(MeshDiscoveryNotifier.new);
