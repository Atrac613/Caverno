import 'dart:io';

import '../domain/remote_coding_transport_policy.dart';

typedef RemoteCodingWebSocketConnector =
    Future<WebSocket> Function({
      required String url,
      required String certificatePin,
    });

Future<WebSocket> connectPinnedRemoteCodingWebSocket({
  required String url,
  required String certificatePin,
}) async {
  RemoteCodingTransportPolicy.ensureConfidentialBeforeCredentials(
    url: url,
    certificatePin: certificatePin,
  );
  // Disable platform roots so every certificate reaches the pin check.
  final context = SecurityContext(withTrustedRoots: false);
  final client = HttpClient(context: context)
    ..badCertificateCallback = (certificate, host, port) {
      return RemoteCodingTransportPolicy.pinMatches(
        certificate,
        certificatePin,
      );
    };
  try {
    return await WebSocket.connect(url, customClient: client);
  } finally {
    client.close();
  }
}
