import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:caverno/features/chat/data/datasources/network_socket_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portCheck reports successful and failed connections', () async {
    final openSocket = _FakeSocket();
    final successHarness = _FakeSocketHarness(plainResults: [openSocket]);
    final successTools = NetworkSocketTools(
      socketConnector: successHarness.connect,
    );

    final open = _decode(
      await successTools.portCheck(
        host: 'open.example.test',
        port: 8443,
        timeoutSeconds: 7,
      ),
    );

    expect(open['host'], 'open.example.test');
    expect(open['port'], 8443);
    expect(open['open'], isTrue);
    expect(open['response_time_ms'], isA<int>());
    expect(openSocket.destroyed, isTrue);
    expect(successHarness.plainInvocations.single.host, 'open.example.test');
    expect(successHarness.plainInvocations.single.port, 8443);
    expect(successHarness.plainInvocations.single.timeout, 7.seconds);

    final failureHarness = _FakeSocketHarness(
      plainResults: [
        const _ConnectorFailure(SocketException('connection refused')),
      ],
    );
    final failureTools = NetworkSocketTools(
      socketConnector: failureHarness.connect,
    );

    final closed = _decode(
      await failureTools.portCheck(host: 'closed.example.test', port: 9),
    );

    expect(closed, {
      'host': 'closed.example.test',
      'port': 9,
      'open': false,
      'error': 'connection refused',
    });
    expect(failureHarness.plainInvocations.single.timeout, 5.seconds);
  });

  test('sslCertificate reports certificate metadata and cleanup', () async {
    final certificate = _FakeCertificate(
      subject: 'CN=example.test',
      issuer: 'CN=Caverno Test CA',
      startValidity: DateTime.utc(2026, 1, 1),
      endValidity: DateTime.utc(2027, 1, 1),
      sha1: Uint8List.fromList([0xaa, 0xbb, 0xcc]),
    );
    final secureSocket = _FakeSecureSocket(certificate);
    final harness = _FakeSocketHarness(secureResults: [secureSocket]);
    final tools = NetworkSocketTools(
      secureSocketConnector: harness.connectSecure,
      clock: () => DateTime.utc(2026, 7, 18),
    );

    final result = _decode(
      await tools.sslCertificate(
        host: 'tls.example.test',
        port: 9443,
        timeoutSeconds: 12,
      ),
    );

    expect(result, {
      'host': 'tls.example.test',
      'port': 9443,
      'subject': 'CN=example.test',
      'issuer': 'CN=Caverno Test CA',
      'valid_from': '2026-01-01T00:00:00.000Z',
      'valid_until': '2027-01-01T00:00:00.000Z',
      'is_valid_now': true,
      'sha1_fingerprint': [0xaa, 0xbb, 0xcc],
    });
    expect(secureSocket.destroyed, isTrue);
    expect(harness.secureInvocations.single.host, 'tls.example.test');
    expect(harness.secureInvocations.single.port, 9443);
    expect(harness.secureInvocations.single.timeout, 12.seconds);
    expect(harness.secureInvocations.single.acceptedBadCertificate, isTrue);
  });

  test('sslCertificate preserves the missing-certificate result', () async {
    final secureSocket = _FakeSecureSocket(null);
    final harness = _FakeSocketHarness(secureResults: [secureSocket]);
    final tools = NetworkSocketTools(
      secureSocketConnector: harness.connectSecure,
    );

    final result = _decode(
      await tools.sslCertificate(host: 'empty.example.test'),
    );

    expect(result, {
      'host': 'empty.example.test',
      'error': 'No certificate returned',
    });
    expect(secureSocket.destroyed, isTrue);
    expect(harness.secureInvocations.single.port, 443);
    expect(harness.secureInvocations.single.timeout, 10.seconds);
  });

  test('whoisLookup normalizes, follows referrals, and truncates', () async {
    final initialSocket = _FakeSocket(
      body: utf8.encode(
        'Domain Name: EXAMPLE.COM\n'
        'Registrar WHOIS Server: whois.registrar.test\n',
      ),
    );
    final detailedSocket = _FakeSocket(
      body: utf8.encode(List.filled(4001, 'd').join()),
    );
    final harness = _FakeSocketHarness(
      plainResults: [initialSocket, detailedSocket],
    );
    final tools = NetworkSocketTools(socketConnector: harness.connect);

    final result = await tools.whoisLookup(domain: '  EXAMPLE.COM  ');

    expect(harness.plainInvocations, hasLength(2));
    expect(harness.plainInvocations.map((invocation) => invocation.host), [
      'whois.verisign-grs.com',
      'whois.registrar.test',
    ]);
    expect(
      harness.plainInvocations.every(
        (invocation) =>
            invocation.port == 43 && invocation.timeout == 10.seconds,
      ),
      isTrue,
    );
    expect(initialSocket.writtenText, 'example.com\r\n');
    expect(detailedSocket.writtenText, 'example.com\r\n');
    expect(initialSocket.flushCount, 1);
    expect(detailedSocket.flushCount, 1);
    expect(initialSocket.destroyed, isTrue);
    expect(detailedSocket.destroyed, isTrue);
    expect(result, '${List.filled(4000, 'd').join()}\n... (truncated)');
  });

  test('whoisLookup falls back after referral failure', () async {
    const initialResponse =
        'Domain Name: EXAMPLE.UNKNOWN\n'
        'Registrar WHOIS Server: unavailable.example.test\n';
    final initialSocket = _FakeSocket(body: utf8.encode(initialResponse));
    final harness = _FakeSocketHarness(
      plainResults: [
        initialSocket,
        const _ConnectorFailure(SocketException('referral unavailable')),
      ],
    );
    final tools = NetworkSocketTools(socketConnector: harness.connect);

    final result = await tools.whoisLookup(domain: 'Example.Unknown');

    expect(result, initialResponse);
    expect(harness.plainInvocations.first.host, 'whois.iana.org');
    expect(harness.plainInvocations.last.host, 'unavailable.example.test');
    expect(initialSocket.destroyed, isTrue);
  });
}

extension on int {
  Duration get seconds => Duration(seconds: this);
}

Map<String, dynamic> _decode(String value) {
  return jsonDecode(value) as Map<String, dynamic>;
}

class _ConnectorFailure {
  const _ConnectorFailure(this.error);

  final Object error;
}

class _SocketInvocation {
  const _SocketInvocation({
    required this.host,
    required this.port,
    required this.timeout,
    this.acceptedBadCertificate,
  });

  final String host;
  final int port;
  final Duration? timeout;
  final bool? acceptedBadCertificate;
}

class _FakeSocketHarness {
  _FakeSocketHarness({
    List<Object> plainResults = const [],
    List<_FakeSecureSocket> secureResults = const [],
  }) : _plainResults = List<Object>.from(plainResults),
       _secureResults = List<_FakeSecureSocket>.from(secureResults);

  final List<Object> _plainResults;
  final List<_FakeSecureSocket> _secureResults;
  final List<_SocketInvocation> plainInvocations = [];
  final List<_SocketInvocation> secureInvocations = [];

  Future<Socket> connect(String host, int port, {Duration? timeout}) async {
    plainInvocations.add(
      _SocketInvocation(host: host, port: port, timeout: timeout),
    );
    final result = _plainResults.removeAt(0);
    if (result case _ConnectorFailure(:final error)) {
      throw error;
    }
    return result as Socket;
  }

  Future<SecureSocket> connectSecure(
    String host,
    int port, {
    Duration? timeout,
    bool Function(X509Certificate certificate)? onBadCertificate,
  }) async {
    final socket = _secureResults.removeAt(0);
    final certificate = socket.peerCertificate;
    secureInvocations.add(
      _SocketInvocation(
        host: host,
        port: port,
        timeout: timeout,
        acceptedBadCertificate: certificate == null
            ? null
            : onBadCertificate?.call(certificate),
      ),
    );
    return socket;
  }
}

class _FakeSocket extends Stream<Uint8List> implements Socket {
  _FakeSocket({List<int> body = const []}) : body = Uint8List.fromList(body);

  final Uint8List body;
  final StringBuffer _written = StringBuffer();
  bool destroyed = false;
  int flushCount = 0;

  String get writtenText => _written.toString();

  @override
  void write(Object? object) {
    _written.write(object);
  }

  @override
  Future<void> flush() async {
    flushCount += 1;
  }

  @override
  void destroy() {
    destroyed = true;
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<Uint8List>.value(body).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSecureSocket extends _FakeSocket implements SecureSocket {
  _FakeSecureSocket(this.peerCertificate);

  @override
  final X509Certificate? peerCertificate;
}

class _FakeCertificate implements X509Certificate {
  _FakeCertificate({
    required this.subject,
    required this.issuer,
    required this.startValidity,
    required this.endValidity,
    required this.sha1,
  });

  @override
  final String subject;

  @override
  final String issuer;

  @override
  final DateTime startValidity;

  @override
  final DateTime endValidity;

  @override
  final Uint8List sha1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
