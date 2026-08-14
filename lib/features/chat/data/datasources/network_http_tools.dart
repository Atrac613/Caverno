import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../core/security/egress_destination_policy.dart';

typedef NetworkHttpClientFactory = HttpClient Function();
typedef NetworkEgressAddressLookup =
    Future<List<InternetAddress>> Function(String host);
typedef NetworkPinnedSocketConnector =
    Future<ConnectionTask<Socket>> Function(
      Uri uri,
      InternetAddress address,
      int port,
    );

HttpClient _defaultHttpClientFactory() => HttpClient();
Future<List<InternetAddress>> _defaultAddressLookup(String host) =>
    InternetAddress.lookup(host);

Future<ConnectionTask<Socket>> _defaultPinnedSocketConnector(
  Uri uri,
  InternetAddress address,
  int port,
) async {
  final socketTask = await Socket.startConnect(address, port);
  if (uri.scheme.toLowerCase() != 'https') {
    return socketTask;
  }
  final secureSocket = socketTask.socket.then(
    (socket) => SecureSocket.secure(socket, host: uri.host),
  );
  return ConnectionTask.fromSocket<Socket>(secureSocket, socketTask.cancel);
}

class NetworkHttpTools {
  NetworkHttpTools({
    NetworkHttpClientFactory? clientFactory,
    NetworkEgressAddressLookup? addressLookup,
    NetworkPinnedSocketConnector? socketConnector,
    EgressDestinationPolicy destinationPolicy = const EgressDestinationPolicy(),
  }) : _clientFactory = clientFactory ?? _defaultHttpClientFactory,
       _addressLookup = addressLookup ?? _defaultAddressLookup,
       _socketConnector = socketConnector ?? _defaultPinnedSocketConnector,
       _destinationPolicy = destinationPolicy;

  static const int _bodyMaxChars = 4000;

  final NetworkHttpClientFactory _clientFactory;
  final NetworkEgressAddressLookup _addressLookup;
  final NetworkPinnedSocketConnector _socketConnector;
  final EgressDestinationPolicy _destinationPolicy;

  Future<String> httpStatus({required String url, int timeoutSeconds = 10}) {
    return _httpRequest(
      method: 'GET',
      url: url,
      timeoutSeconds: timeoutSeconds,
      followRedirects: true,
      maxRedirects: 5,
      includeBody: false,
      statusOnly: true,
    );
  }

  Future<String> httpGet({
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

  Future<String> httpHead({
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

  Future<String> httpDelete({
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

  Future<String> httpPost({
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

  Future<String> httpPut({
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

  Future<String> httpPatch({
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

  Future<String> _httpRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
    required bool includeBody,
    bool statusOnly = false,
  }) async {
    final originalUri = _destinationPolicy.validateUri(Uri.parse(url));
    var currentUri = originalUri;
    var currentMethod = method;
    var currentHeaders = Map<String, String>.from(headers ?? const {});
    var currentBody = body;
    final redirects = <Map<String, dynamic>>[];
    final stopwatch = Stopwatch()..start();

    while (true) {
      final client = await _createPinnedClient(
        currentUri,
        timeoutSeconds: timeoutSeconds,
      );
      try {
        final request = await client.openUrl(currentMethod, currentUri);
        request.followRedirects = false;
        request.maxRedirects = 0;
        _writeRequest(
          request,
          headers: currentHeaders,
          body: currentBody,
          contentType: contentType,
        );

        final response = await request.close().timeout(
          Duration(seconds: timeoutSeconds),
        );
        final redirectUri = followRedirects
            ? _redirectTarget(currentUri, response)
            : null;
        if (redirectUri != null) {
          if (redirects.length >= maxRedirects) {
            await response.drain<void>();
            throw const EgressPolicyException(
              'too_many_redirects',
              'The response exceeded the configured redirect limit.',
            );
          }
          redirects.add({
            'status': response.statusCode,
            'location': redirectUri.toString(),
          });
          await response.drain<void>();
          currentHeaders = _destinationPolicy.headersForRedirect(
            currentHeaders,
            from: currentUri,
            to: redirectUri,
          );
          final redirectRequest = _redirectRequest(
            statusCode: response.statusCode,
            method: currentMethod,
            body: currentBody,
          );
          if (currentBody != null && redirectRequest.body == null) {
            currentHeaders = _withoutBodyHeaders(currentHeaders);
          }
          currentMethod = redirectRequest.method;
          currentBody = redirectRequest.body;
          currentUri = redirectUri;
          continue;
        }

        stopwatch.stop();
        final payload = _baseResponsePayload(
          originalUrl: url,
          method: method,
          response: response,
          elapsed: stopwatch.elapsed,
          redirects: redirects,
          statusOnly: statusOnly,
        );
        if (!includeBody) {
          await response.drain<void>();
          return jsonEncode(payload);
        }
        await _addResponseBody(payload, response);
        return jsonEncode(payload);
      } finally {
        client.close(force: true);
      }
    }
  }

  Future<HttpClient> _createPinnedClient(
    Uri uri, {
    required int timeoutSeconds,
  }) async {
    final literalAddress = InternetAddress.tryParse(uri.host);
    final addresses = literalAddress == null
        ? await _addressLookup(uri.host)
        : [literalAddress];
    final destination = _destinationPolicy.approveResolvedAddresses(
      uri,
      addresses,
    );
    final client = _clientFactory()
      ..connectionTimeout = Duration(seconds: timeoutSeconds)
      ..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (requestedUri, proxyHost, proxyPort) async {
      if (proxyHost != null ||
          proxyPort != null ||
          !_destinationPolicy.isSameOrigin(uri, requestedUri)) {
        throw const EgressPolicyException(
          'unexpected_connection_target',
          'The HTTP client attempted an unapproved connection target.',
        );
      }
      final task = await _socketConnector(
        requestedUri,
        destination.address,
        _effectivePort(requestedUri),
      );
      final verifiedSocket = task.socket.then((socket) {
        _destinationPolicy.verifyPeer(destination, socket.remoteAddress);
        return socket;
      });
      return ConnectionTask.fromSocket<Socket>(verifiedSocket, task.cancel);
    };
    return client;
  }

  void _writeRequest(
    HttpClientRequest request, {
    required Map<String, String> headers,
    required String? body,
    required String? contentType,
  }) {
    final providedHeaderNames = <String>{};
    headers.forEach((name, value) {
      providedHeaderNames.add(name.toLowerCase());
      request.headers.set(name, value);
    });

    if (body == null || body.isEmpty) return;
    if (!providedHeaderNames.contains(HttpHeaders.contentTypeHeader)) {
      request.headers.contentType = ContentType.parse(
        contentType ?? 'application/json',
      );
    }
    final encodedBody = utf8.encode(body);
    request.contentLength = encodedBody.length;
    request.add(encodedBody);
  }

  Uri? _redirectTarget(Uri currentUri, HttpClientResponse response) {
    if (!_redirectStatusCodes.contains(response.statusCode)) return null;
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (location == null || location.trim().isEmpty) return null;
    return currentUri.resolve(location.trim());
  }

  ({String method, String? body}) _redirectRequest({
    required int statusCode,
    required String method,
    required String? body,
  }) {
    final normalizedMethod = method.toUpperCase();
    final rewriteToGet =
        statusCode == HttpStatus.seeOther && normalizedMethod != 'HEAD' ||
        (statusCode == HttpStatus.movedPermanently ||
                statusCode == HttpStatus.found) &&
            normalizedMethod == 'POST';
    return rewriteToGet
        ? (method: 'GET', body: null)
        : (method: method, body: body);
  }

  Map<String, String> _withoutBodyHeaders(Map<String, String> headers) {
    const bodyHeaders = {
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentTypeHeader,
      HttpHeaders.transferEncodingHeader,
    };
    return Map<String, String>.fromEntries(
      headers.entries.where(
        (entry) => !bodyHeaders.contains(entry.key.toLowerCase()),
      ),
    );
  }

  Map<String, dynamic> _baseResponsePayload({
    required String originalUrl,
    required String method,
    required HttpClientResponse response,
    required Duration elapsed,
    required List<Map<String, dynamic>> redirects,
    required bool statusOnly,
  }) {
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name] = values.join(', ');
    });
    final reportedRedirects = <Map<String, dynamic>>[
      ...redirects,
      ...response.redirects.map(
        (redirect) => {
          'status': redirect.statusCode,
          'location': redirect.location.toString(),
        },
      ),
    ];
    final payload = <String, dynamic>{
      'url': originalUrl,
      'status_code': response.statusCode,
      'reason_phrase': response.reasonPhrase,
      'response_time_ms': elapsed.inMilliseconds,
      'headers': responseHeaders,
      'redirects': reportedRedirects,
    };
    if (!statusOnly) {
      payload['method'] = method;
      payload['content_type'] = response.headers.contentType?.toString();
    }
    return payload;
  }

  Future<void> _addResponseBody(
    Map<String, dynamic> payload,
    HttpClientResponse response,
  ) async {
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

    final truncated = bodyText.length > _bodyMaxChars;
    payload['body'] = truncated
        ? bodyText.substring(0, _bodyMaxChars)
        : bodyText;
    payload['body_truncated'] = truncated;
    payload['body_encoding'] = encoding;
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  static const Set<int> _redirectStatusCodes = {
    HttpStatus.movedPermanently,
    HttpStatus.found,
    HttpStatus.seeOther,
    HttpStatus.temporaryRedirect,
    HttpStatus.permanentRedirect,
  };
}
