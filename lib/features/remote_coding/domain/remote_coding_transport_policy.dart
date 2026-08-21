import 'dart:io';

import 'package:crypto/crypto.dart';

import '../data/remote_coding_security.dart';

/// Thrown when credentials would be sent over plaintext WebSocket.
class RemoteCodingPlaintextDowngradeException implements Exception {
  const RemoteCodingPlaintextDowngradeException();

  @override
  String toString() =>
      'Remote Coding refuses to send credentials over plaintext WebSocket. '
      'Scan a fresh pairing QR from a host that advertises wss and a '
      'certificate pin.';
}

/// Builds pinned WSS URLs and rejects plaintext downgrade.
abstract final class RemoteCodingTransportPolicy {
  static const String confidentialScheme = 'wss';
  static const String plaintextScheme = 'ws';
  static const String websocketPath = '/ws';

  static String websocketUrl({
    required String host,
    required int port,
    required String certificatePin,
  }) {
    if (certificatePin.trim().isEmpty) {
      throw const RemoteCodingPlaintextDowngradeException();
    }
    return '$confidentialScheme://$host:$port$websocketPath';
  }

  static void ensureConfidentialBeforeCredentials({
    required String url,
    required String certificatePin,
  }) {
    if (certificatePin.trim().isEmpty ||
        !url.startsWith('$confidentialScheme://')) {
      throw const RemoteCodingPlaintextDowngradeException();
    }
  }

  static bool pinMatches(X509Certificate certificate, String certificatePin) {
    final expected = certificatePin.trim().toLowerCase();
    if (expected.isEmpty) {
      return false;
    }
    final actual = sha256.convert(certificate.der).toString();
    return RemoteCodingSecurity.constantTimeEquals(actual, expected);
  }

  static String pinForDer(List<int> der) => sha256.convert(der).toString();
}
