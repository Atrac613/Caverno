import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/network_http_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('httpStatus reports status, headers, redirects, and cleanup', () async {
    final harness = _FakeHttpHarness([
      _FakeHttpClient.withResponse(
        _FakeHttpResponse(
          statusCode: HttpStatus.created,
          reasonPhrase: 'Created',
          headers: {
            'x-network-test': ['status'],
          },
          redirects: [
            _FakeRedirectInfo(
              statusCode: HttpStatus.movedPermanently,
              location: Uri.parse('https://redirect.example.test/'),
            ),
          ],
          body: utf8.encode('drained'),
        ),
      ),
    ]);
    final tools = NetworkHttpTools(clientFactory: harness.createClient);

    final result = _decode(
      await tools.httpStatus(
        url: 'https://example.test/status',
        timeoutSeconds: 7,
      ),
    );

    expect(result['url'], 'https://example.test/status');
    expect(result['status_code'], HttpStatus.created);
    expect(result['reason_phrase'], 'Created');
    expect(result['response_time_ms'], isA<int>());
    expect(result['headers'], containsPair('x-network-test', 'status'));
    expect(result['redirects'], [
      {
        'status': HttpStatus.movedPermanently,
        'location': 'https://redirect.example.test/',
      },
    ]);
    expect(result, isNot(contains('body')));
    expect(harness.createdClients, hasLength(1));
    expect(harness.createdClients.single.connectionTimeout, 7.seconds);
    expect(harness.createdClients.single.request?.method, 'GET');
    expect(harness.createdClients.single.closed, isTrue);
  });

  test('GET preserves request controls and returns text', () async {
    final harness = _FakeHttpHarness([
      _FakeHttpClient.withResponse(
        _FakeHttpResponse(
          statusCode: HttpStatus.ok,
          reasonPhrase: 'OK',
          headers: {
            'content-type': ['text/plain; charset=utf-8'],
            'x-network-test': ['text'],
          },
          redirects: [
            _FakeRedirectInfo(
              statusCode: HttpStatus.found,
              location: Uri.parse('https://example.test/text'),
            ),
          ],
          body: utf8.encode('hello from fake transport'),
        ),
      ),
    ]);
    final tools = NetworkHttpTools(clientFactory: harness.createClient);

    final result = _decode(
      await tools.httpGet(
        url: 'https://example.test/redirect',
        headers: const {'X-Request-Test': 'redirect'},
        timeoutSeconds: 3,
        followRedirects: false,
        maxRedirects: 2,
      ),
    );
    final request = harness.createdClients.single.request!;

    expect(request.method, 'GET');
    expect(request.uri, Uri.parse('https://example.test/redirect'));
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 2);
    expect(request.headers.value('x-request-test'), 'redirect');
    expect(result['method'], 'GET');
    expect(result['status_code'], HttpStatus.ok);
    expect(result['body'], 'hello from fake transport');
    expect(result['body_bytes'], 25);
    expect(result['body_encoding'], 'utf-8');
    expect(result['body_truncated'], isFalse);
    expect(result['content_type'], 'text/plain; charset=utf-8');
    expect(result['headers'], containsPair('x-network-test', 'text'));
    expect(result['redirects'], [
      {'status': HttpStatus.found, 'location': 'https://example.test/text'},
    ]);
  });

  test('HEAD drains the response and omits body fields', () async {
    final harness = _FakeHttpHarness([
      _FakeHttpClient.withResponse(
        _FakeHttpResponse(
          headers: const {
            'content-type': ['text/plain'],
          },
          body: utf8.encode('not returned'),
        ),
      ),
    ]);
    final tools = NetworkHttpTools(clientFactory: harness.createClient);

    final result = _decode(
      await tools.httpHead(url: 'https://example.test/text', timeoutSeconds: 2),
    );

    expect(harness.createdClients.single.request?.method, 'HEAD');
    expect(result['method'], 'HEAD');
    expect(result['content_type'], 'text/plain');
    expect(result, isNot(contains('body')));
    expect(result, isNot(contains('body_bytes')));
    expect(result, isNot(contains('body_encoding')));
    expect(result, isNot(contains('body_truncated')));
  });

  test('mutation methods preserve verbs, bodies, and content types', () async {
    final harness = _FakeHttpHarness([
      for (var index = 0; index < 4; index += 1)
        _FakeHttpClient.withResponse(
          _FakeHttpResponse(body: utf8.encode('ok')),
        ),
    ]);
    final tools = NetworkHttpTools(clientFactory: harness.createClient);
    final calls =
        <
          ({
            String method,
            String body,
            String? expectedContentType,
            Future<String> Function() invoke,
          })
        >[
          (
            method: 'POST',
            body: 'post-body',
            expectedContentType: 'text/plain',
            invoke: () => tools.httpPost(
              url: 'https://example.test/echo',
              headers: const {
                'CONTENT-TYPE': 'text/plain',
                'X-Request-Test': 'post',
              },
              body: 'post-body',
              contentType: 'application/ignored',
            ),
          ),
          (
            method: 'PUT',
            body: 'put-body',
            expectedContentType: 'application/vnd.caverno.test',
            invoke: () => tools.httpPut(
              url: 'https://example.test/echo',
              body: 'put-body',
              contentType: 'application/vnd.caverno.test',
            ),
          ),
          (
            method: 'PATCH',
            body: '',
            expectedContentType: null,
            invoke: () =>
                tools.httpPatch(url: 'https://example.test/echo', body: ''),
          ),
          (
            method: 'DELETE',
            body: 'delete-body',
            expectedContentType: 'application/json',
            invoke: () => tools.httpDelete(
              url: 'https://example.test/echo',
              body: 'delete-body',
            ),
          ),
        ];

    for (var index = 0; index < calls.length; index += 1) {
      final call = calls[index];
      final result = _decode(await call.invoke());
      final request = harness.createdClients[index].request!;
      expect(result['method'], call.method);
      expect(request.method, call.method);
      expect(utf8.decode(request.bodyBytes), call.body);
      expect(request.contentLength, call.body.isEmpty ? -1 : call.body.length);
      expect(request.headers.contentType?.toString(), call.expectedContentType);
      if (call.method == 'POST') {
        expect(request.headers.value('x-request-test'), 'post');
      }
    }
  });

  test('encodes binary bodies and truncates long text bodies', () async {
    final harness = _FakeHttpHarness([
      _FakeHttpClient.withResponse(
        _FakeHttpResponse(body: const [0xff, 0xfe, 0xfd]),
      ),
      _FakeHttpClient.withResponse(
        _FakeHttpResponse(body: utf8.encode(List.filled(4001, 'a').join())),
      ),
    ]);
    final tools = NetworkHttpTools(clientFactory: harness.createClient);

    final binary = _decode(
      await tools.httpGet(url: 'https://example.test/binary'),
    );
    final large = _decode(
      await tools.httpGet(url: 'https://example.test/large'),
    );

    expect(binary['body_bytes'], 3);
    expect(binary['body_encoding'], 'base64');
    expect(binary['body'], base64Encode([0xff, 0xfe, 0xfd]));
    expect(binary['body_truncated'], isFalse);
    expect(large['body_bytes'], 4001);
    expect((large['body'] as String).length, 4000);
    expect(large['body_encoding'], 'utf-8');
    expect(large['body_truncated'], isTrue);
  });

  test('closes the client when request setup fails', () async {
    final harness = _FakeHttpHarness([
      _FakeHttpClient.withError(const SocketException('connection failed')),
    ]);
    final tools = NetworkHttpTools(clientFactory: harness.createClient);

    await expectLater(
      tools.httpGet(url: 'https://example.test/failure'),
      throwsA(isA<SocketException>()),
    );
    expect(harness.createdClients.single.closed, isTrue);
  });
}

extension on int {
  Duration get seconds => Duration(seconds: this);
}

Map<String, dynamic> _decode(String value) {
  return jsonDecode(value) as Map<String, dynamic>;
}

class _FakeHttpHarness {
  _FakeHttpHarness(this._pendingClients);

  final List<_FakeHttpClient> _pendingClients;
  final List<_FakeHttpClient> createdClients = [];

  HttpClient createClient() {
    final client = _pendingClients.removeAt(0);
    createdClients.add(client);
    return client;
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient.withResponse(this._response) : _error = null;
  _FakeHttpClient.withError(this._error) : _response = null;

  final _FakeHttpResponse? _response;
  final Object? _error;

  _FakeHttpRequest? request;
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return request = _FakeHttpRequest(
      method: method,
      uri: url,
      response: _response,
      error: _error,
    );
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest({
    required this.method,
    required this.uri,
    required _FakeHttpResponse? response,
    required Object? error,
  }) : _response = response,
       _error = error;

  @override
  final String method;

  @override
  final Uri uri;
  final _FakeHttpResponse? _response;
  final Object? _error;
  final List<int> bodyBytes = [];

  @override
  final _FakeHttpHeaders headers = _FakeHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  void add(List<int> data) {
    bodyBytes.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async {
    if (_error != null) {
      throw _error;
    }
    return _response!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpResponse({
    this.statusCode = HttpStatus.ok,
    this.reasonPhrase = 'OK',
    Map<String, List<String>> headers = const {},
    this.redirects = const [],
    this.body = const [],
  }) : headers = _FakeHttpHeaders(headers);

  @override
  final int statusCode;

  @override
  final String reasonPhrase;

  @override
  final _FakeHttpHeaders headers;

  @override
  final List<RedirectInfo> redirects;

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
  ContentType? get contentType {
    final value = this.value(HttpHeaders.contentTypeHeader);
    return value == null ? null : ContentType.parse(value);
  }

  @override
  set contentType(ContentType? value) {
    if (value == null) {
      _values.remove(HttpHeaders.contentTypeHeader);
    } else {
      set(HttpHeaders.contentTypeHeader, value.toString());
    }
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(', ');

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRedirectInfo implements RedirectInfo {
  _FakeRedirectInfo({required this.statusCode, required this.location});

  @override
  final int statusCode;

  @override
  final Uri location;

  @override
  String get method => 'GET';
}
