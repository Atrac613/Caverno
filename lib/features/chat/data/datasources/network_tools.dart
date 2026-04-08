import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ping/dart_ping.dart';

/// Network diagnostic utilities for built-in MCP tools.
///
/// All methods run locally without external API dependencies.
class NetworkTools {

  // ---------------------------------------------------------------------------
  // DNS Lookup
  // ---------------------------------------------------------------------------

  /// Resolves [host] to IP addresses and returns a JSON-formatted result.
  static Future<String> dnsLookup({required String host}) async {
    final results = await InternetAddress.lookup(host);
    if (results.isEmpty) {
      return jsonEncode({'host': host, 'error': 'No records found'});
    }

    final records = results.map((r) => {
      'address': r.address,
      'type': r.type == InternetAddressType.IPv4 ? 'A' : 'AAAA',
      'host': r.host,
    }).toList();

    return jsonEncode({'host': host, 'records': records});
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
      'is_valid_now': DateTime.now().isAfter(cert.startValidity) &&
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
        'redirects': response.redirects.map((r) => {
          'status': r.statusCode,
          'location': r.location.toString(),
        }).toList(),
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
        'redirects': response.redirects.map((r) => {
          'status': r.statusCode,
          'location': r.location.toString(),
        }).toList(),
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

    return jsonEncode({
      'host': host,
      'max_hops': maxHops,
      'hops': hops,
    });
  }

  // ---------------------------------------------------------------------------
  // Ping
  // ---------------------------------------------------------------------------
  /// Pings a [host] and returns a JSON-formatted result string.
  static Future<String> ping({
    required String host,
    int count = 4,
    int timeoutSeconds = 5,
  }) async {
    final ping = Ping(
      host,
      count: count,
      timeout: timeoutSeconds,
    );

    final results = <Map<String, dynamic>>[];
    String? resolvedIp;
    int transmitted = 0;
    int received = 0;
    final times = <double>[];

    await for (final event in ping.stream) {
      if (event.response != null) {
        final response = event.response!;
        resolvedIp ??= response.ip?.toString();
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
          results.add({
            'seq': response.seq,
            'status': 'timeout',
          });
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
        ? ((transmitted - received) / transmitted * 100)
            .toStringAsFixed(1)
        : '0.0';

    final payload = <String, dynamic>{
      'host': host,
      // ignore: use_null_aware_elements
      if (resolvedIp != null) 'resolved_ip': resolvedIp,
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
            (times.reduce((a, b) => a + b) / times.length)
                .toStringAsFixed(2),
          ),
          'max_ms': double.parse(
            times.reduce((a, b) => a > b ? a : b).toStringAsFixed(2),
          ),
        },
      },
    };

    return jsonEncode(payload);
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
}
