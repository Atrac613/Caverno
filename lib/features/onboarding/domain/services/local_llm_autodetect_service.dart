import '../../../../core/services/lan_endpoint_discovery.dart';

/// First-run detection of a local LLM server.
///
/// [LanEndpointDiscovery.discover] needs an explicit host list, and the only
/// producer of one today is a full LAN sweep — seconds of traffic before the
/// wizard can say anything. Loopback is the overwhelmingly common case (LM
/// Studio, Ollama and llama.cpp all bind localhost by default) and costs a
/// handful of parallel connects, so onboarding tries it first and keeps the LAN
/// sweep as an explicit, user-triggered fallback.
class LocalLlmAutodetectService {
  const LocalLlmAutodetectService(this._discovery);

  final LanEndpointDiscovery _discovery;

  /// Loopback hosts to probe. IPv4 only: a server bound to `::1` alone would be
  /// missed, but probing both doubles the connect count to surface a case that
  /// does not occur with the servers in [LanEndpointDiscovery.knownPorts].
  static const List<String> loopbackHosts = ['127.0.0.1'];

  /// Probe this machine for an OpenAI-compatible server on any known port.
  ///
  /// Returns the endpoints that answered `GET /v1/models`, fastest first. Never
  /// throws: "nothing is running here" is the expected answer on a fresh
  /// install, not an error.
  Future<List<DiscoveredEndpoint>> probeLoopback() async {
    try {
      return await _discovery.discover(hosts: loopbackHosts);
    } on Object {
      return const <DiscoveredEndpoint>[];
    }
  }
}
