import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/security/egress_destination_policy.dart';
import 'package:caverno/core/services/browser_mediation_proxy.dart';
import 'package:caverno/core/services/browser_pinned_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserOriginMapper', () {
    final mapper = BrowserOriginMapper(
      proxyOrigin: Uri.parse('http://127.0.0.1:4321'),
      upstreamOrigin: Uri.parse('https://example.com'),
    );

    test('round-trips path, query, and fragment onto the proxy origin', () {
      final https = Uri.parse('https://example.com/r/LocalLLaMA/hot/?t=day');
      final encoded = mapper.toProxyUrl(https);
      expect(
        encoded.toString(),
        'http://127.0.0.1:4321/r/LocalLLaMA/hot/?t=day',
      );
      expect(mapper.toUpstream(encoded), https);
    });

    test('preserves a non-default upstream port across the round-trip', () {
      final mapper = BrowserOriginMapper(
        proxyOrigin: Uri.parse('http://127.0.0.1:4321'),
        upstreamOrigin: Uri.parse('http://cdn.example.com:8443'),
      );
      final customPort = Uri.parse('http://cdn.example.com:8443/app.js');
      expect(mapper.toUpstream(mapper.toProxyUrl(customPort)), customPort);
    });
  });

  group('BrowserProxiedContentRewriter', () {
    const rewriter = BrowserProxiedContentRewriter();
    final page = Uri.parse('https://example.com/dir/page.html');
    Uri? encode(Uri target) {
      if (target.host == 'cdn.example.com') {
        return Uri.parse('http://127.0.0.1:9999${target.path}');
      }
      fail('unexpected rewrite target $target');
    }

    test('rewrites only cross-origin absolute HTTP(S) references', () {
      const html = '''
<a href="https://cdn.example.com/app.js">js</a>
<a href="https://example.com/dir/other.html">local</a>
<img src="/logo.png">
<link href="style.css">
''';
      final rewritten = rewriter.rewriteHtml(html, page, proxyUrlFor: encode);
      expect(rewritten, contains('http://127.0.0.1:9999/app.js'));
      expect(rewritten, contains('href="/dir/other.html"'));
      expect(rewritten, contains('src="/logo.png"'));
      expect(rewritten, contains('href="style.css"'));
      expect(rewritten, isNot(contains('https://cdn.example.com')));
      expect(rewritten, isNot(contains('https://example.com/dir/other.html')));
    });

    test('leaves data, blob, and fragment references unchanged', () {
      const html = '<img src="data:image/png;base64,AA=="><a href="#top"></a>';
      expect(rewriter.rewriteHtml(html, page, proxyUrlFor: encode), html);
    });
  });

  group('BrowserPinnedHttpClient', () {
    test('pins the approved DNS answer and verifies the peer', () async {
      final harness = _FakeHttpHarness([
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(
            headers: const {
              'content-type': ['text/plain'],
            },
            body: utf8.encode('ok'),
          ),
        ),
      ]);
      final client = _client(harness);

      final response = await client.send(
        method: 'GET',
        uri: Uri.parse('https://example.test/page'),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(utf8.decode(response.body), 'ok');
      expect(harness.connectedAddresses.single.address, '93.184.216.34');
      expect(harness.connectedPorts.single, 443);
      expect(harness.createdClients.single.closed, isTrue);
    });

    test('rejects a private DNS answer before opening a request', () async {
      final harness = _FakeHttpHarness(const []);
      final client = BrowserPinnedHttpClient(
        clientFactory: harness.createClient,
        addressLookup: (_) async => [InternetAddress('127.0.0.1')],
        socketConnector: (uri, address, port) =>
            throw StateError('unreachable'),
      );

      await expectLater(
        client.approve(Uri.parse('https://example.test/')),
        throwsA(
          isA<EgressPolicyException>().having(
            (error) => error.code,
            'code',
            'unsafe_address',
          ),
        ),
      );
      expect(harness.createdClients, isEmpty);
    });

    test('rejects a peer mismatch before writing the request', () async {
      final harness = _FakeHttpHarness([
        _FakeHttpClient.withResponse(_FakeHttpResponse()),
      ]);
      final client = BrowserPinnedHttpClient(
        clientFactory: harness.createClient,
        addressLookup: (_) async => [InternetAddress('93.184.216.34')],
        socketConnector: (uri, address, port) async {
          return ConnectionTask.fromSocket<Socket>(
            Future<Socket>.value(_FakeSocket(InternetAddress('93.184.216.35'))),
            () {},
          );
        },
      );

      await expectLater(
        client.send(
          method: 'GET',
          uri: Uri.parse('https://example.test/mismatch'),
        ),
        throwsA(
          isA<EgressPolicyException>().having(
            (error) => error.code,
            'code',
            'peer_mismatch',
          ),
        ),
      );
      expect(harness.createdClients.single.request, isNull);
    });

    test('replays cookies on later requests to the same host', () async {
      final harness = _FakeHttpHarness([
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(
            headers: const {
              'set-cookie': ['session=abc; Path=/'],
            },
            body: utf8.encode('one'),
          ),
        ),
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(body: utf8.encode('two')),
        ),
      ]);
      final client = _client(harness);

      await client.send(
        method: 'GET',
        uri: Uri.parse('https://example.test/first'),
      );
      await client.send(
        method: 'GET',
        uri: Uri.parse('https://example.test/second'),
      );

      expect(
        harness.createdClients[1].request!.headers.value('cookie'),
        'session=abc',
      );
    });

    test('does not send Secure cookies on HTTP', () async {
      final harness = _FakeHttpHarness([
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(
            headers: const {
              'set-cookie': ['session=abc; Path=/; Secure'],
            },
          ),
        ),
        _FakeHttpClient.withResponse(_FakeHttpResponse()),
        _FakeHttpClient.withResponse(_FakeHttpResponse()),
      ]);
      final client = _client(harness);

      await client.send(
        method: 'GET',
        uri: Uri.parse('https://example.test/first'),
      );
      await client.send(
        method: 'GET',
        uri: Uri.parse('http://example.test/second'),
      );
      await client.send(
        method: 'GET',
        uri: Uri.parse('https://example.test/third'),
      );

      expect(
        harness.createdClients[1].request!.headers.value('cookie'),
        isNull,
      );
      expect(
        harness.createdClients[2].request!.headers.value('cookie'),
        'session=abc',
      );
    });

    test('honors Path, Domain, and Expires attributes', () async {
      final harness = _FakeHttpHarness([
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(
            headers: const {
              'set-cookie': [
                'admin=secret; Path=/admin',
                'session=abc; Domain=example.test; Path=/; '
                    'Expires=Wed, 21 Oct 2099 07:28:00 GMT',
                'gone=x; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/',
              ],
            },
          ),
        ),
        _FakeHttpClient.withResponse(_FakeHttpResponse()),
        _FakeHttpClient.withResponse(_FakeHttpResponse()),
        _FakeHttpClient.withResponse(_FakeHttpResponse()),
      ]);
      final client = _client(harness);

      await client.send(
        method: 'GET',
        uri: Uri.parse('https://www.example.test/admin/login'),
      );
      await client.send(
        method: 'GET',
        uri: Uri.parse('https://www.example.test/'),
      );
      await client.send(
        method: 'GET',
        uri: Uri.parse('https://www.example.test/admin/users'),
      );
      await client.send(method: 'GET', uri: Uri.parse('https://other.test/'));

      expect(
        harness.createdClients[1].request!.headers.value('cookie'),
        'session=abc',
      );
      expect(
        harness.createdClients[2].request!.headers.value('cookie'),
        'admin=secret; session=abc',
      );
      expect(
        harness.createdClients[3].request!.headers.value('cookie'),
        isNull,
      );
    });

    test(
      'rejects a Domain attribute that does not match the request host',
      () async {
        final harness = _FakeHttpHarness([
          _FakeHttpClient.withResponse(
            _FakeHttpResponse(
              headers: const {
                'set-cookie': ['session=abc; Domain=evil.com; Path=/'],
              },
            ),
          ),
          _FakeHttpClient.withResponse(_FakeHttpResponse()),
        ]);
        final client = _client(harness);

        await client.send(
          method: 'GET',
          uri: Uri.parse('https://example.test/first'),
        );
        await client.send(
          method: 'GET',
          uri: Uri.parse('https://example.test/second'),
        );

        expect(
          harness.createdClients[1].request!.headers.value('cookie'),
          isNull,
        );
      },
    );
  });

  group('BrowserMediationProxy', () {
    test('serves rewritten HTML through the pinned client', () async {
      final harness = _FakeHttpHarness([
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(
            headers: const {
              'content-type': ['text/html; charset=utf-8'],
            },
            body: utf8.encode(
              '<html><a href="https://cdn.example.test/app.js">js</a>'
              '<img src="/logo.png"></html>',
            ),
          ),
        ),
      ]);
      final proxy = BrowserMediationProxy(httpClient: _client(harness));
      addTearDown(proxy.stop);
      final page = await proxy.proxyUrlFor(
        Uri.parse('https://example.test/page'),
      );

      final fetched = await _get(page);

      expect(fetched.statusCode, HttpStatus.ok);
      expect(fetched.body, contains('src="/logo.png"'));
      expect(fetched.body, isNot(contains('https://cdn.example.test')));
      final cdn = RegExp(
        r'http://127\.0\.0\.1:(\d+)/app\.js',
      ).firstMatch(fetched.body);
      expect(cdn, isNotNull);
      expect(int.parse(cdn!.group(1)!), isNot(page.port));
      expect(
        fetched.headers['content-security-policy'],
        contains('http://127.0.0.1:${cdn.group(1)}'),
      );
      expect(
        fetched.headers['content-security-policy'],
        isNot(contains('http://127.0.0.1:*')),
      );
      expect(fetched.headers['referrer-policy'], 'no-referrer');
      expect(harness.connectedAddresses, isNotEmpty);
    });

    test('isolates each upstream origin on its own loopback port', () async {
      final proxy = BrowserMediationProxy(
        httpClient: BrowserPinnedHttpClient(
          socketConnector: (uri, address, port) =>
              throw StateError('unreachable'),
        ),
      );
      addTearDown(proxy.stop);

      final first = await proxy.proxyUrlFor(
        Uri.parse('https://a.example.test/r/foo'),
      );
      final second = await proxy.proxyUrlFor(
        Uri.parse('https://b.example.test/r/foo'),
      );

      expect(first.port, isNot(second.port));
      expect(first.path, '/r/foo');
      expect(second.path, '/r/foo');
      expect(proxy.targetFromProxyUrl(first)?.host, 'a.example.test');
      expect(proxy.targetFromProxyUrl(second)?.host, 'b.example.test');
    });

    test(
      'rejects loopback destinations before binding a proxy origin',
      () async {
        final proxy = BrowserMediationProxy(
          httpClient: BrowserPinnedHttpClient(
            socketConnector: (uri, address, port) =>
                throw StateError('unreachable'),
          ),
        );
        addTearDown(proxy.stop);

        await expectLater(
          proxy.proxyUrlFor(Uri.parse('https://127.0.0.1/admin')),
          throwsA(
            isA<EgressPolicyException>().having(
              (error) => error.code,
              'code',
              'unsafe_address',
            ),
          ),
        );
      },
    );

    test(
      'rewrites redirect Location headers onto the target origin slot',
      () async {
        final harness = _FakeHttpHarness([
          _FakeHttpClient.withResponse(
            _FakeHttpResponse(
              statusCode: HttpStatus.found,
              headers: const {
                'location': ['https://other.example.test/final'],
              },
            ),
          ),
        ]);
        final proxy = BrowserMediationProxy(httpClient: _client(harness));
        addTearDown(proxy.stop);
        final page = await proxy.proxyUrlFor(
          Uri.parse('https://example.test/start'),
        );

        final fetched = await _get(page, followRedirects: false);

        expect(fetched.statusCode, HttpStatus.found);
        final location = Uri.parse(fetched.headers['location']!);
        expect(location.scheme, 'http');
        expect(location.host, '127.0.0.1');
        expect(location.path, '/final');
        expect(location.port, isNot(page.port));
        expect(proxy.targetFromProxyUrl(location)?.host, 'other.example.test');
      },
    );

    test(
      'maps loopback Origin back to the slot upstream, not the request target',
      () async {
        final harness = _FakeHttpHarness([
          _FakeHttpClient.withResponse(_FakeHttpResponse()),
          _FakeHttpClient.withResponse(_FakeHttpResponse()),
        ]);
        final proxy = BrowserMediationProxy(httpClient: _client(harness));
        addTearDown(proxy.stop);
        final page = await proxy.proxyUrlFor(
          Uri.parse('https://example.test/page'),
        );

      await _get(page, requestHeaders: {'origin': page.origin});
      expect(
        harness.createdClients[0].request!.headers.value('origin'),
        'https://example.test',
      );

      await _get(page, requestHeaders: {'origin': 'http://127.0.0.1:1'});
        expect(
          harness.createdClients[1].request!.headers.value('origin'),
          isNull,
        );
      },
    );

    test('handles overlapping subresource requests', () async {
      final gate = Completer<void>();
      var opens = 0;
      Future<void> beforeOpen() async {
        opens += 1;
        if (opens >= 2 && !gate.isCompleted) {
          gate.complete();
        }
        await gate.future;
      }

      final harness = _FakeHttpHarness([
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(body: utf8.encode('one')),
          beforeOpen: beforeOpen,
        ),
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(body: utf8.encode('two')),
          beforeOpen: beforeOpen,
        ),
      ]);
      final proxy = BrowserMediationProxy(httpClient: _client(harness));
      addTearDown(proxy.stop);
      final page = await proxy.proxyUrlFor(
        Uri.parse('https://example.test/page'),
      );

      final results = await Future.wait([
        _get(page.replace(path: '/one')),
        _get(page.replace(path: '/two')),
      ]).timeout(const Duration(seconds: 2));

      expect(opens, 2);
      expect(results.map((fetched) => fetched.body).toSet(), {'one', 'two'});
    });
  });
}

BrowserPinnedHttpClient _client(_FakeHttpHarness harness) {
  return BrowserPinnedHttpClient(
    clientFactory: harness.createClient,
    addressLookup: (_) async => [InternetAddress('93.184.216.34')],
    socketConnector: (uri, address, port) async {
      harness.connectedAddresses.add(address);
      harness.connectedPorts.add(port);
      return ConnectionTask.fromSocket<Socket>(
        Future<Socket>.value(_FakeSocket(address)),
        () {},
      );
    },
  );
}

Future<_Fetched> _get(
  Uri url, {
  bool followRedirects = true,
  Map<String, String> requestHeaders = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.followRedirects = followRedirects;
    requestHeaders.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return _Fetched(
      statusCode: response.statusCode,
      headers: headers,
      body: utf8.decode(body),
    );
  } finally {
    client.close(force: true);
  }
}

class _Fetched {
  const _Fetched({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

class _FakeHttpHarness {
  _FakeHttpHarness(this._pendingClients);

  final List<_FakeHttpClient> _pendingClients;
  final List<_FakeHttpClient> createdClients = [];
  final List<InternetAddress> connectedAddresses = [];
  final List<int> connectedPorts = [];

  HttpClient createClient() {
    final client = _pendingClients.removeAt(0);
    createdClients.add(client);
    return client;
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient.withResponse(this._response, {this.beforeOpen});

  final _FakeHttpResponse _response;
  final Future<void> Function()? beforeOpen;
  _FakeHttpRequest? request;
  bool closed = false;
  Future<ConnectionTask<Socket>> Function(Uri, String?, int?)?
  configuredConnectionFactory;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    await beforeOpen?.call();
    final connect = configuredConnectionFactory;
    if (connect != null) {
      final task = await connect(url, null, null);
      await task.socket;
    }
    return request = _FakeHttpRequest(
      method: method,
      uri: url,
      response: _response,
    );
  }

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value,
  ) {
    configuredConnectionFactory = value;
  }

  @override
  set findProxy(String Function(Uri)? value) {}

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSocket implements Socket {
  _FakeSocket(this.remoteAddress);

  @override
  final InternetAddress remoteAddress;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest({
    required this.method,
    required this.uri,
    required this.response,
  });

  @override
  final String method;

  @override
  final Uri uri;
  final _FakeHttpResponse response;

  @override
  final _FakeHttpHeaders headers = _FakeHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpResponse({
    this.statusCode = HttpStatus.ok,
    Map<String, List<String>> headers = const {},
    this.body = const [],
  }) : headers = _FakeHttpHeaders(headers);

  @override
  final int statusCode;

  @override
  String get reasonPhrase => 'OK';

  @override
  final _FakeHttpHeaders headers;

  @override
  List<RedirectInfo> get redirects => const [];

  final List<int> body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(body).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  _FakeHttpHeaders([Map<String, List<String>> values = const {}]) {
    values.forEach((name, entries) {
      _values[name.toLowerCase()] = List<String>.from(entries);
    });
  }

  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  String? value(String name) {
    final values = _values[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.join(', ');
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
