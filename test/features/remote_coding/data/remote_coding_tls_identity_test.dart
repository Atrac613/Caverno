import 'dart:io';

import 'package:caverno/features/remote_coding/data/remote_coding_tls_identity.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_websocket_connector.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_transport_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generated identity binds WSS and accepts only the matching pin',
    () async {
      final identity = RemoteCodingTlsIdentity.generate();
      expect(identity.certificatePin, isNotEmpty);
      expect(identity.certificatePem, contains('BEGIN CERTIFICATE'));
      expect(identity.privateKeyPem, contains('BEGIN RSA PRIVATE KEY'));

      final roundTrip = RemoteCodingTlsIdentity.fromJson(identity.toJson());
      expect(roundTrip.certificatePin, identity.certificatePin);

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        identity.securityContext,
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.add('ok');
          await socket.close();
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
        }
      });

      final url = RemoteCodingTransportPolicy.websocketUrl(
        host: '127.0.0.1',
        port: server.port,
        certificatePin: identity.certificatePin,
      );
      final accepted = await connectPinnedRemoteCodingWebSocket(
        url: url,
        certificatePin: identity.certificatePin,
      );
      addTearDown(accepted.close);
      expect(await accepted.first, 'ok');

      expect(
        () => connectPinnedRemoteCodingWebSocket(
          url: url.replaceFirst('wss://', 'ws://'),
          certificatePin: identity.certificatePin,
        ),
        throwsA(isA<RemoteCodingPlaintextDowngradeException>()),
      );

      expect(
        () => connectPinnedRemoteCodingWebSocket(
          url: url,
          certificatePin: 'deadbeef',
        ),
        throwsA(isA<HandshakeException>()),
      );
    },
  );

  test('persisted identity rejects a mismatched certificate pin', () {
    final identity = RemoteCodingTlsIdentity.generate();
    final json = identity.toJson()..['certificatePin'] = 'deadbeef';

    expect(
      () => RemoteCodingTlsIdentity.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('persisted identity rejects a mismatched private key', () {
    final identity = RemoteCodingTlsIdentity.generate();
    final otherIdentity = RemoteCodingTlsIdentity.generate();
    final json = identity.toJson()
      ..['privateKeyPem'] = otherIdentity.privateKeyPem;

    expect(
      () => RemoteCodingTlsIdentity.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
