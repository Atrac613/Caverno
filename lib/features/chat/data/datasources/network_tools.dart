import 'dart:convert';
import 'dart:io';

import 'package:dart_ping/dart_ping.dart';

/// Network diagnostic utilities for built-in MCP tools.
class NetworkTools {
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
