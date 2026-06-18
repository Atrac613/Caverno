import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lan_scan_service.dart' show LanIpNetwork;

/// An OpenAI-compatible inference endpoint discovered on the LAN.
class DiscoveredEndpoint {
  const DiscoveredEndpoint({
    required this.host,
    required this.port,
    required this.modelIds,
    required this.responseMs,
    required this.serverHint,
  });

  final String host;
  final int port;

  /// Model ids advertised by `GET /v1/models`, in response order.
  final List<String> modelIds;

  /// Round-trip time of the verifying probe, in milliseconds.
  final double responseMs;

  /// A best-effort server-kind hint derived from the port (advisory only).
  final String serverHint;

  /// OpenAI-style base URL ready to drop into settings, e.g.
  /// `http://192.168.100.241:1234/v1`. IPv6 hosts are bracketed.
  String get baseUrl => 'http://${_hostForUrl(host)}:$port/v1';

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'base_url': baseUrl,
    'server_hint': serverHint,
    'response_time_ms': responseMs,
    'model_ids': modelIds,
  };

  static String _hostForUrl(String host) {
    final stripped = LanIpNetwork.stripScopeId(host);
    return LanIpNetwork.looksLikeIpv6(stripped) ? '[$stripped]' : stripped;
  }
}

/// LL8 LAN inference mesh discovery.
///
/// Probes candidate `host:port` pairs for an OpenAI-compatible API by issuing an
/// unauthenticated `GET /v1/models`. Credentials are never sent to unverified
/// hosts (acceptance criterion); registration of any discovered endpoint stays
/// an explicit, user-confirmed step handled by later slices.
class LanEndpointDiscovery {
  LanEndpointDiscovery({
    http.Client? client,
    Duration timeout = const Duration(seconds: 2),
  }) : _client = client ?? http.Client(),
       _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  /// Default ports for local OpenAI-compatible servers, with advisory labels.
  static const Map<int, String> knownPorts = {
    1234: 'LM Studio',
    11434: 'Ollama',
    8080: 'llama.cpp',
    8000: 'OpenAI-compatible',
    5000: 'OpenAI-compatible',
  };

  /// Probe many [hosts] across [ports] (defaults to [knownPorts]) and return the
  /// endpoints that answered, sorted fastest-first. Probes run concurrently in
  /// bounded batches to avoid socket exhaustion.
  Future<List<DiscoveredEndpoint>> discover({
    required List<String> hosts,
    List<int>? ports,
    int concurrency = 24,
  }) async {
    final effectivePorts = (ports == null || ports.isEmpty)
        ? knownPorts.keys.toList(growable: false)
        : ports;
    final targets = <(String, int)>[
      for (final host in hosts)
        for (final port in effectivePorts) (host, port),
    ];

    final found = <DiscoveredEndpoint>[];
    final batchSize = concurrency < 1 ? 1 : concurrency;
    for (var index = 0; index < targets.length; index += batchSize) {
      final batch = targets.sublist(
        index,
        (index + batchSize).clamp(0, targets.length),
      );
      final results = await Future.wait(
        batch.map((target) => probe(host: target.$1, port: target.$2)),
      );
      for (final endpoint in results) {
        if (endpoint != null) found.add(endpoint);
      }
    }

    found.sort((a, b) => a.responseMs.compareTo(b.responseMs));
    return found;
  }

  /// Probe a single `host:port` for an OpenAI-compatible API. Returns null on any
  /// failure (unreachable, non-2xx, malformed body, no models) so callers can
  /// simply skip it.
  Future<DiscoveredEndpoint?> probe({
    required String host,
    required int port,
  }) async {
    final uri = _modelsUri(host, port);
    if (uri == null) return null;

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
      stopwatch.stop();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final modelIds = _parseModelIds(response.body);
      if (modelIds == null) return null;
      return DiscoveredEndpoint(
        host: host,
        port: port,
        modelIds: modelIds,
        responseMs: double.parse(
          (stopwatch.elapsedMicroseconds / 1000.0).toStringAsFixed(2),
        ),
        serverHint: knownPorts[port] ?? 'OpenAI-compatible',
      );
    } on Object {
      return null;
    }
  }

  void close() => _client.close();

  static Uri? _modelsUri(String host, int port) {
    if (port <= 0 || port > 65535) return null;
    final stripped = LanIpNetwork.stripScopeId(host).trim();
    if (stripped.isEmpty) return null;
    return Uri(scheme: 'http', host: stripped, port: port, path: '/v1/models');
  }

  /// Parse the `data[].id` list from a `/v1/models` body. Returns null when the
  /// body is not a recognizable OpenAI-compatible model listing, and an empty
  /// list when the server answered correctly but advertises no models.
  static List<String>? _parseModelIds(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final data = decoded['data'];
    if (data is! List) return null;
    final ids = <String>[];
    for (final entry in data) {
      if (entry is Map && entry['id'] is String) {
        ids.add(entry['id'] as String);
      }
    }
    return ids;
  }
}
