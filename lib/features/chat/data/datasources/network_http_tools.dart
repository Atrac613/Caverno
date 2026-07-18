import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef NetworkHttpClientFactory = HttpClient Function();

HttpClient _defaultHttpClientFactory() => HttpClient();

class NetworkHttpTools {
  NetworkHttpTools({NetworkHttpClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultHttpClientFactory;

  static const int _bodyMaxChars = 4000;

  final NetworkHttpClientFactory _clientFactory;

  Future<String> httpStatus({
    required String url,
    int timeoutSeconds = 10,
  }) async {
    final uri = Uri.parse(url);
    final client = _clientFactory()
      ..connectionTimeout = Duration(seconds: timeoutSeconds);

    try {
      final stopwatch = Stopwatch()..start();
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        Duration(seconds: timeoutSeconds),
      );
      stopwatch.stop();

      await response.drain<void>();

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });

      return jsonEncode({
        'url': url,
        'status_code': response.statusCode,
        'reason_phrase': response.reasonPhrase,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'headers': headers,
        'redirects': response.redirects
            .map(
              (redirect) => {
                'status': redirect.statusCode,
                'location': redirect.location.toString(),
              },
            )
            .toList(),
      });
    } finally {
      client.close();
    }
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
  }) async {
    final uri = Uri.parse(url);
    final client = _clientFactory()
      ..connectionTimeout = Duration(seconds: timeoutSeconds);

    try {
      final stopwatch = Stopwatch()..start();
      final request = await client.openUrl(method, uri);
      request.followRedirects = followRedirects;
      request.maxRedirects = maxRedirects;

      final providedHeaderNames = <String>{};
      if (headers != null) {
        headers.forEach((name, value) {
          providedHeaderNames.add(name.toLowerCase());
          request.headers.set(name, value);
        });
      }

      final hasBody = body != null && body.isNotEmpty;
      if (hasBody) {
        if (!providedHeaderNames.contains('content-type')) {
          request.headers.contentType = ContentType.parse(
            contentType ?? 'application/json',
          );
        }
        final encodedBody = utf8.encode(body);
        request.contentLength = encodedBody.length;
        request.add(encodedBody);
      }

      final response = await request.close().timeout(
        Duration(seconds: timeoutSeconds),
      );
      stopwatch.stop();

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      final payload = <String, dynamic>{
        'url': url,
        'method': method,
        'status_code': response.statusCode,
        'reason_phrase': response.reasonPhrase,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'headers': responseHeaders,
        'redirects': response.redirects
            .map(
              (redirect) => {
                'status': redirect.statusCode,
                'location': redirect.location.toString(),
              },
            )
            .toList(),
        'content_type': response.headers.contentType?.toString(),
      };

      if (!includeBody) {
        await response.drain<void>();
        return jsonEncode(payload);
      }

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

      return jsonEncode(payload);
    } finally {
      client.close();
    }
  }
}
