import 'dart:convert';
import 'dart:io';

typedef NetworkSocketConnector =
    Future<Socket> Function(String host, int port, {Duration? timeout});
typedef NetworkSecureSocketConnector =
    Future<SecureSocket> Function(
      String host,
      int port, {
      Duration? timeout,
      bool Function(X509Certificate certificate)? onBadCertificate,
    });
typedef NetworkClock = DateTime Function();

Future<Socket> _defaultSocketConnector(
  String host,
  int port, {
  Duration? timeout,
}) {
  return Socket.connect(host, port, timeout: timeout);
}

Future<SecureSocket> _defaultSecureSocketConnector(
  String host,
  int port, {
  Duration? timeout,
  bool Function(X509Certificate certificate)? onBadCertificate,
}) {
  return SecureSocket.connect(
    host,
    port,
    timeout: timeout,
    onBadCertificate: onBadCertificate,
  );
}

class NetworkSocketTools {
  NetworkSocketTools({
    NetworkSocketConnector? socketConnector,
    NetworkSecureSocketConnector? secureSocketConnector,
    NetworkClock? clock,
  }) : _socketConnector = socketConnector ?? _defaultSocketConnector,
       _secureSocketConnector =
           secureSocketConnector ?? _defaultSecureSocketConnector,
       _clock = clock ?? DateTime.now;

  static const Map<String, String> _whoisServers = {
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

  final NetworkSocketConnector _socketConnector;
  final NetworkSecureSocketConnector _secureSocketConnector;
  final NetworkClock _clock;

  Future<String> portCheck({
    required String host,
    required int port,
    int timeoutSeconds = 5,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await _socketConnector(
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
    } on SocketException catch (error) {
      stopwatch.stop();
      return jsonEncode({
        'host': host,
        'port': port,
        'open': false,
        'error': error.message,
      });
    }
  }

  Future<String> sslCertificate({
    required String host,
    int port = 443,
    int timeoutSeconds = 10,
  }) async {
    final socket = await _secureSocketConnector(
      host,
      port,
      timeout: Duration(seconds: timeoutSeconds),
      onBadCertificate: (_) => true,
    );

    final certificate = socket.peerCertificate;
    socket.destroy();

    if (certificate == null) {
      return jsonEncode({'host': host, 'error': 'No certificate returned'});
    }

    final now = _clock();
    return jsonEncode({
      'host': host,
      'port': port,
      'subject': certificate.subject,
      'issuer': certificate.issuer,
      'valid_from': certificate.startValidity.toIso8601String(),
      'valid_until': certificate.endValidity.toIso8601String(),
      'is_valid_now':
          now.isAfter(certificate.startValidity) &&
          now.isBefore(certificate.endValidity),
      'sha1_fingerprint': certificate.sha1,
    });
  }

  Future<String> whoisLookup({required String domain}) async {
    final normalizedDomain = domain.trim().toLowerCase();
    final whoisServer = _whoisServerForTld(_extractTld(normalizedDomain));
    final result = await _queryWhoisServer(
      server: whoisServer,
      query: normalizedDomain,
    );

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
          // Preserve the initial response when a referral cannot be queried.
        }
      }
    }

    return _truncate(result, 4000);
  }

  String _extractTld(String domain) {
    final parts = domain.split('.');
    if (parts.length < 2) return domain;
    return parts.last;
  }

  String _whoisServerForTld(String tld) {
    return _whoisServers[tld] ?? 'whois.iana.org';
  }

  Future<String> _queryWhoisServer({
    required String server,
    required String query,
  }) async {
    final socket = await _socketConnector(
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

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}\n... (truncated)';
  }
}
