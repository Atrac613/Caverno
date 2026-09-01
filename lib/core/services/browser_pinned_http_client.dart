import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../security/egress_destination_policy.dart';

typedef BrowserHttpClientFactory = HttpClient Function();
typedef BrowserEgressAddressLookup =
    Future<List<InternetAddress>> Function(String host);
typedef BrowserPinnedSocketConnector =
    Future<ConnectionTask<Socket>> Function(
      Uri uri,
      InternetAddress address,
      int port,
    );

/// One hop of a model-triggered browser fetch after DNS approval and peer pin.
class BrowserPinnedHttpResponse {
  const BrowserPinnedHttpResponse({
    required this.uri,
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final String reasonPhrase;
  final Map<String, List<String>> headers;
  final Uint8List body;

  String? get contentType => _headerValue(HttpHeaders.contentTypeHeader);

  String? get location => _headerValue(HttpHeaders.locationHeader);

  String? _headerValue(String name) {
    final values = headers[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.join(', ');
  }
}

/// Resolves, pins, and peer-checks HTTP(S) for the built-in browser proxy.
///
/// The WebView never dials the destination itself. This client is the only
/// path that may connect, and it reuses the shared [EgressDestinationPolicy].
class BrowserPinnedHttpClient {
  BrowserPinnedHttpClient({
    BrowserHttpClientFactory? clientFactory,
    BrowserEgressAddressLookup? addressLookup,
    BrowserPinnedSocketConnector? socketConnector,
    EgressDestinationPolicy destinationPolicy = const EgressDestinationPolicy(),
    this.maxResponseBodyBytes = defaultMaxResponseBodyBytes,
    this.responseIdleTimeout = defaultResponseIdleTimeout,
    DateTime Function()? clock,
  }) : _clientFactory = clientFactory ?? _defaultHttpClientFactory,
       _addressLookup =
           addressLookup ?? ((host) => InternetAddress.lookup(host)),
       _socketConnector = socketConnector ?? _defaultPinnedSocketConnector,
       _destinationPolicy = destinationPolicy,
       _cookies = _BrowserCookieJar(clock ?? DateTime.now) {
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

  static const int defaultMaxResponseBodyBytes = 8 * 1024 * 1024;
  static const Duration defaultResponseIdleTimeout = Duration(seconds: 15);
  static const Set<int> redirectStatusCodes = {
    HttpStatus.movedPermanently,
    HttpStatus.found,
    HttpStatus.seeOther,
    HttpStatus.temporaryRedirect,
    HttpStatus.permanentRedirect,
  };

  final BrowserHttpClientFactory _clientFactory;
  final BrowserEgressAddressLookup _addressLookup;
  final BrowserPinnedSocketConnector _socketConnector;
  final EgressDestinationPolicy _destinationPolicy;
  final int maxResponseBodyBytes;
  final Duration responseIdleTimeout;
  final _BrowserCookieJar _cookies;

  EgressDestinationPolicy get destinationPolicy => _destinationPolicy;

  Future<ApprovedEgressDestination> approve(Uri uri) async {
    final validated = _destinationPolicy.validateUri(uri);
    final literalAddress = InternetAddress.tryParse(validated.host);
    final addresses = literalAddress == null
        ? await _addressLookup(validated.host)
        : [literalAddress];
    return _destinationPolicy.approveResolvedAddresses(validated, addresses);
  }

  Future<BrowserPinnedHttpResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    List<int>? body,
    int timeoutSeconds = 30,
    Uri? requestSiteOrigin,
    bool initiatorSentOriginHeader = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final totalTimeout = Duration(seconds: timeoutSeconds);
    final destination = await approve(uri);
    _remaining(totalTimeout, stopwatch);
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
    try {
      final request = await _beforeDeadline(
        client.openUrl(method, uri),
        stopwatch: stopwatch,
        totalTimeout: totalTimeout,
      );
      request.followRedirects = false;
      request.maxRedirects = 0;
      _writeHeaders(
        request,
        headers: headers,
        uri: uri,
        method: method,
        requestSiteOrigin: requestSiteOrigin,
        initiatorSentOriginHeader: initiatorSentOriginHeader,
      );
      if (body != null && body.isNotEmpty) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await _beforeDeadline(
        request.close(),
        stopwatch: stopwatch,
        totalTimeout: totalTimeout,
      );
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = List<String>.from(values);
      });
      _cookies.storeFromResponse(uri, response, responseHeaders);
      final responseBody = await _consumeResponse(
        response,
        stopwatch: stopwatch,
        totalTimeout: totalTimeout,
      );
      return BrowserPinnedHttpResponse(
        uri: uri,
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        headers: responseHeaders,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }

  void _writeHeaders(
    HttpClientRequest request, {
    required Map<String, String> headers,
    required Uri uri,
    required String method,
    Uri? requestSiteOrigin,
    bool initiatorSentOriginHeader = false,
  }) {
    headers.forEach((name, value) {
      if (_hopByHopRequestHeaders.contains(name.toLowerCase())) return;
      request.headers.set(name, value);
    });
    final cookie = _cookies.header(
      uri,
      method: method,
      requestSiteOrigin: requestSiteOrigin,
      initiatorSentOriginHeader: initiatorSentOriginHeader,
    );
    if (cookie != null &&
        !headers.keys.any((name) => name.toLowerCase() == 'cookie')) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }
  }

  Future<Uint8List> _consumeResponse(
    HttpClientResponse response, {
    required Stopwatch stopwatch,
    required Duration totalTimeout,
  }) async {
    final declaredLength = int.tryParse(
      response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
    );
    if (declaredLength != null && declaredLength > maxResponseBodyBytes) {
      throw const EgressPolicyException(
        'response_too_large',
        'The browser response exceeded the configured byte limit.',
      );
    }

    final builder = BytesBuilder(copy: false);
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
          throw const EgressPolicyException(
            'response_too_large',
            'The browser response exceeded the configured byte limit.',
          );
        }
        builder.add(chunk);
      }
    } finally {
      await iterator.cancel();
    }
    return builder.takeBytes();
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
        throw TimeoutException(
          'The HTTP request exceeded its total timeout.',
          totalTimeout,
        );
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
      onTimeout: () => throw TimeoutException(
        'The HTTP request exceeded its total timeout.',
        totalTimeout,
      ),
    );
  }

  Duration _remaining(Duration totalTimeout, Stopwatch stopwatch) {
    final remaining = totalTimeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'The HTTP request exceeded its total timeout.',
        totalTimeout,
      );
    }
    return remaining;
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }
}

HttpClient _defaultHttpClientFactory() => HttpClient();

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

const Set<String> _hopByHopRequestHeaders = {
  HttpHeaders.hostHeader,
  HttpHeaders.connectionHeader,
  'keep-alive',
  HttpHeaders.proxyAuthorizationHeader,
  HttpHeaders.transferEncodingHeader,
  HttpHeaders.upgradeHeader,
  HttpHeaders.contentLengthHeader,
  HttpHeaders.cookieHeader,
  'te',
  'trailer',
};

/// RFC 6265-ish cookie jar keyed by name+domain+path.
///
/// Set-Cookie attributes are parsed on `;`, never on `,`, because `Expires`
/// contains commas. Secure cookies are only sent on HTTPS *upstream* URIs.
class _BrowserCookieJar {
  _BrowserCookieJar(this._clock);

  final DateTime Function() _clock;
  final List<_StoredCookie> _cookies = [];

  void storeFromResponse(
    Uri uri,
    HttpClientResponse response,
    Map<String, List<String>> headers,
  ) {
    final dartCookies = _tryDartCookies(response);
    if (dartCookies != null && dartCookies.isNotEmpty) {
      for (final cookie in dartCookies) {
        _store(_fromDartCookie(cookie), uri);
      }
      return;
    }
    store(uri, headers['set-cookie'] ?? const []);
  }

  void store(Uri uri, List<String> setCookieHeaders) {
    for (final header in setCookieHeaders) {
      final parsed = _parseSetCookie(header);
      if (parsed != null) _store(parsed, uri);
    }
  }

  String? header(
    Uri uri, {
    String method = 'GET',
    Uri? requestSiteOrigin,
    bool initiatorSentOriginHeader = false,
  }) {
    final now = _clock();
    final matching = <_StoredCookie>[];
    _cookies.removeWhere((cookie) => cookie.isExpired(now));
    for (final cookie in _cookies) {
      if (!_matchesRequest(cookie, uri)) continue;
      if (!_allowsSameSite(
        cookie,
        method: method,
        requestUri: uri,
        requestSiteOrigin: requestSiteOrigin,
        initiatorSentOriginHeader: initiatorSentOriginHeader,
      )) {
        continue;
      }
      matching.add(cookie);
    }
    if (matching.isEmpty) return null;
    return matching
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  void _store(_ParsedCookie parsed, Uri requestUri) {
    final now = _clock();
    final host = requestUri.host.toLowerCase();
    final domainResult = _cookieDomain(host, parsed.domain);
    if (domainResult == null) return;
    final path = _cookiePath(parsed.path, requestUri);
    DateTime? expiresAt = parsed.expires;
    if (parsed.maxAge != null) {
      if (parsed.maxAge! <= 0) {
        _cookies.removeWhere(
          (cookie) =>
              cookie.identityEquals(parsed.name, domainResult.domain, path),
        );
        return;
      }
      expiresAt = now.add(Duration(seconds: parsed.maxAge!));
    }
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      _cookies.removeWhere(
        (cookie) =>
            cookie.identityEquals(parsed.name, domainResult.domain, path),
      );
      return;
    }
    final stored = _StoredCookie(
      name: parsed.name,
      value: parsed.value,
      domain: domainResult.domain,
      hostOnly: domainResult.hostOnly,
      path: path,
      secure: parsed.secure,
      sameSite: parsed.sameSite,
      expiresAt: expiresAt,
    );
    _cookies.removeWhere(
      (cookie) =>
          cookie.identityEquals(stored.name, stored.domain, stored.path),
    );
    _cookies.add(stored);
  }

  bool _matchesRequest(_StoredCookie cookie, Uri uri) {
    if (cookie.secure && uri.scheme.toLowerCase() != 'https') return false;
    if (!_domainMatches(uri.host.toLowerCase(), cookie)) return false;
    return _pathMatches(uri.path.isEmpty ? '/' : uri.path, cookie.path);
  }

  bool _allowsSameSite(
    _StoredCookie cookie, {
    required String method,
    required Uri requestUri,
    Uri? requestSiteOrigin,
    required bool initiatorSentOriginHeader,
  }) {
    final initiator = requestSiteOrigin;
    if (initiator == null) return true;
    final sameSiteRequest =
        initiator.scheme.toLowerCase() == requestUri.scheme.toLowerCase() &&
        initiator.host.toLowerCase() == requestUri.host.toLowerCase() &&
        _cookieEffectivePort(initiator) == _cookieEffectivePort(requestUri);
    if (sameSiteRequest) return true;
    switch (cookie.sameSite) {
      case 'strict':
        return false;
      case 'none':
        return cookie.secure;
      case 'lax':
      default:
        // Origin present implies fetch/XHR, not a top-level navigation.
        if (initiatorSentOriginHeader) return false;
        final upper = method.toUpperCase();
        return upper == 'GET' || upper == 'HEAD';
    }
  }

  _CookieDomain? _cookieDomain(String requestHost, String? domainAttribute) {
    final requestIsIp = InternetAddress.tryParse(requestHost) != null;
    if (domainAttribute == null || domainAttribute.isEmpty) {
      return _CookieDomain(requestHost, hostOnly: true);
    }
    var domain = domainAttribute.toLowerCase();
    if (domain.startsWith('.')) domain = domain.substring(1);
    if (domain.isEmpty) return null;
    final domainIsIp = InternetAddress.tryParse(domain) != null;
    if (requestIsIp || domainIsIp) {
      if (domain != requestHost) return null;
      return _CookieDomain(requestHost, hostOnly: true);
    }
    if (!_hostDomainMatches(requestHost, domain)) return null;
    // Reject public-suffix-like values such as "com".
    if (!domain.contains('.') && domain != requestHost) return null;
    return _CookieDomain(domain, hostOnly: false);
  }

  String _cookiePath(String? pathAttribute, Uri requestUri) {
    if (pathAttribute != null &&
        pathAttribute.isNotEmpty &&
        pathAttribute.startsWith('/')) {
      return pathAttribute;
    }
    return _defaultCookiePath(requestUri);
  }

  _ParsedCookie? _parseSetCookie(String header) {
    final parts = header.split(';');
    if (parts.isEmpty) return null;
    final pair = parts.first;
    final equals = pair.indexOf('=');
    if (equals <= 0) return null;
    final name = pair.substring(0, equals).trim();
    if (name.isEmpty) return null;
    final parsed = _ParsedCookie(
      name: name,
      value: pair.substring(equals + 1).trim(),
    );
    for (final attribute in parts.skip(1)) {
      final trimmed = attribute.trim();
      if (trimmed.isEmpty) continue;
      final attrEquals = trimmed.indexOf('=');
      final key =
          (attrEquals == -1 ? trimmed : trimmed.substring(0, attrEquals))
              .trim()
              .toLowerCase();
      final value = attrEquals == -1
          ? ''
          : trimmed.substring(attrEquals + 1).trim();
      switch (key) {
        case 'domain':
          parsed.domain = value;
        case 'path':
          parsed.path = value;
        case 'secure':
          parsed.secure = true;
        case 'samesite':
          parsed.sameSite = value.toLowerCase();
        case 'max-age':
          parsed.maxAge = int.tryParse(value);
        case 'expires':
          try {
            parsed.expires = HttpDate.parse(value);
          } catch (_) {}
      }
    }
    return parsed;
  }

  _ParsedCookie _fromDartCookie(Cookie cookie) {
    return _ParsedCookie(
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path,
      secure: cookie.secure,
      expires: cookie.expires,
      maxAge: cookie.maxAge,
      sameSite: switch (cookie.sameSite) {
        SameSite.lax => 'lax',
        SameSite.strict => 'strict',
        SameSite.none => 'none',
        _ => null,
      },
    );
  }

  List<Cookie>? _tryDartCookies(HttpClientResponse response) {
    try {
      return response.cookies;
    } catch (_) {
      return null;
    }
  }
}

class _ParsedCookie {
  _ParsedCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.secure = false,
    this.expires,
    this.maxAge,
    this.sameSite,
  });

  final String name;
  final String value;
  String? domain;
  String? path;
  bool secure;
  DateTime? expires;
  int? maxAge;
  String? sameSite;
}

class _CookieDomain {
  const _CookieDomain(this.domain, {required this.hostOnly});

  final String domain;
  final bool hostOnly;
}

class _StoredCookie {
  const _StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.secure,
    required this.sameSite,
    required this.expiresAt,
  });

  final String name;
  final String value;
  final String domain;
  final bool hostOnly;
  final String path;
  final bool secure;
  final String? sameSite;
  final DateTime? expiresAt;

  bool isExpired(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  bool identityEquals(String otherName, String otherDomain, String otherPath) {
    return name.toLowerCase() == otherName.toLowerCase() &&
        domain == otherDomain &&
        path == otherPath;
  }
}

bool _domainMatches(String requestHost, _StoredCookie cookie) {
  if (cookie.hostOnly) return requestHost == cookie.domain;
  return _hostDomainMatches(requestHost, cookie.domain);
}

bool _hostDomainMatches(String host, String domain) {
  if (host == domain) return true;
  return host.endsWith('.$domain');
}

bool _pathMatches(String requestPath, String cookiePath) {
  if (requestPath == cookiePath) return true;
  if (!requestPath.startsWith(cookiePath)) return false;
  if (cookiePath.endsWith('/')) return true;
  return requestPath.length > cookiePath.length &&
      requestPath[cookiePath.length] == '/';
}

int _cookieEffectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}

String _defaultCookiePath(Uri uri) {
  final path = uri.path;
  if (path.isEmpty || !path.startsWith('/') || path == '/') return '/';
  final lastSlash = path.lastIndexOf('/');
  if (lastSlash <= 0) return '/';
  return path.substring(0, lastSlash);
}
