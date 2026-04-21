import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ping/dart_ping.dart';
import 'package:multicast_dns/multicast_dns.dart';

typedef NetworkProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef NetworkAddressLookup =
    Future<List<InternetAddress>> Function(
      String host, {
      InternetAddressType type,
    });
typedef NetworkPingRunner =
    Future<String> Function({
      required String requestedHost,
      required String pingTarget,
      required int count,
      required int timeoutSeconds,
      String? resolvedIp,
      String? requestedIpVersion,
    });
typedef NetworkReverseLookup =
    Future<InternetAddress> Function(InternetAddress address);
typedef NetworkMdnsBrowseRunner =
    Future<Map<String, dynamic>> Function({
      required String serviceType,
      required int timeoutMs,
      required int maxResults,
      required String ipVersion,
    });

/// Network diagnostic utilities for built-in MCP tools.
///
/// All methods run locally without external API dependencies.
class NetworkTools {
  static const Set<String> _supportedArpVersions = {'all', 'ipv4', 'ipv6'};
  static const Set<String> _supportedRouteVersions = {'auto', 'ipv4', 'ipv6'};
  static const Set<String> _supportedDnsRecordTypes = {
    'A',
    'AAAA',
    'PTR',
    'CNAME',
  };
  static const String _mdnsServiceCatalog = '_services._dns-sd._udp.local';

  // ---------------------------------------------------------------------------
  // DNS Lookup
  // ---------------------------------------------------------------------------

  /// Resolves [host] to IP addresses and returns a JSON-formatted result.
  static Future<String> dnsLookup({required String host}) async {
    final results = await InternetAddress.lookup(host);
    if (results.isEmpty) {
      return jsonEncode({'host': host, 'error': 'No records found'});
    }

    final records = results
        .map(
          (r) => {
            'address': r.address,
            'type': r.type == InternetAddressType.IPv4 ? 'A' : 'AAAA',
            'host': r.host,
          },
        )
        .toList();

    return jsonEncode({'host': host, 'records': records});
  }

  // ---------------------------------------------------------------------------
  // Route Lookup
  // ---------------------------------------------------------------------------

  /// Shows which route, interface, gateway, and source IP would be selected
  /// for a destination from the current machine.
  static Future<String> routeLookup({
    required String host,
    String ipVersion = 'auto',
    NetworkProcessRunner? processRunner,
    NetworkAddressLookup? addressLookup,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedRouteVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedRouteVersions.join(', ')}',
      });
    }

    if (!Platform.isMacOS && !Platform.isLinux) {
      return jsonEncode({
        'error': true,
        'message': 'Route inspection is only supported on macOS and Linux.',
      });
    }

    final targets = await _resolveRouteTargets(
      host,
      requestedVersion: normalizedVersion,
      addressLookup: addressLookup,
    );

    final routes = <_RouteLookupEntry>[];
    for (final target in targets) {
      final entry = Platform.isMacOS
          ? await _lookupMacOsRoute(target, processRunner: processRunner)
          : await _lookupLinuxRoute(target, processRunner: processRunner);
      if (entry != null) {
        routes.add(entry);
      }
    }

    return jsonEncode({
      'host': host,
      'ip_version': normalizedVersion,
      'routes_found': routes.length,
      'routes': routes.map((entry) => entry.toJson()).toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // Interface Info
  // ---------------------------------------------------------------------------

  /// Returns local interface addresses, MTU, flags, and default gateways.
  static Future<String> interfaceInfo({
    String? interfaceName,
    String ipVersion = 'all',
    NetworkProcessRunner? processRunner,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedArpVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedArpVersions.join(', ')}',
      });
    }

    final requestedInterface = interfaceName?.trim();
    final interfaces = await _loadInterfaceInfoEntries(
      processRunner: processRunner,
    );
    final filtered = interfaces
        .where(
          (entry) =>
              requestedInterface == null ||
              requestedInterface.isEmpty ||
              entry.name == requestedInterface,
        )
        .map((entry) => entry.filtered(ipVersion: normalizedVersion))
        .where(
          (entry) =>
              normalizedVersion == 'all' ||
              entry.addresses.isNotEmpty ||
              entry.defaultGateways.isNotEmpty,
        )
        .toList(growable: false);

    return jsonEncode({
      'interface': requestedInterface,
      'ip_version': normalizedVersion,
      'interfaces_found': filtered.length,
      'interfaces': filtered.map((entry) => entry.toJson()).toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // DNS Query
  // ---------------------------------------------------------------------------

  /// Resolves a specific DNS record type for [target].
  static Future<String> dnsQuery({
    required String target,
    String recordType = 'A',
    NetworkAddressLookup? addressLookup,
    NetworkReverseLookup? reverseLookup,
    NetworkProcessRunner? processRunner,
  }) async {
    final normalizedType = recordType.trim().toUpperCase();
    if (!_supportedDnsRecordTypes.contains(normalizedType)) {
      return jsonEncode({
        'error': true,
        'message':
            'record_type must be one of: ${_supportedDnsRecordTypes.join(', ')}',
      });
    }

    final records = <Map<String, dynamic>>[];
    switch (normalizedType) {
      case 'A':
      case 'AAAA':
        final lookup = addressLookup ?? InternetAddress.lookup;
        final type = normalizedType == 'A'
            ? InternetAddressType.IPv4
            : InternetAddressType.IPv6;
        final addresses = await lookup(target, type: type);
        final seen = <String>{};
        for (final address in addresses) {
          if (seen.add(address.address)) {
            records.add({
              'type': normalizedType,
              'value': address.address,
              'host': address.host,
            });
          }
        }
        break;
      case 'PTR':
        final literal = InternetAddress.tryParse(
          _normalizeIpForComparison(target),
        );
        if (literal == null) {
          return jsonEncode({
            'error': true,
            'message': 'PTR queries require an IPv4 or IPv6 literal address.',
          });
        }
        final reverse = reverseLookup ?? ((address) => address.reverse());
        final resolved = await reverse(literal);
        records.add({
          'type': normalizedType,
          'value': resolved.host,
          'address': literal.address,
        });
        break;
      case 'CNAME':
        final result = await _runProcess('nslookup', [
          '-type=cname',
          target,
        ], processRunner: processRunner);
        if (result.exitCode == 0) {
          final matches = RegExp(
            r'canonical name\s*=\s*(\S+)',
            caseSensitive: false,
          ).allMatches(result.stdout as String);
          final seen = <String>{};
          for (final match in matches) {
            final value = match.group(1);
            if (value != null && seen.add(value)) {
              records.add({'type': normalizedType, 'value': value});
            }
          }
        }
        break;
    }

    return jsonEncode({
      'target': target,
      'record_type': normalizedType,
      'records_found': records.length,
      'records': records,
    });
  }

  // ---------------------------------------------------------------------------
  // Path MTU
  // ---------------------------------------------------------------------------

  /// Attempts to discover the current path MTU for [host].
  static Future<String> pathMtu({
    required String host,
    String ipVersion = 'auto',
    NetworkProcessRunner? processRunner,
    NetworkAddressLookup? addressLookup,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedRouteVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedRouteVersions.join(', ')}',
      });
    }

    if (!Platform.isMacOS && !Platform.isLinux) {
      return jsonEncode({
        'error': true,
        'message': 'Path MTU discovery is only supported on macOS and Linux.',
      });
    }

    final targets = await _resolveRouteTargets(
      host,
      requestedVersion: normalizedVersion,
      addressLookup: addressLookup,
    );
    final measurements = <_PathMtuMeasurement>[];
    final interfaces = await _loadInterfaceInfoEntries(
      processRunner: processRunner,
    );

    for (final target in targets) {
      final route = Platform.isMacOS
          ? await _lookupMacOsRoute(target, processRunner: processRunner)
          : await _lookupLinuxRoute(target, processRunner: processRunner);
      final measurement = Platform.isLinux
          ? await _runLinuxTracepath(
              target,
              route: route,
              interfaces: interfaces,
              processRunner: processRunner,
            )
          : _buildInterfaceMtuFallbackMeasurement(
              target,
              route: route,
              interfaces: interfaces,
              note:
                  'macOS fallback returns the egress interface MTU as a local '
                  'upper bound when tracepath is unavailable.',
            );
      if (measurement != null) {
        measurements.add(measurement);
      }
    }

    return jsonEncode({
      'host': host,
      'ip_version': normalizedVersion,
      'measurements_found': measurements.length,
      'measurements': measurements.map((entry) => entry.toJson()).toList(),
    });
  }

  // ---------------------------------------------------------------------------
  // mDNS Browse
  // ---------------------------------------------------------------------------

  /// Browses the local multicast DNS service catalog or a specific service.
  static Future<String> mdnsBrowse({
    String serviceType = _mdnsServiceCatalog,
    String ipVersion = 'all',
    int timeoutMs = 2000,
    int maxResults = 50,
    NetworkMdnsBrowseRunner? browseRunner,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedArpVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedArpVersions.join(', ')}',
      });
    }

    final normalizedServiceType = _normalizeMdnsServiceType(serviceType);
    final effectiveTimeoutMs = timeoutMs.clamp(200, 10000).toInt();
    final effectiveMaxResults = maxResults.clamp(1, 100).toInt();

    final payload = browseRunner != null
        ? await browseRunner(
            serviceType: normalizedServiceType,
            timeoutMs: effectiveTimeoutMs,
            maxResults: effectiveMaxResults,
            ipVersion: normalizedVersion,
          )
        : await _browseMdnsPayload(
            serviceType: normalizedServiceType,
            timeoutMs: effectiveTimeoutMs,
            maxResults: effectiveMaxResults,
            ipVersion: normalizedVersion,
          );

    return jsonEncode(payload);
  }

  // ---------------------------------------------------------------------------
  // ARP / NDP Cache Inspection
  // ---------------------------------------------------------------------------

  /// Reads the local ARP/NDP neighbor cache and returns recently observed
  /// IP-to-MAC mappings from the current machine.
  static Future<String> arp({
    String? host,
    String ipVersion = 'all',
    NetworkProcessRunner? processRunner,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedArpVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedArpVersions.join(', ')}',
      });
    }

    if (!Platform.isMacOS && !Platform.isLinux) {
      return jsonEncode({
        'error': true,
        'message':
            'ARP inspection is only supported on macOS and Linux. '
            'This platform does not expose a compatible local neighbor table.',
      });
    }

    final requestedHost = host?.trim();
    final requestedVersion = normalizedVersion;
    final entries = <_NeighborCacheEntry>[];

    if (requestedVersion != 'ipv6') {
      entries.addAll(
        Platform.isMacOS
            ? await _readMacOsArpTable(processRunner: processRunner)
            : await _readLinuxNeighborTable(
                ipv6: false,
                processRunner: processRunner,
              ),
      );
    }

    if (requestedVersion != 'ipv4') {
      entries.addAll(
        Platform.isMacOS
            ? await _readMacOsNdpTable(processRunner: processRunner)
            : await _readLinuxNeighborTable(
                ipv6: true,
                processRunner: processRunner,
              ),
      );
    }

    final matchedEntries = requestedHost == null || requestedHost.isEmpty
        ? entries
        : entries.where(
            (entry) => _matchesNeighborFilter(entry, requestedHost),
          );
    final filteredEntries = matchedEntries.toList(growable: false)
      ..sort((a, b) => _compareIpAddresses(a.ip, b.ip));

    return jsonEncode({
      'host': requestedHost,
      'ip_version': requestedVersion,
      'entries_found': filteredEntries.length,
      'entries': filteredEntries.map((entry) => entry.toJson()).toList(),
    });
  }

  /// Reads only IPv6 NDP neighbor cache entries from the local machine.
  static Future<String> ndp({
    String? host,
    NetworkProcessRunner? processRunner,
  }) {
    return arp(host: host, ipVersion: 'ipv6', processRunner: processRunner);
  }

  // ---------------------------------------------------------------------------
  // Port Check
  // ---------------------------------------------------------------------------

  /// Tests whether a TCP [port] is open on [host].
  static Future<String> portCheck({
    required String host,
    required int port,
    int timeoutSeconds = 5,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(seconds: timeoutSeconds),
      );
      stopwatch.stop();
      socket.destroy();
      return jsonEncode({
        'host': host,
        'port': port,
        'open': true,
        'response_time_ms': stopwatch.elapsedMilliseconds,
      });
    } on SocketException catch (e) {
      stopwatch.stop();
      return jsonEncode({
        'host': host,
        'port': port,
        'open': false,
        'error': e.message,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // SSL Certificate
  // ---------------------------------------------------------------------------

  /// Retrieves TLS/SSL certificate information for [host].
  static Future<String> sslCertificate({
    required String host,
    int port = 443,
    int timeoutSeconds = 10,
  }) async {
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: Duration(seconds: timeoutSeconds),
      onBadCertificate: (_) => true, // Accept to still inspect the cert.
    );

    final cert = socket.peerCertificate;
    socket.destroy();

    if (cert == null) {
      return jsonEncode({'host': host, 'error': 'No certificate returned'});
    }

    return jsonEncode({
      'host': host,
      'port': port,
      'subject': cert.subject,
      'issuer': cert.issuer,
      'valid_from': cert.startValidity.toIso8601String(),
      'valid_until': cert.endValidity.toIso8601String(),
      'is_valid_now':
          DateTime.now().isAfter(cert.startValidity) &&
          DateTime.now().isBefore(cert.endValidity),
      'sha1_fingerprint': cert.sha1,
    });
  }

  // ---------------------------------------------------------------------------
  // HTTP Status
  // ---------------------------------------------------------------------------

  /// Checks URL reachability and returns status code, headers, and timing.
  static Future<String> httpStatus({
    required String url,
    int timeoutSeconds = 10,
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = Duration(seconds: timeoutSeconds);

    try {
      final stopwatch = Stopwatch()..start();
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        Duration(seconds: timeoutSeconds),
      );
      stopwatch.stop();

      // Read a small portion of the body to confirm it's reachable.
      await response.drain<void>();

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });

      return jsonEncode({
        'url': url,
        'status_code': response.statusCode,
        'reason_phrase': response.reasonPhrase,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'headers': headers,
        'redirects': response.redirects
            .map(
              (r) => {
                'status': r.statusCode,
                'location': r.location.toString(),
              },
            )
            .toList(),
      });
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP Methods (GET / HEAD / DELETE / POST / PUT / PATCH)
  // ---------------------------------------------------------------------------

  /// Maximum response body characters returned to the LLM.
  static const int _kHttpBodyMaxChars = 4000;

  /// Performs an HTTP GET request and returns the decoded body alongside
  /// status, headers, and timing information as a JSON-encoded string.
  static Future<String> httpGet({
    required String url,
    Map<String, String>? headers,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpRequest(
      method: 'GET',
      url: url,
      headers: headers,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  /// Performs an HTTP HEAD request. The response body is drained and not
  /// returned, mirroring the behaviour of [httpStatus] but exposing the
  /// HEAD verb explicitly.
  static Future<String> httpHead({
    required String url,
    Map<String, String>? headers,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpRequest(
      method: 'HEAD',
      url: url,
      headers: headers,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: false,
    );
  }

  /// Performs an HTTP DELETE request. A request body is permitted by the
  /// HTTP spec and forwarded if [body] is non-null.
  static Future<String> httpDelete({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpRequest(
      method: 'DELETE',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  /// Performs an HTTP POST request with [body] as the raw payload.
  static Future<String> httpPost({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpRequest(
      method: 'POST',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  /// Performs an HTTP PUT request with [body] as the raw payload.
  static Future<String> httpPut({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpRequest(
      method: 'PUT',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  /// Performs an HTTP PATCH request with [body] as the raw payload.
  static Future<String> httpPatch({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpRequest(
      method: 'PATCH',
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      includeBody: true,
    );
  }

  /// Shared implementation for all method-specific HTTP wrappers.
  ///
  /// Returns a JSON-encoded payload describing status, headers, redirect
  /// chain, timing, and (when [includeBody] is true) the response body.
  /// Bodies are decoded as UTF-8 when possible and otherwise base64-encoded;
  /// in either case the returned string is truncated to
  /// [_kHttpBodyMaxChars] characters with a `body_truncated` flag set.
  static Future<String> _httpRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
    required bool includeBody,
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = Duration(seconds: timeoutSeconds);

    try {
      final stopwatch = Stopwatch()..start();
      final request = await client.openUrl(method, uri);
      request.followRedirects = followRedirects;
      request.maxRedirects = maxRedirects;

      // Track which header names were explicitly provided so the
      // content_type convenience parameter does not clobber them.
      final providedHeaderNames = <String>{};
      if (headers != null) {
        headers.forEach((name, value) {
          providedHeaderNames.add(name.toLowerCase());
          request.headers.set(name, value);
        });
      }

      final hasBody = body != null && body.isNotEmpty;
      if (hasBody) {
        if (!providedHeaderNames.contains('content-type')) {
          request.headers.contentType = ContentType.parse(
            contentType ?? 'application/json',
          );
        }
        final encodedBody = utf8.encode(body);
        request.contentLength = encodedBody.length;
        request.add(encodedBody);
      }

      final response = await request.close().timeout(
        Duration(seconds: timeoutSeconds),
      );
      stopwatch.stop();

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      final payload = <String, dynamic>{
        'url': url,
        'method': method,
        'status_code': response.statusCode,
        'reason_phrase': response.reasonPhrase,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'headers': responseHeaders,
        'redirects': response.redirects
            .map(
              (r) => {
                'status': r.statusCode,
                'location': r.location.toString(),
              },
            )
            .toList(),
        'content_type': response.headers.contentType?.toString(),
      };

      if (!includeBody) {
        await response.drain<void>();
        return jsonEncode(payload);
      }

      // Collect the raw bytes so we can fall back to base64 for
      // non-textual responses without losing the data entirely.
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      payload['body_bytes'] = bytes.length;

      String bodyText;
      String encoding;
      try {
        bodyText = utf8.decode(bytes);
        encoding = 'utf-8';
      } on FormatException {
        bodyText = base64Encode(bytes);
        encoding = 'base64';
      }

      final truncated = bodyText.length > _kHttpBodyMaxChars;
      payload['body'] = truncated
          ? bodyText.substring(0, _kHttpBodyMaxChars)
          : bodyText;
      payload['body_truncated'] = truncated;
      payload['body_encoding'] = encoding;

      return jsonEncode(payload);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Traceroute
  // ---------------------------------------------------------------------------

  /// Traces the network path to [host] by incrementing TTL.
  static Future<String> traceroute({
    required String host,
    int maxHops = 20,
    int timeoutSeconds = 3,
  }) async {
    final hops = <Map<String, dynamic>>[];

    for (var ttl = 1; ttl <= maxHops; ttl++) {
      final ping = Ping(host, count: 1, timeout: timeoutSeconds, ttl: ttl);
      PingData? data;
      await for (final event in ping.stream) {
        if (event.response != null || event.error != null) {
          data = event;
          break;
        }
      }

      if (data == null) {
        hops.add({'hop': ttl, 'status': 'timeout'});
        continue;
      }

      if (data.error != null) {
        // TTL exceeded responses often come back as errors with the
        // intermediate router IP embedded in the message.
        hops.add({
          'hop': ttl,
          'status': 'ttl_exceeded',
          'message': data.error!.message,
        });
        continue;
      }

      final resp = data.response!;
      final ms = resp.time?.inMicroseconds != null
          ? (resp.time!.inMicroseconds / 1000.0)
          : null;
      hops.add({
        'hop': ttl,
        'ip': resp.ip?.toString(),
        if (ms != null) 'time_ms': double.parse(ms.toStringAsFixed(2)),
        'ttl': resp.ttl,
      });

      // Reached the destination.
      if (resp.ip?.toString() != null) {
        try {
          final resolved = await InternetAddress.lookup(host);
          if (resolved.any((r) => r.address == resp.ip.toString())) {
            break;
          }
        } catch (_) {
          // Ignore resolution failures; continue tracing.
        }
      }
    }

    return jsonEncode({'host': host, 'max_hops': maxHops, 'hops': hops});
  }

  // ---------------------------------------------------------------------------
  // Ping
  // ---------------------------------------------------------------------------
  /// Pings a [host] and returns a JSON-formatted result string.
  static Future<String> ping({
    required String host,
    int count = 4,
    int timeoutSeconds = 5,
    NetworkPingRunner? pingRunner,
  }) {
    return _runPing(
      requestedHost: host,
      pingTarget: host,
      count: count,
      timeoutSeconds: timeoutSeconds,
      pingRunner: pingRunner,
    );
  }

  /// Resolves [host] to IPv6 and pings the resulting IPv6 address.
  static Future<String> ping6({
    required String host,
    int count = 4,
    int timeoutSeconds = 5,
    NetworkAddressLookup? addressLookup,
    NetworkPingRunner? pingRunner,
  }) async {
    final ipv6Target = await _resolveIpv6Target(
      host,
      addressLookup: addressLookup,
    );
    return _runPing(
      requestedHost: host,
      pingTarget: ipv6Target.pingTarget,
      count: count,
      timeoutSeconds: timeoutSeconds,
      resolvedIp: ipv6Target.resolvedIp,
      requestedIpVersion: 'ipv6',
      pingRunner: pingRunner,
    );
  }

  static Future<String> _runPing({
    required String requestedHost,
    required String pingTarget,
    required int count,
    required int timeoutSeconds,
    String? resolvedIp,
    String? requestedIpVersion,
    NetworkPingRunner? pingRunner,
  }) async {
    final runner = pingRunner;
    if (runner != null) {
      return runner(
        requestedHost: requestedHost,
        pingTarget: pingTarget,
        count: count,
        timeoutSeconds: timeoutSeconds,
        resolvedIp: resolvedIp,
        requestedIpVersion: requestedIpVersion,
      );
    }

    final ping = Ping(pingTarget, count: count, timeout: timeoutSeconds);

    final results = <Map<String, dynamic>>[];
    var effectiveResolvedIp = resolvedIp;
    int transmitted = 0;
    int received = 0;
    final times = <double>[];

    await for (final event in ping.stream) {
      if (event.response != null) {
        final response = event.response!;
        effectiveResolvedIp ??= response.ip?.toString();
        transmitted++;
        if (response.time != null) {
          received++;
          final ms = response.time!.inMicroseconds / 1000.0;
          times.add(ms);
          results.add({
            'seq': response.seq,
            'ttl': response.ttl,
            'time_ms': double.parse(ms.toStringAsFixed(2)),
          });
        } else {
          results.add({'seq': response.seq, 'status': 'timeout'});
        }
      } else if (event.error != null) {
        transmitted++;
        results.add({
          'seq': transmitted,
          'status': 'error',
          'message': event.error!.message,
        });
      } else if (event.summary != null) {
        // Use summary data if available.
        transmitted = event.summary!.transmitted;
        received = event.summary!.received;
      }
    }

    final lossPercent = transmitted > 0
        ? ((transmitted - received) / transmitted * 100).toStringAsFixed(1)
        : '0.0';

    final payload = <String, dynamic>{
      'host': requestedHost,
      ...?requestedIpVersion == null
          ? null
          : <String, dynamic>{'ip_version': requestedIpVersion},
      ...?effectiveResolvedIp == null
          ? null
          : <String, dynamic>{'resolved_ip': effectiveResolvedIp},
      'results': results,
      'summary': {
        'transmitted': transmitted,
        'received': received,
        'loss_percent': double.parse(lossPercent),
        if (times.isNotEmpty) ...{
          'min_ms': double.parse(
            times.reduce((a, b) => a < b ? a : b).toStringAsFixed(2),
          ),
          'avg_ms': double.parse(
            (times.reduce((a, b) => a + b) / times.length).toStringAsFixed(2),
          ),
          'max_ms': double.parse(
            times.reduce((a, b) => a > b ? a : b).toStringAsFixed(2),
          ),
        },
      },
    };

    return jsonEncode(payload);
  }

  static Future<({String pingTarget, String resolvedIp})> _resolveIpv6Target(
    String host, {
    NetworkAddressLookup? addressLookup,
  }) async {
    final literal = InternetAddress.tryParse(_normalizeIpForComparison(host));
    if (literal != null) {
      if (literal.type != InternetAddressType.IPv6) {
        throw SocketException('Host is not an IPv6 address');
      }
      return (pingTarget: host, resolvedIp: literal.address);
    }

    final lookup = addressLookup ?? InternetAddress.lookup;
    final addresses = await lookup(host, type: InternetAddressType.IPv6);
    if (addresses.isEmpty) {
      throw SocketException('No IPv6 address found for host "$host"');
    }

    return (
      pingTarget: addresses.first.address,
      resolvedIp: addresses.first.address,
    );
  }

  /// Performs a WHOIS lookup for [domain] via raw TCP socket.
  static Future<String> whoisLookup({required String domain}) async {
    final normalizedDomain = domain.trim().toLowerCase();

    final tld = _extractTld(normalizedDomain);
    final whoisServer = _whoisServerForTld(tld);

    final result = await _queryWhoisServer(
      server: whoisServer,
      query: normalizedDomain,
    );

    // Some registries (e.g., .com) include a "Registrar WHOIS Server" line
    // pointing to a more detailed server. Follow the referral if found.
    final referralMatch = RegExp(
      r'Registrar WHOIS Server:\s*(\S+)',
      caseSensitive: false,
    ).firstMatch(result);

    if (referralMatch != null) {
      final referralServer = referralMatch.group(1)!;
      if (referralServer != whoisServer) {
        try {
          final detailed = await _queryWhoisServer(
            server: referralServer,
            query: normalizedDomain,
          );
          if (detailed.trim().isNotEmpty) {
            return _truncate(detailed, 4000);
          }
        } catch (_) {
          // Fall through to initial result on referral failure.
        }
      }
    }

    return _truncate(result, 4000);
  }

  static String _extractTld(String domain) {
    final parts = domain.split('.');
    if (parts.length < 2) return domain;
    return parts.last;
  }

  static String _whoisServerForTld(String tld) {
    const servers = {
      'com': 'whois.verisign-grs.com',
      'net': 'whois.verisign-grs.com',
      'org': 'whois.pir.org',
      'io': 'whois.nic.io',
      'dev': 'whois.nic.google',
      'app': 'whois.nic.google',
      'jp': 'whois.jprs.jp',
      'uk': 'whois.nic.uk',
      'de': 'whois.denic.de',
      'fr': 'whois.nic.fr',
      'au': 'whois.auda.org.au',
      'ca': 'whois.cira.ca',
      'info': 'whois.afilias.net',
      'me': 'whois.nic.me',
      'co': 'whois.nic.co',
      'xyz': 'whois.nic.xyz',
    };
    return servers[tld] ?? 'whois.iana.org';
  }

  static Future<String> _queryWhoisServer({
    required String server,
    required String query,
  }) async {
    final socket = await Socket.connect(
      server,
      43,
      timeout: const Duration(seconds: 10),
    );

    socket.write('$query\r\n');
    await socket.flush();

    final response = StringBuffer();
    await for (final data in socket.timeout(const Duration(seconds: 10))) {
      response.write(String.fromCharCodes(data));
    }
    socket.destroy();

    return response.toString();
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}\n... (truncated)';
  }

  static Future<List<_NeighborCacheEntry>> _readMacOsArpTable({
    NetworkProcessRunner? processRunner,
  }) async {
    final result = await _runProcess('arp', [
      '-a',
    ], processRunner: processRunner);
    if (result.exitCode != 0) {
      return const [];
    }

    final entries = <_NeighborCacheEntry>[];
    final lines = (result.stdout as String).split('\n');
    final regex = RegExp(
      r'^(\S+)\s+\((\d+\.\d+\.\d+\.\d+)\)\s+at\s+([0-9a-fA-F:]+|\(incomplete\))(?:\s+on\s+(\S+))?',
    );

    for (final line in lines) {
      final match = regex.firstMatch(line.trim());
      if (match == null) {
        continue;
      }

      final hostname = match.group(1);
      final ip = match.group(2)!;
      final mac = match.group(3);
      if (mac == null || mac == '(incomplete)' || mac == 'ff:ff:ff:ff:ff:ff') {
        continue;
      }

      entries.add(
        _NeighborCacheEntry(
          ip: ip,
          ipVersion: 'ipv4',
          mac: mac.toLowerCase(),
          hostname: hostname == null || hostname == '?' ? null : hostname,
          interfaceName: match.group(4),
          source: 'arp',
        ),
      );
    }

    return entries;
  }

  static Future<List<_NeighborCacheEntry>> _readMacOsNdpTable({
    NetworkProcessRunner? processRunner,
  }) async {
    final result = await _runProcess('ndp', [
      '-an',
    ], processRunner: processRunner);
    if (result.exitCode != 0) {
      return const [];
    }

    final entries = <_NeighborCacheEntry>[];
    final lines = (result.stdout as String).split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Neighbor ')) {
        continue;
      }

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 3) {
        continue;
      }

      final ip = parts[0];
      final mac = parts[1];
      final interfaceName = parts[2];
      if (mac == '(incomplete)' || mac == 'ff:ff:ff:ff:ff:ff') {
        continue;
      }

      entries.add(
        _NeighborCacheEntry(
          ip: ip,
          ipVersion: 'ipv6',
          mac: mac.toLowerCase(),
          interfaceName: interfaceName,
          state: parts.length >= 5 ? parts.last : null,
          source: 'ndp',
        ),
      );
    }

    return entries;
  }

  static Future<List<_NeighborCacheEntry>> _readLinuxNeighborTable({
    required bool ipv6,
    NetworkProcessRunner? processRunner,
  }) async {
    final arguments = ipv6
        ? const ['-6', 'neighbor', 'show']
        : const ['neighbor', 'show'];
    final result = await _runProcess(
      'ip',
      arguments,
      processRunner: processRunner,
    );
    if (result.exitCode != 0) {
      return const [];
    }

    final entries = <_NeighborCacheEntry>[];
    final lines = (result.stdout as String).split('\n');
    final regex = RegExp(
      r'^([0-9a-fA-F:.%]+)\s+dev\s+(\S+)(?:\s+lladdr\s+([0-9a-fA-F:]+))?(?:\s+router)?(?:\s+(\S+))?$',
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.contains('FAILED') ||
          trimmed.contains('INCOMPLETE')) {
        continue;
      }

      final match = regex.firstMatch(trimmed);
      if (match == null) {
        continue;
      }

      final mac = match.group(3);
      if (mac == null || mac == 'ff:ff:ff:ff:ff:ff') {
        continue;
      }

      entries.add(
        _NeighborCacheEntry(
          ip: match.group(1)!,
          ipVersion: ipv6 ? 'ipv6' : 'ipv4',
          mac: mac.toLowerCase(),
          interfaceName: match.group(2),
          state: match.group(4),
          source: ipv6 ? 'ndp' : 'arp',
        ),
      );
    }

    return entries;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    NetworkProcessRunner? processRunner,
  }) {
    final runner = processRunner;
    return runner != null
        ? runner(executable, arguments)
        : Process.run(executable, arguments);
  }

  static bool _matchesNeighborFilter(
    _NeighborCacheEntry entry,
    String requestedHost,
  ) {
    final normalizedFilter = requestedHost.trim().toLowerCase();
    if (normalizedFilter.isEmpty) {
      return true;
    }

    final filterIp = _normalizeIpForComparison(normalizedFilter);
    if (_normalizeIpForComparison(entry.ip) == filterIp) {
      return true;
    }

    final hostname = entry.hostname?.toLowerCase();
    return hostname != null && hostname.contains(normalizedFilter);
  }

  static int _compareIpAddresses(String a, String b) {
    final aAddress = InternetAddress.tryParse(_normalizeIpForComparison(a));
    final bAddress = InternetAddress.tryParse(_normalizeIpForComparison(b));

    if (aAddress == null || bAddress == null) {
      return a.compareTo(b);
    }

    if (aAddress.type != bAddress.type) {
      return aAddress.type == InternetAddressType.IPv4 ? -1 : 1;
    }

    final aBytes = aAddress.rawAddress;
    final bBytes = bAddress.rawAddress;
    final maxLength = aBytes.length < bBytes.length
        ? aBytes.length
        : bBytes.length;

    for (var index = 0; index < maxLength; index += 1) {
      final diff = aBytes[index] - bBytes[index];
      if (diff != 0) {
        return diff;
      }
    }

    return a.compareTo(b);
  }

  static String _normalizeIpForComparison(String value) {
    final separatorIndex = value.indexOf('%');
    return separatorIndex >= 0 ? value.substring(0, separatorIndex) : value;
  }

  static Future<List<_ResolvedRouteTarget>> _resolveRouteTargets(
    String host, {
    required String requestedVersion,
    NetworkAddressLookup? addressLookup,
  }) async {
    final literal = InternetAddress.tryParse(_normalizeIpForComparison(host));
    if (literal != null) {
      final literalVersion = literal.type == InternetAddressType.IPv4
          ? 'ipv4'
          : 'ipv6';
      if (requestedVersion != 'auto' && literalVersion != requestedVersion) {
        return const [];
      }
      return [
        _ResolvedRouteTarget(
          requestedHost: host,
          commandTarget: host,
          resolvedIp: host,
          ipVersion: literalVersion,
        ),
      ];
    }

    final lookup = addressLookup ?? InternetAddress.lookup;
    final targets = <_ResolvedRouteTarget>[];
    final seenVersions = <String>{};

    Future<void> addLookupTargets(InternetAddressType type) async {
      final addresses = await lookup(host, type: type);
      for (final address in addresses) {
        final version = address.type == InternetAddressType.IPv4
            ? 'ipv4'
            : 'ipv6';
        if (requestedVersion == 'auto' && !seenVersions.add(version)) {
          continue;
        }
        targets.add(
          _ResolvedRouteTarget(
            requestedHost: host,
            commandTarget: address.address,
            resolvedIp: address.address,
            ipVersion: version,
          ),
        );
      }
    }

    if (requestedVersion == 'auto') {
      try {
        await addLookupTargets(InternetAddressType.IPv4);
      } on SocketException {
        // Continue so IPv6-only hosts can still return a usable route.
      }
      try {
        await addLookupTargets(InternetAddressType.IPv6);
      } on SocketException {
        // Continue so IPv4-only hosts can still return a usable route.
      }
    } else {
      await addLookupTargets(
        requestedVersion == 'ipv4'
            ? InternetAddressType.IPv4
            : InternetAddressType.IPv6,
      );
    }

    return targets;
  }

  static Future<_RouteLookupEntry?> _lookupMacOsRoute(
    _ResolvedRouteTarget target, {
    NetworkProcessRunner? processRunner,
  }) async {
    final arguments = target.ipVersion == 'ipv6'
        ? ['-n', 'get', '-inet6', target.commandTarget]
        : ['-n', 'get', target.commandTarget];
    final result = await _runProcess(
      'route',
      arguments,
      processRunner: processRunner,
    );
    if (result.exitCode != 0) {
      return null;
    }

    final fields = <String, String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        fields[key] = value;
      }
    }

    return _RouteLookupEntry(
      requestedHost: target.requestedHost,
      resolvedIp: target.resolvedIp,
      ipVersion: target.ipVersion,
      destination: fields['destination'] ?? fields['route to'],
      gateway: fields['gateway'],
      interfaceName: fields['interface'],
      sourceIp:
          fields['if address'] ?? fields['source address'] ?? fields['source'],
      flags: fields['flags'],
      rawOutput: (result.stdout as String).trim(),
    );
  }

  static Future<_RouteLookupEntry?> _lookupLinuxRoute(
    _ResolvedRouteTarget target, {
    NetworkProcessRunner? processRunner,
  }) async {
    final arguments = target.ipVersion == 'ipv6'
        ? ['-6', 'route', 'get', target.commandTarget]
        : ['route', 'get', target.commandTarget];
    final result = await _runProcess(
      'ip',
      arguments,
      processRunner: processRunner,
    );
    if (result.exitCode != 0) {
      return null;
    }

    final lines = (result.stdout as String)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return null;
    }

    final tokens = lines.first.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty) {
      return null;
    }

    var index = 0;
    String? routeType;
    String? destination;
    if (_linuxSpecialRouteTypes.contains(tokens.first) && tokens.length >= 2) {
      routeType = tokens.first;
      destination = tokens[1];
      index = 2;
    } else {
      destination = tokens.first;
      index = 1;
    }

    String? gateway;
    String? interfaceName;
    String? sourceIp;
    String? flags;

    while (index < tokens.length) {
      final token = tokens[index];
      switch (token) {
        case 'via':
          if (index + 1 < tokens.length) {
            gateway = tokens[index + 1];
          }
          index += 2;
          break;
        case 'dev':
          if (index + 1 < tokens.length) {
            interfaceName = tokens[index + 1];
          }
          index += 2;
          break;
        case 'src':
          if (index + 1 < tokens.length) {
            sourceIp = tokens[index + 1];
          }
          index += 2;
          break;
        case 'metric':
        case 'proto':
        case 'scope':
        case 'pref':
        case 'table':
        case 'uid':
        case 'from':
          index += index + 1 < tokens.length ? 2 : 1;
          break;
        default:
          index += 1;
          break;
      }
    }

    if (routeType != null) {
      flags = routeType;
    }

    return _RouteLookupEntry(
      requestedHost: target.requestedHost,
      resolvedIp: target.resolvedIp,
      ipVersion: target.ipVersion,
      destination: destination,
      gateway: gateway,
      interfaceName: interfaceName,
      sourceIp: sourceIp,
      flags: flags,
      rawOutput: (result.stdout as String).trim(),
    );
  }

  static Future<List<_InterfaceInfoEntry>> _loadInterfaceInfoEntries({
    NetworkProcessRunner? processRunner,
  }) async {
    if (Platform.isMacOS) {
      final interfaces = await _readMacOsInterfaceInfo(
        processRunner: processRunner,
      );
      if (interfaces.isNotEmpty) {
        return interfaces;
      }
    }

    if (Platform.isLinux) {
      final interfaces = await _readLinuxInterfaceInfo(
        processRunner: processRunner,
      );
      if (interfaces.isNotEmpty) {
        return interfaces;
      }
    }

    final networkInterfaces = await NetworkInterface.list(
      includeLinkLocal: true,
      includeLoopback: true,
    );
    return networkInterfaces
        .map(
          (interface) => _InterfaceInfoEntry(
            name: interface.name,
            addresses: interface.addresses
                .map(
                  (address) => _InterfaceAddressInfo(
                    address: address.address,
                    ipVersion: address.type == InternetAddressType.IPv4
                        ? 'ipv4'
                        : 'ipv6',
                    scope: _addressScope(address.address),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  static Future<List<_InterfaceInfoEntry>> _readMacOsInterfaceInfo({
    NetworkProcessRunner? processRunner,
  }) async {
    final result = await _runProcess(
      'ifconfig',
      const [],
      processRunner: processRunner,
    );
    if (result.exitCode != 0) {
      return const [];
    }

    final gateways = await _readMacOsDefaultGateways(
      processRunner: processRunner,
    );
    final builders = <String, _InterfaceInfoEntryBuilder>{};
    _InterfaceInfoEntryBuilder? current;

    for (final line in (result.stdout as String).split('\n')) {
      final headerMatch = RegExp(
        r'^([0-9A-Za-z._:-]+):\s+flags=\d+<([^>]*)>(?:\s+mtu\s+(\d+))?',
      ).firstMatch(line);
      if (headerMatch != null) {
        final name = headerMatch.group(1)!;
        current = builders.putIfAbsent(
          name,
          () => _InterfaceInfoEntryBuilder(name),
        );
        current
          ..flags = headerMatch.group(2)?.split(',') ?? const []
          ..mtu = int.tryParse(headerMatch.group(3) ?? '')
          ..defaultGateways = gateways[name] ?? const [];
        continue;
      }

      if (current == null) {
        continue;
      }

      final trimmed = line.trim();
      if (trimmed.startsWith('ether ')) {
        current.mac = trimmed.substring('ether '.length).trim().toLowerCase();
        continue;
      }
      if (trimmed.startsWith('status: ')) {
        current.status = trimmed.substring('status: '.length).trim();
        continue;
      }

      final ipv4Match = RegExp(
        r'^inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+(\S+)',
      ).firstMatch(trimmed);
      if (ipv4Match != null) {
        current.addresses.add(
          _InterfaceAddressInfo(
            address: ipv4Match.group(1)!,
            ipVersion: 'ipv4',
            prefixLength: _ipv4MaskToPrefix(ipv4Match.group(2)!),
            scope: 'global',
          ),
        );
        continue;
      }

      final ipv6Match = RegExp(
        r'^inet6\s+([0-9a-fA-F:.%]+)\s+prefixlen\s+(\d+)',
      ).firstMatch(trimmed);
      if (ipv6Match != null) {
        final address = ipv6Match.group(1)!;
        current.addresses.add(
          _InterfaceAddressInfo(
            address: address,
            ipVersion: 'ipv6',
            prefixLength: int.tryParse(ipv6Match.group(2)!),
            scope: _addressScope(address),
          ),
        );
      }
    }

    return builders.values
        .map((builder) => builder.build())
        .toList(growable: false);
  }

  static Future<List<_InterfaceInfoEntry>> _readLinuxInterfaceInfo({
    NetworkProcessRunner? processRunner,
  }) async {
    final result = await _runProcess('ip', const [
      'addr',
      'show',
    ], processRunner: processRunner);
    if (result.exitCode != 0) {
      return const [];
    }

    final gateways = await _readLinuxDefaultGateways(
      processRunner: processRunner,
    );
    final builders = <String, _InterfaceInfoEntryBuilder>{};
    _InterfaceInfoEntryBuilder? current;

    for (final line in (result.stdout as String).split('\n')) {
      final headerMatch = RegExp(
        r'^\d+:\s+([^:]+):\s+<([^>]*)>.*\bmtu\s+(\d+)(?:.*\bstate\s+(\S+))?',
      ).firstMatch(line);
      if (headerMatch != null) {
        final name = headerMatch.group(1)!.split('@').first;
        current = builders.putIfAbsent(
          name,
          () => _InterfaceInfoEntryBuilder(name),
        );
        current
          ..flags = headerMatch.group(2)?.split(',') ?? const []
          ..mtu = int.tryParse(headerMatch.group(3) ?? '')
          ..status = headerMatch.group(4)
          ..defaultGateways = gateways[name] ?? const [];
        continue;
      }

      if (current == null) {
        continue;
      }

      final linkMatch = RegExp(
        r'^\s+link/\S+\s+([0-9a-fA-F:]{17})',
      ).firstMatch(line);
      if (linkMatch != null) {
        current.mac = linkMatch.group(1)?.toLowerCase();
        continue;
      }

      final ipv4Match = RegExp(
        r'^\s+inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)(?:\s+brd\s+\S+)?\s+scope\s+(\S+)',
      ).firstMatch(line);
      if (ipv4Match != null) {
        current.addresses.add(
          _InterfaceAddressInfo(
            address: ipv4Match.group(1)!,
            ipVersion: 'ipv4',
            prefixLength: int.tryParse(ipv4Match.group(2)!),
            scope: ipv4Match.group(3)!,
          ),
        );
        continue;
      }

      final ipv6Match = RegExp(
        r'^\s+inet6\s+([0-9a-fA-F:.%]+)/(\d+)\s+scope\s+(\S+)',
      ).firstMatch(line);
      if (ipv6Match != null) {
        current.addresses.add(
          _InterfaceAddressInfo(
            address: ipv6Match.group(1)!,
            ipVersion: 'ipv6',
            prefixLength: int.tryParse(ipv6Match.group(2)!),
            scope: ipv6Match.group(3)!,
          ),
        );
      }
    }

    return builders.values
        .map((builder) => builder.build())
        .toList(growable: false);
  }

  static Future<Map<String, List<_InterfaceGateway>>>
  _readMacOsDefaultGateways({NetworkProcessRunner? processRunner}) async {
    final gateways = <String, List<_InterfaceGateway>>{};
    for (final request in [
      ('ipv4', ['-n', 'get', 'default']),
      ('ipv6', ['-n', 'get', '-inet6', 'default']),
    ]) {
      final result = await _runProcess(
        'route',
        request.$2,
        processRunner: processRunner,
      );
      if (result.exitCode != 0) {
        continue;
      }

      final fields = <String, String>{};
      for (final line in (result.stdout as String).split('\n')) {
        final separator = line.indexOf(':');
        if (separator <= 0) {
          continue;
        }
        final key = line.substring(0, separator).trim().toLowerCase();
        final value = line.substring(separator + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          fields[key] = value;
        }
      }

      final interfaceName = fields['interface'];
      final gateway = fields['gateway'];
      if (interfaceName == null || gateway == null) {
        continue;
      }
      gateways
          .putIfAbsent(interfaceName, () => [])
          .add(_InterfaceGateway(ip: gateway, ipVersion: request.$1));
    }
    return gateways;
  }

  static Future<Map<String, List<_InterfaceGateway>>>
  _readLinuxDefaultGateways({NetworkProcessRunner? processRunner}) async {
    final gateways = <String, List<_InterfaceGateway>>{};
    for (final request in [
      ('ipv4', ['route', 'show', 'default']),
      ('ipv6', ['-6', 'route', 'show', 'default']),
    ]) {
      final result = await _runProcess(
        'ip',
        request.$2,
        processRunner: processRunner,
      );
      if (result.exitCode != 0) {
        continue;
      }

      for (final line in (result.stdout as String).split('\n')) {
        final match = RegExp(
          r'^default(?:\s+via\s+(\S+))?.*\sdev\s+(\S+)',
        ).firstMatch(line.trim());
        if (match == null) {
          continue;
        }
        final gateway = match.group(1);
        final interfaceName = match.group(2);
        if (interfaceName == null) {
          continue;
        }
        gateways
            .putIfAbsent(interfaceName, () => [])
            .add(_InterfaceGateway(ip: gateway, ipVersion: request.$1));
      }
    }
    return gateways;
  }

  static Future<_PathMtuMeasurement?> _runLinuxTracepath(
    _ResolvedRouteTarget target, {
    required _RouteLookupEntry? route,
    required List<_InterfaceInfoEntry> interfaces,
    NetworkProcessRunner? processRunner,
  }) async {
    for (final command in _tracepathCommandsForTarget(target)) {
      try {
        final result = await _runProcess(
          command.$1,
          command.$2,
          processRunner: processRunner,
        );
        final stdout = (result.stdout as String).trim();
        if (stdout.isEmpty) {
          continue;
        }

        int? pathMtu;
        final hops = <_TracepathHop>[];
        for (final line in stdout.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            continue;
          }

          final pmtuMatch = RegExp(r'\bpmtu\s+(\d+)').firstMatch(trimmed);
          if (pmtuMatch != null) {
            pathMtu = int.tryParse(pmtuMatch.group(1)!);
          }

          final hopMatch = RegExp(r'^(\d+)[?:]?:\s+(.*)$').firstMatch(trimmed);
          if (hopMatch == null) {
            continue;
          }

          final details = hopMatch.group(2)!;
          final nodeToken = details.split(RegExp(r'\s+')).first;
          final timeMatch = RegExp(r'([0-9.]+)ms').firstMatch(details);
          final hopPmtuMatch = RegExp(r'\bpmtu\s+(\d+)').firstMatch(details);
          hops.add(
            _TracepathHop(
              hop: int.parse(hopMatch.group(1)!),
              node: nodeToken == '[LOCALHOST]' ? null : nodeToken,
              timeMs: timeMatch == null
                  ? null
                  : double.tryParse(timeMatch.group(1)!),
              pathMtu: hopPmtuMatch == null
                  ? null
                  : int.tryParse(hopPmtuMatch.group(1)!),
              note: details.contains('no reply') ? 'no reply' : null,
            ),
          );
        }

        if (pathMtu != null || hops.isNotEmpty) {
          return _PathMtuMeasurement(
            resolvedIp: target.resolvedIp,
            ipVersion: target.ipVersion,
            pathMtu: pathMtu,
            interfaceName: route?.interfaceName,
            gateway: route?.gateway,
            sourceIp: route?.sourceIp,
            discoveryMethod: command.$1,
            hops: hops,
          );
        }
      } on ProcessException {
        continue;
      }
    }

    return _buildInterfaceMtuFallbackMeasurement(
      target,
      route: route,
      interfaces: interfaces,
      note:
          'tracepath output was unavailable, so this falls back to the egress '
          'interface MTU.',
    );
  }

  static _PathMtuMeasurement? _buildInterfaceMtuFallbackMeasurement(
    _ResolvedRouteTarget target, {
    required _RouteLookupEntry? route,
    required List<_InterfaceInfoEntry> interfaces,
    required String note,
  }) {
    final interfaceName = route?.interfaceName;
    if (interfaceName == null) {
      return null;
    }

    final interface = _firstWhereOrNull<_InterfaceInfoEntry>(
      interfaces,
      (entry) => entry.name == interfaceName,
    );
    if (interface?.mtu == null) {
      return null;
    }

    return _PathMtuMeasurement(
      resolvedIp: target.resolvedIp,
      ipVersion: target.ipVersion,
      pathMtu: interface!.mtu,
      interfaceName: interface.name,
      gateway: route?.gateway,
      sourceIp: route?.sourceIp,
      discoveryMethod: 'interface_mtu_fallback',
      notes: [note],
    );
  }

  static Future<Map<String, dynamic>> _browseMdnsPayload({
    required String serviceType,
    required int timeoutMs,
    required int maxResults,
    required String ipVersion,
  }) async {
    final listenAddresses = ipVersion == 'ipv4'
        ? [InternetAddress.anyIPv4]
        : ipVersion == 'ipv6'
        ? [InternetAddress.anyIPv6]
        : [InternetAddress.anyIPv4, InternetAddress.anyIPv6];

    final serviceEntries = <String, _MdnsServiceEntry>{};
    final serviceTypes = <String>{};

    for (final listenAddress in listenAddresses) {
      MDnsClient? client;
      try {
        client = MDnsClient();
        await client.start(listenAddress: listenAddress);
        final pointers = await _collectStreamWithinTimeout<PtrResourceRecord>(
          client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
          ),
          timeout: Duration(milliseconds: timeoutMs),
          maxResults: maxResults,
        );

        if (serviceType == _mdnsServiceCatalog) {
          for (final pointer in pointers) {
            serviceTypes.add(pointer.domainName);
          }
          continue;
        }

        for (final pointer in pointers) {
          final instanceName = pointer.domainName;
          final targets = <_MdnsServiceTarget>[];
          final txtRecords = <String>{};

          final services = await _collectStreamWithinTimeout<SrvResourceRecord>(
            client.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(instanceName),
            ),
            timeout: Duration(milliseconds: timeoutMs),
            maxResults: maxResults,
          );
          final texts = await _collectStreamWithinTimeout<TxtResourceRecord>(
            client.lookup<TxtResourceRecord>(
              ResourceRecordQuery.text(instanceName),
            ),
            timeout: Duration(milliseconds: timeoutMs),
            maxResults: maxResults,
          );
          for (final text in texts) {
            txtRecords.add(text.text);
          }

          for (final service in services) {
            final addresses = <String>{};
            if (ipVersion != 'ipv6') {
              final ipv4Addresses =
                  await _collectStreamWithinTimeout<IPAddressResourceRecord>(
                    client.lookup<IPAddressResourceRecord>(
                      ResourceRecordQuery.addressIPv4(service.target),
                    ),
                    timeout: Duration(milliseconds: timeoutMs),
                    maxResults: maxResults,
                  );
              addresses.addAll(
                ipv4Addresses.map((record) => record.address.address),
              );
            }
            if (ipVersion != 'ipv4') {
              final ipv6Addresses =
                  await _collectStreamWithinTimeout<IPAddressResourceRecord>(
                    client.lookup<IPAddressResourceRecord>(
                      ResourceRecordQuery.addressIPv6(service.target),
                    ),
                    timeout: Duration(milliseconds: timeoutMs),
                    maxResults: maxResults,
                  );
              addresses.addAll(
                ipv6Addresses.map((record) => record.address.address),
              );
            }

            targets.add(
              _MdnsServiceTarget(
                host: service.target,
                port: service.port,
                priority: service.priority,
                weight: service.weight,
                addresses: addresses.toList()..sort(_compareIpAddresses),
              ),
            );
          }

          serviceEntries
              .putIfAbsent(
                instanceName,
                () => _MdnsServiceEntry(
                  instanceName: instanceName,
                  serviceType: serviceType,
                ),
              )
              .merge(
                _MdnsServiceEntry(
                  instanceName: instanceName,
                  serviceType: serviceType,
                  txtRecords: txtRecords.toList(growable: false),
                  targets: targets,
                ),
              );
        }
      } catch (_) {
        // Ignore transport-specific mDNS failures so the remaining family
        // still has a chance to return useful results.
      } finally {
        client?.stop();
      }
    }

    if (serviceType == _mdnsServiceCatalog) {
      final services = serviceTypes.toList()..sort();
      return {
        'service_type': serviceType,
        'ip_version': ipVersion,
        'services_found': services.length,
        'services': services.map((type) => {'service_type': type}).toList(),
      };
    }

    final services = serviceEntries.values.toList()
      ..sort((a, b) => a.instanceName.compareTo(b.instanceName));
    return {
      'service_type': serviceType,
      'ip_version': ipVersion,
      'services_found': services.length,
      'services': services.map((entry) => entry.toJson()).toList(),
    };
  }

  static Future<List<T>> _collectStreamWithinTimeout<T>(
    Stream<T> stream, {
    required Duration timeout,
    int? maxResults,
  }) async {
    final results = <T>[];
    final completer = Completer<List<T>>();
    late final StreamSubscription<T> subscription;

    void finish() {
      if (completer.isCompleted) {
        return;
      }
      subscription.cancel();
      completer.complete(results);
    }

    subscription = stream.listen(
      (event) {
        results.add(event);
        if (maxResults != null && results.length >= maxResults) {
          finish();
        }
      },
      onError: (error, stackTrace) => finish(),
      onDone: finish,
      cancelOnError: false,
    );

    Timer(timeout, finish);
    return completer.future;
  }

  static List<(String, List<String>)> _tracepathCommandsForTarget(
    _ResolvedRouteTarget target,
  ) {
    if (target.ipVersion == 'ipv6') {
      return [
        ('tracepath', ['-6', '-n', target.commandTarget]),
        ('tracepath6', ['-n', target.commandTarget]),
        ('tracepath6', [target.commandTarget]),
      ];
    }
    return [
      ('tracepath', ['-n', target.commandTarget]),
    ];
  }

  static int? _ipv4MaskToPrefix(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.startsWith('0x')) {
      final mask = int.tryParse(normalized.substring(2), radix: 16);
      return mask == null ? null : _bitCount(mask);
    }

    final address = InternetAddress.tryParse(normalized);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return null;
    }
    return address.rawAddress.fold<int>(
      0,
      (sum, byte) => sum + _bitCount(byte),
    );
  }

  static int _bitCount(int value) {
    var count = 0;
    var current = value;
    while (current > 0) {
      count += current & 1;
      current >>= 1;
    }
    return count;
  }

  static String _addressScope(String address) {
    final parsed = InternetAddress.tryParse(_normalizeIpForComparison(address));
    if (parsed == null) {
      return 'unknown';
    }
    if (parsed.isLoopback) {
      return 'host';
    }
    if (parsed.type == InternetAddressType.IPv6) {
      final bytes = parsed.rawAddress;
      if (bytes.isNotEmpty && bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) {
        return 'link';
      }
      return 'global';
    }
    final bytes = parsed.rawAddress;
    if (bytes.length >= 2 && bytes[0] == 169 && bytes[1] == 254) {
      return 'link';
    }
    return 'global';
  }

  static String _normalizeMdnsServiceType(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _mdnsServiceCatalog;
    }
    if (trimmed.endsWith('.local')) {
      return trimmed;
    }
    return '$trimmed.local';
  }

  static T? _firstWhereOrNull<T>(
    Iterable<T> values,
    bool Function(T value) predicate,
  ) {
    for (final value in values) {
      if (predicate(value)) {
        return value;
      }
    }
    return null;
  }
}

class _NeighborCacheEntry {
  const _NeighborCacheEntry({
    required this.ip,
    required this.ipVersion,
    required this.source,
    this.mac,
    this.hostname,
    this.interfaceName,
    this.state,
  });

  final String ip;
  final String ipVersion;
  final String source;
  final String? mac;
  final String? hostname;
  final String? interfaceName;
  final String? state;

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'ip_version': ipVersion,
    'source': source,
    if (mac != null) 'mac': mac,
    if (hostname != null) 'hostname': hostname,
    if (interfaceName != null) 'interface': interfaceName,
    if (state != null) 'state': state,
  };
}

const Set<String> _linuxSpecialRouteTypes = {
  'local',
  'broadcast',
  'multicast',
  'blackhole',
  'unreachable',
  'prohibit',
  'throw',
};

class _ResolvedRouteTarget {
  const _ResolvedRouteTarget({
    required this.requestedHost,
    required this.commandTarget,
    required this.resolvedIp,
    required this.ipVersion,
  });

  final String requestedHost;
  final String commandTarget;
  final String resolvedIp;
  final String ipVersion;
}

class _RouteLookupEntry {
  const _RouteLookupEntry({
    required this.requestedHost,
    required this.resolvedIp,
    required this.ipVersion,
    this.destination,
    this.gateway,
    this.interfaceName,
    this.sourceIp,
    this.flags,
    this.rawOutput,
  });

  final String requestedHost;
  final String resolvedIp;
  final String ipVersion;
  final String? destination;
  final String? gateway;
  final String? interfaceName;
  final String? sourceIp;
  final String? flags;
  final String? rawOutput;

  Map<String, dynamic> toJson() => {
    'host': requestedHost,
    'resolved_ip': resolvedIp,
    'ip_version': ipVersion,
    if (destination != null) 'destination': destination,
    if (gateway != null) 'gateway': gateway,
    if (interfaceName != null) 'interface': interfaceName,
    if (sourceIp != null) 'source_ip': sourceIp,
    if (flags != null) 'flags': flags,
    if (rawOutput != null) 'raw_output': rawOutput,
  };
}

class _InterfaceInfoEntry {
  const _InterfaceInfoEntry({
    required this.name,
    this.mac,
    this.mtu,
    this.status,
    this.flags = const [],
    this.addresses = const [],
    this.defaultGateways = const [],
  });

  final String name;
  final String? mac;
  final int? mtu;
  final String? status;
  final List<String> flags;
  final List<_InterfaceAddressInfo> addresses;
  final List<_InterfaceGateway> defaultGateways;

  _InterfaceInfoEntry filtered({required String ipVersion}) {
    if (ipVersion == 'all') {
      return this;
    }

    return _InterfaceInfoEntry(
      name: name,
      mac: mac,
      mtu: mtu,
      status: status,
      flags: flags,
      addresses: addresses
          .where((entry) => entry.ipVersion == ipVersion)
          .toList(growable: false),
      defaultGateways: defaultGateways
          .where((entry) => entry.ipVersion == ipVersion)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (mac != null) 'mac': mac,
    if (mtu != null) 'mtu': mtu,
    if (status != null) 'status': status,
    if (flags.isNotEmpty) 'flags': flags,
    'is_up': flags.contains('UP') || status == 'active' || status == 'UP',
    'addresses': addresses.map((entry) => entry.toJson()).toList(),
    if (defaultGateways.isNotEmpty)
      'default_gateways': defaultGateways
          .map((entry) => entry.toJson())
          .toList(),
  };
}

class _InterfaceInfoEntryBuilder {
  _InterfaceInfoEntryBuilder(this.name);

  final String name;
  String? mac;
  int? mtu;
  String? status;
  List<String> flags = const [];
  final List<_InterfaceAddressInfo> addresses = [];
  List<_InterfaceGateway> defaultGateways = const [];

  _InterfaceInfoEntry build() {
    final sortedAddresses = addresses.toList(growable: false)
      ..sort((a, b) => NetworkTools._compareIpAddresses(a.address, b.address));
    return _InterfaceInfoEntry(
      name: name,
      mac: mac,
      mtu: mtu,
      status: status,
      flags: List.unmodifiable(flags),
      addresses: sortedAddresses,
      defaultGateways: List.unmodifiable(defaultGateways),
    );
  }
}

class _InterfaceAddressInfo {
  const _InterfaceAddressInfo({
    required this.address,
    required this.ipVersion,
    required this.scope,
    this.prefixLength,
  });

  final String address;
  final String ipVersion;
  final String scope;
  final int? prefixLength;

  Map<String, dynamic> toJson() => {
    'address': address,
    'ip_version': ipVersion,
    'scope': scope,
    if (prefixLength != null) 'prefix_length': prefixLength,
  };
}

class _InterfaceGateway {
  const _InterfaceGateway({required this.ip, required this.ipVersion});

  final String? ip;
  final String ipVersion;

  Map<String, dynamic> toJson() => {
    if (ip != null) 'ip': ip,
    'ip_version': ipVersion,
  };
}

class _PathMtuMeasurement {
  const _PathMtuMeasurement({
    required this.resolvedIp,
    required this.ipVersion,
    required this.discoveryMethod,
    this.pathMtu,
    this.interfaceName,
    this.gateway,
    this.sourceIp,
    this.notes = const [],
    this.hops = const [],
  });

  final String resolvedIp;
  final String ipVersion;
  final String discoveryMethod;
  final int? pathMtu;
  final String? interfaceName;
  final String? gateway;
  final String? sourceIp;
  final List<String> notes;
  final List<_TracepathHop> hops;

  Map<String, dynamic> toJson() => {
    'resolved_ip': resolvedIp,
    'ip_version': ipVersion,
    'discovery_method': discoveryMethod,
    if (pathMtu != null) 'path_mtu': pathMtu,
    if (interfaceName != null) 'interface': interfaceName,
    if (gateway != null) 'gateway': gateway,
    if (sourceIp != null) 'source_ip': sourceIp,
    if (notes.isNotEmpty) 'notes': notes,
    if (hops.isNotEmpty) 'hops': hops.map((entry) => entry.toJson()).toList(),
  };
}

class _TracepathHop {
  const _TracepathHop({
    required this.hop,
    this.node,
    this.timeMs,
    this.pathMtu,
    this.note,
  });

  final int hop;
  final String? node;
  final double? timeMs;
  final int? pathMtu;
  final String? note;

  Map<String, dynamic> toJson() => {
    'hop': hop,
    if (node != null) 'node': node,
    if (timeMs != null) 'time_ms': timeMs,
    if (pathMtu != null) 'path_mtu': pathMtu,
    if (note != null) 'note': note,
  };
}

class _MdnsServiceEntry {
  _MdnsServiceEntry({
    required this.instanceName,
    required this.serviceType,
    List<String>? txtRecords,
    List<_MdnsServiceTarget>? targets,
  }) : txtRecords = txtRecords ?? <String>[],
       targets = targets ?? <_MdnsServiceTarget>[];

  final String instanceName;
  final String serviceType;
  final List<String> txtRecords;
  final List<_MdnsServiceTarget> targets;

  void merge(_MdnsServiceEntry other) {
    for (final record in other.txtRecords) {
      if (!txtRecords.contains(record)) {
        txtRecords.add(record);
      }
    }
    for (final target in other.targets) {
      final existing = NetworkTools._firstWhereOrNull<_MdnsServiceTarget>(
        targets,
        (entry) => entry.host == target.host && entry.port == target.port,
      );
      if (existing == null) {
        targets.add(target);
      } else {
        existing.merge(target);
      }
    }
    targets.sort((a, b) => a.host.compareTo(b.host));
  }

  Map<String, dynamic> toJson() => {
    'service_instance': instanceName,
    'service_type': serviceType,
    if (txtRecords.isNotEmpty) 'txt_records': txtRecords,
    if (targets.isNotEmpty)
      'targets': targets.map((entry) => entry.toJson()).toList(),
  };
}

class _MdnsServiceTarget {
  _MdnsServiceTarget({
    required this.host,
    required this.port,
    required this.priority,
    required this.weight,
    required this.addresses,
  });

  final String host;
  final int port;
  final int priority;
  final int weight;
  final List<String> addresses;

  void merge(_MdnsServiceTarget other) {
    for (final address in other.addresses) {
      if (!addresses.contains(address)) {
        addresses.add(address);
      }
    }
    addresses.sort(NetworkTools._compareIpAddresses);
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'priority': priority,
    'weight': weight,
    if (addresses.isNotEmpty) 'addresses': addresses,
  };
}
