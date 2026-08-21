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
}) {
  RemoteCodingTransportPolicy.ensureConfidentialBeforeCredentials(
    url: url,
    certificatePin: certificatePin,
  );
  final client = HttpClient()
    ..badCertificateCallback = (certificate, host, port) {
      return RemoteCodingTransportPolicy.pinMatches(
        certificate,
        certificatePin,
      );
    };
  return WebSocket.connect(url, customClient: client);
}
