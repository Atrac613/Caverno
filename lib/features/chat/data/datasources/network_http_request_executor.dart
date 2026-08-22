import 'dart:async';
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

final class NetworkHttpResourceLimitException implements Exception {
  const NetworkHttpResourceLimitException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

HttpClient _defaultHttpClientFactory() => HttpClient();
Future<List<InternetAddress>> _defaultAddressLookup(String host) =>
    InternetAddress.lookup(host);

Future<ConnectionTask<Socket>> _defaultPinnedSocketConnector(
  Uri uri,
  InternetAddress address,
  int port,
) async {
  final socketTask = await Socket.startConnect(address, port);
  if (uri.scheme.toLowerCase() != 'https') return socketTask;
  final secureSocket = socketTask.socket.then(
    (socket) => SecureSocket.secure(socket, host: uri.host),
  );
  return ConnectionTask.fromSocket<Socket>(secureSocket, socketTask.cancel);
}

final class NetworkHttpRequestExecutor {
  NetworkHttpRequestExecutor({
    NetworkHttpClientFactory? clientFactory,
    NetworkEgressAddressLookup? addressLookup,
    NetworkPinnedSocketConnector? socketConnector,
    EgressDestinationPolicy destinationPolicy = const EgressDestinationPolicy(),
    this.maxResponseBodyBytes = defaultMaxResponseBodyBytes,
    this.responseIdleTimeout = defaultResponseIdleTimeout,
  }) : _clientFactory = clientFactory ?? _defaultHttpClientFactory,
       _addressLookup = addressLookup ?? _defaultAddressLookup,
       _socketConnector = socketConnector ?? _defaultPinnedSocketConnector,
       _destinationPolicy = destinationPolicy {
    if (maxResponseBodyBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBodyBytes,
        'maxResponseBodyBytes',
        'The response byte limit must be positive.',
      );
    }
    if (responseIdleTimeout <= Duration.zero) {
      throw ArgumentError.value(
        responseIdleTimeout,
        'responseIdleTimeout',
        'The response idle timeout must be positive.',
      );
    }
  }

  static const int _bodyMaxChars = 4000;
  static const int defaultMaxResponseBodyBytes = 1024 * 1024;
  static const Duration defaultResponseIdleTimeout = Duration(seconds: 5);
  static const Set<int> _redirectStatusCodes = {
    HttpStatus.movedPermanently,
    HttpStatus.found,
    HttpStatus.seeOther,
    HttpStatus.temporaryRedirect,
    HttpStatus.permanentRedirect,
  };

  final NetworkHttpClientFactory _clientFactory;
  final NetworkEgressAddressLookup _addressLookup;
  final NetworkPinnedSocketConnector _socketConnector;
  final EgressDestinationPolicy _destinationPolicy;
  final int maxResponseBodyBytes;
  final Duration responseIdleTimeout;

  Future<String> execute({
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
    final totalTimeout = Duration(seconds: timeoutSeconds);

    while (true) {
      final client = await _beforeDeadline(
        _createPinnedClient(
          currentUri,
          timeoutSeconds: timeoutSeconds,
          stopwatch: stopwatch,
          totalTimeout: totalTimeout,
        ),
        stopwatch: stopwatch,
        totalTimeout: totalTimeout,
      );
      try {
        final request = await _beforeDeadline(
          client.openUrl(currentMethod, currentUri),
          stopwatch: stopwatch,
          totalTimeout: totalTimeout,
        );
        request.followRedirects = false;
        request.maxRedirects = 0;
        _writeRequest(
          request,
          headers: currentHeaders,
          body: currentBody,
          contentType: contentType,
        );
        final response = await _beforeDeadline(
          request.close(),
          stopwatch: stopwatch,
          totalTimeout: totalTimeout,
        );
        final redirectUri = followRedirects
            ? _redirectTarget(currentUri, response)
            : null;
        if (redirectUri != null) {
          if (redirects.length >= maxRedirects) {
            await _consumeResponse(
              response,
              stopwatch: stopwatch,
              totalTimeout: totalTimeout,
              collectBody: false,
            );
            throw const EgressPolicyException(
              'too_many_redirects',
              'The response exceeded the configured redirect limit.',
            );
          }
          redirects.add({
            'status': response.statusCode,
            'location': redirectUri.toString(),
          });
          await _consumeResponse(
            response,
            stopwatch: stopwatch,
            totalTimeout: totalTimeout,
            collectBody: false,
          );
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

        final responseBytes = await _consumeResponse(
          response,
          stopwatch: stopwatch,
          totalTimeout: totalTimeout,
          collectBody: includeBody,
        );
        stopwatch.stop();
        final payload = _baseResponsePayload(
          originalUrl: url,
          method: method,
          response: response,
          elapsed: stopwatch.elapsed,
          redirects: redirects,
          statusOnly: statusOnly,
        );
        if (includeBody) {
          _addResponseBody(payload, responseBytes);
        }
        return jsonEncode(payload);
      } finally {
        client.close(force: true);
      }
    }
  }

  Future<HttpClient> _createPinnedClient(
    Uri uri, {
    required int timeoutSeconds,
    required Stopwatch stopwatch,
    required Duration totalTimeout,
  }) async {
    final literalAddress = InternetAddress.tryParse(uri.host);
    final addresses = literalAddress == null
        ? await _addressLookup(uri.host)
        : [literalAddress];
    _remaining(totalTimeout, stopwatch);
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

  Future<Uint8List> _consumeResponse(
    HttpClientResponse response, {
    required Stopwatch stopwatch,
    required Duration totalTimeout,
    required bool collectBody,
  }) async {
    final declaredLength = int.tryParse(
      response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
    );
    if (declaredLength != null && declaredLength > maxResponseBodyBytes) {
      throw _responseTooLarge();
    }

    final builder = collectBody ? BytesBuilder(copy: false) : null;
    var receivedBytes = 0;
    final iterator = StreamIterator<List<int>>(response);
    try {
      while (await _nextChunk(
        iterator,
        stopwatch: stopwatch,
        totalTimeout: totalTimeout,
      )) {
        final chunk = iterator.current;
        receivedBytes += chunk.length;
        if (receivedBytes > maxResponseBodyBytes) {
          throw _responseTooLarge();
        }
        builder?.add(chunk);
      }
    } finally {
      await iterator.cancel();
    }
    return builder?.takeBytes() ?? Uint8List(0);
  }

  Future<bool> _nextChunk(
    StreamIterator<List<int>> iterator, {
    required Stopwatch stopwatch,
    required Duration totalTimeout,
  }) async {
    final remaining = _remaining(totalTimeout, stopwatch);
    final wait = remaining < responseIdleTimeout
        ? remaining
        : responseIdleTimeout;
    try {
      return await iterator.moveNext().timeout(wait);
    } on TimeoutException {
      if (remaining <= responseIdleTimeout) {
        throw _totalTimeout(totalTimeout);
      }
      throw TimeoutException(
        'The HTTP response sent no data for '
        '${responseIdleTimeout.inMilliseconds} ms.',
        responseIdleTimeout,
      );
    }
  }

  Future<T> _beforeDeadline<T>(
    Future<T> operation, {
    required Stopwatch stopwatch,
    required Duration totalTimeout,
  }) {
    return operation.timeout(
      _remaining(totalTimeout, stopwatch),
      onTimeout: () => throw _totalTimeout(totalTimeout),
    );
  }

  Duration _remaining(Duration totalTimeout, Stopwatch stopwatch) {
    final remaining = totalTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw _totalTimeout(Duration.zero);
    }
    return remaining;
  }

  TimeoutException _totalTimeout(Duration timeout) =>
      TimeoutException('The HTTP request exceeded its total timeout.', timeout);

  NetworkHttpResourceLimitException _responseTooLarge() =>
      NetworkHttpResourceLimitException(
        'response_too_large',
        'The HTTP response exceeded the $maxResponseBodyBytes byte limit.',
      );

  void _addResponseBody(Map<String, dynamic> payload, Uint8List bytes) {
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
}
