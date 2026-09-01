import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../security/egress_destination_policy.dart';
import 'browser_pinned_http_client.dart';

/// Maps one upstream origin onto a dedicated loopback HTTP origin.
///
/// Path, query, and fragment pass through unchanged so same-origin relative
/// URLs (`/api`, `./app.js`, `pushState`) stay on this proxy origin without
/// rewriting. Cross-origin absolute URLs must be rewritten onto a different
/// slot's loopback origin.
class BrowserOriginMapper {
  const BrowserOriginMapper({
    required this.proxyOrigin,
    required this.upstreamOrigin,
  });

  final Uri proxyOrigin;
  final Uri upstreamOrigin;

  bool isProxyUrl(Uri url) {
    return url.scheme.toLowerCase() == proxyOrigin.scheme.toLowerCase() &&
        url.host.toLowerCase() == proxyOrigin.host.toLowerCase() &&
        _effectivePort(url) == _effectivePort(proxyOrigin);
  }

  Uri toProxyUrl(Uri target) {
    return Uri(
      scheme: proxyOrigin.scheme,
      host: proxyOrigin.host,
      port: proxyOrigin.port,
      path: target.path.isEmpty ? '/' : target.path,
      query: target.hasQuery ? target.query : null,
      fragment: target.hasFragment ? target.fragment : null,
    );
  }

  Uri toUpstream(Uri proxyUrl) {
    return Uri(
      scheme: upstreamOrigin.scheme,
      host: upstreamOrigin.host,
      port: upstreamOrigin.hasPort ? upstreamOrigin.port : null,
      path: proxyUrl.path.isEmpty ? '/' : proxyUrl.path,
      query: proxyUrl.hasQuery ? proxyUrl.query : null,
      fragment: proxyUrl.hasFragment ? proxyUrl.fragment : null,
    );
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }
}

/// Rewrites only cross-origin absolute HTTP(S) references onto other proxy
/// origins. Same-origin relative and root-relative URLs are left alone.
class BrowserProxiedContentRewriter {
  const BrowserProxiedContentRewriter();

  Set<Uri> collectCrossOriginTargets(String content, Uri pageUrl) {
    final targets = <Uri>{};
    void consider(String raw) {
      final resolved = _resolveCrossOriginHttp(raw, pageUrl);
      if (resolved != null) targets.add(resolved);
    }

    for (final match in _quotedAttributePattern.allMatches(content)) {
      consider(match.group(3)!);
    }
    for (final match in _srcsetPattern.allMatches(content)) {
      for (final part in match.group(2)!.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final separator = trimmed.indexOf(' ');
        consider(separator == -1 ? trimmed : trimmed.substring(0, separator));
      }
    }
    for (final match in _cssUrlPattern.allMatches(content)) {
      consider(match.group(2)!);
    }
    return targets;
  }

  String rewriteHtml(
    String html,
    Uri pageUrl, {
    required Uri? Function(Uri target) proxyUrlFor,
  }) {
    var rewritten = html.replaceAllMapped(_quotedAttributePattern, (match) {
      final url = match.group(3)!;
      final quote = match.group(2);
      final rewrittenUrl = _rewriteReference(url, pageUrl, proxyUrlFor);
      return ' ${match.group(1)}=$quote$rewrittenUrl$quote';
    });
    rewritten = rewritten.replaceAllMapped(_srcsetPattern, (match) {
      return ' srcset=${match.group(1)}${_rewriteSrcset(match.group(2)!, pageUrl, proxyUrlFor)}${match.group(1)}';
    });
    return rewriteCss(rewritten, pageUrl, proxyUrlFor: proxyUrlFor);
  }

  String rewriteCss(
    String css,
    Uri pageUrl, {
    required Uri? Function(Uri target) proxyUrlFor,
  }) {
    return css.replaceAllMapped(_cssUrlPattern, (match) {
      final quote = match.group(1) ?? '';
      final url = match.group(2)!;
      return 'url($quote${_rewriteReference(url, pageUrl, proxyUrlFor)}$quote)';
    });
  }

  String _rewriteSrcset(
    String value,
    Uri pageUrl,
    Uri? Function(Uri target) proxyUrlFor,
  ) {
    return value
        .split(',')
        .map((part) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) return trimmed;
          final separator = trimmed.indexOf(' ');
          if (separator == -1) {
            return _rewriteReference(trimmed, pageUrl, proxyUrlFor);
          }
          return '${_rewriteReference(trimmed.substring(0, separator), pageUrl, proxyUrlFor)}'
              '${trimmed.substring(separator)}';
        })
        .join(', ');
  }

  String _rewriteReference(
    String raw,
    Uri pageUrl,
    Uri? Function(Uri target) proxyUrlFor,
  ) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || _shouldLeave(trimmed)) return raw;
    if (_isAlreadyLoopback(trimmed)) return raw;
    if (!_isAbsoluteOrProtocolRelative(trimmed)) {
      return raw;
    }
    final resolved = pageUrl.resolve(trimmed);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return raw;
    if (_sameOrigin(resolved, pageUrl)) {
      return _pathQueryFragment(resolved);
    }
    return proxyUrlFor(resolved)?.toString() ?? raw;
  }

  Uri? _resolveCrossOriginHttp(String raw, Uri pageUrl) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || _shouldLeave(trimmed)) return null;
    if (_isAlreadyLoopback(trimmed)) return null;
    if (!_isAbsoluteOrProtocolRelative(trimmed)) return null;
    final resolved = pageUrl.resolve(trimmed);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    if (_sameOrigin(resolved, pageUrl)) return null;
    return resolved;
  }

  bool _shouldLeave(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('#') ||
        lower.startsWith('data:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('tel:');
  }

  bool _isAbsoluteOrProtocolRelative(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('//');
  }

  bool _isAlreadyLoopback(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.host.isEmpty) return false;
    final host = parsed.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost';
  }

  static final RegExp _quotedAttributePattern = RegExp(
    r'''\s(href|src|action|poster|formaction|data-src|data-href)\s*=\s*(["'])(.*?)\2''',
    caseSensitive: false,
    dotAll: false,
  );
  static final RegExp _srcsetPattern = RegExp(
    r'''\ssrcset\s*=\s*(["'])(.*?)\1''',
    caseSensitive: false,
    dotAll: false,
  );
  static final RegExp _cssUrlPattern = RegExp(
    r'''url\(\s*(["']?)([^)"']+)\1\s*\)''',
    caseSensitive: false,
  );
}

/// Loopback reverse proxy that fetches destinations through [BrowserPinnedHttpClient].
///
/// Each upstream origin (`scheme|host|port`) gets its own loopback port so
/// pages from different sites are not same-origin with each other in the
/// WebView.
class BrowserMediationProxy {
  BrowserMediationProxy({
    required BrowserPinnedHttpClient httpClient,
    Future<HttpServer> Function(InternetAddress address, int port)? bind,
  }) : _httpClient = httpClient,
       _bind = bind ?? ((address, port) => HttpServer.bind(address, port));

  final BrowserPinnedHttpClient _httpClient;
  final Future<HttpServer> Function(InternetAddress address, int port) _bind;
  final Map<String, _OriginSlot> _slots = {};
  final Map<int, _OriginSlot> _slotsByPort = {};
  final Map<String, Future<_OriginSlot>> _pendingSlots = {};
  bool _stopped = false;

  bool get isStopped => _stopped;

  /// Builds a CSP that allows `'self'` plus only the extra loopback origins
  /// actually rewritten into the document. Never uses `http://127.0.0.1:*`.
  static String contentSecurityPolicy([
    Iterable<Uri> extraProxyOrigins = const [],
  ]) {
    final extras = extraProxyOrigins
        .map(_originLiteral)
        .where((origin) => origin.isNotEmpty)
        .toSet()
        .join(' ');
    final extra = extras.isEmpty ? '' : ' $extras';
    return "default-src 'self'$extra; "
        "script-src 'self' 'unsafe-inline' 'unsafe-eval'$extra; "
        "style-src 'self' 'unsafe-inline'$extra; "
        "img-src 'self' data: blob:$extra; "
        "font-src 'self' data:$extra; "
        "connect-src 'self'$extra; "
        "frame-src 'self'$extra; "
        "worker-src 'none'; "
        "object-src 'none'; "
        "base-uri 'self'; "
        "form-action 'self'$extra";
  }

  Future<Uri> proxyUrlFor(Uri target) async {
    _assertNotStopped();
    _assertSafeToMap(target);
    final slot = await _ensureSlot(target);
    return slot.toProxyUrl(target);
  }

  Uri? proxyUrlForSync(Uri target) {
    final slot = _slots[_originKey(target)];
    if (slot == null) return null;
    return slot.toProxyUrl(target);
  }

  Uri? targetFromProxyUrl(Uri url) {
    return _slotForProxyUrl(url)?.toUpstream(url);
  }

  bool isProxyUrl(Uri url) => _slotForProxyUrl(url) != null;

  Future<void> stop() async {
    _stopped = true;
    final slots = List<_OriginSlot>.from(_slots.values);
    _slots.clear();
    _slotsByPort.clear();
    _pendingSlots.clear();
    for (final slot in slots) {
      await slot.server.close(force: true);
    }
  }

  Future<_OriginSlot> _ensureSlot(Uri target) async {
    final key = _originKey(target);
    final existing = _slots[key];
    if (existing != null) return existing;
    final pending = _pendingSlots[key];
    if (pending != null) return pending;
    final future = _bindSlot(target, key);
    _pendingSlots[key] = future;
    try {
      return await future;
    } finally {
      _pendingSlots.remove(key);
    }
  }

  Future<_OriginSlot> _bindSlot(Uri target, String key) async {
    _assertNotStopped();
    final server = await _bind(InternetAddress.loopbackIPv4, 0);
    if (_stopped) {
      await server.close(force: true);
      throw StateError('BrowserMediationProxy has been stopped.');
    }
    final slot = _OriginSlot(
      key: key,
      upstreamOrigin: _originOf(target),
      server: server,
    );
    _slots[key] = slot;
    _slotsByPort[server.port] = slot;
    unawaited(_serve(slot));
    return slot;
  }

  Future<void> _serve(_OriginSlot slot) async {
    try {
      await for (final request in slot.server) {
        unawaited(_dispatch(slot, request));
      }
    } catch (_) {
      // The server is closed during [stop].
    }
  }

  Future<void> _dispatch(_OriginSlot slot, HttpRequest request) async {
    try {
      await _handle(slot, request);
    } catch (_) {
      try {
        _writePlain(request.response, HttpStatus.badGateway, 'Proxy error');
      } catch (_) {}
    }
  }

  Future<void> _handle(_OriginSlot slot, HttpRequest request) async {
    if (_stopped || !_slots.containsKey(slot.key)) {
      _writePlain(request.response, HttpStatus.serviceUnavailable, 'Stopped');
      return;
    }
    final target = slot.toUpstream(request.uri);
    try {
      _httpClient.destinationPolicy.validateUri(target);
      await _httpClient.approve(target);
    } on EgressPolicyException catch (error) {
      _writePlain(request.response, HttpStatus.forbidden, error.message);
      return;
    }

    final forwardedHeaders = <String, String>{};
    request.headers.forEach((name, values) {
      if (values.isEmpty) return;
      final lower = name.toLowerCase();
      if (_blockedRequestHeaders.contains(lower)) return;
      forwardedHeaders[lower] = values.join(', ');
    });
    if (!forwardedHeaders.containsKey('user-agent')) {
      forwardedHeaders['user-agent'] = _defaultUserAgent;
    }

    final mappedOrigin = _mapIncomingOrigin(forwardedHeaders.remove('origin'));
    final mappedReferer = _mapIncomingReferer(
      forwardedHeaders.remove('referer'),
    );
    if (mappedOrigin != null) {
      forwardedHeaders['origin'] = mappedOrigin.origin;
    }
    if (mappedReferer != null) {
      forwardedHeaders['referer'] = mappedReferer.toString();
    }

    final body = await _readRequestBody(request);
    final BrowserPinnedHttpResponse upstream;
    try {
      upstream = await _httpClient.send(
        method: request.method,
        uri: target,
        headers: forwardedHeaders,
        body: body,
        requestSiteOrigin: mappedOrigin ?? mappedReferer,
        initiatorSentOriginHeader: mappedOrigin != null,
      );
    } on EgressPolicyException catch (error) {
      _writePlain(request.response, HttpStatus.forbidden, error.message);
      return;
    } catch (_) {
      _writePlain(
        request.response,
        HttpStatus.badGateway,
        'The destination could not be loaded.',
      );
      return;
    }

    final response = request.response;
    response.statusCode = upstream.statusCode;
    var bodyBytes = upstream.body;
    final contentType = upstream.contentType ?? '';
    final extraOrigins = <Uri>{};
    final rewrittenLocation = await _rewriteLocation(
      upstream.location,
      target,
      extraOrigins,
    );
    if (rewrittenLocation != null) {
      response.headers.set(HttpHeaders.locationHeader, rewrittenLocation);
    }
    if (_isHtml(contentType)) {
      final charset = _charsetOf(contentType);
      final html = charset.decode(bodyBytes);
      bodyBytes = Uint8List.fromList(
        charset.encode(
          await _rewriteDocument(html, target, extraOrigins, isCss: false),
        ),
      );
      response.headers.contentType = ContentType(
        'text',
        'html',
        charset: charset.name,
      );
    } else if (_isCss(contentType)) {
      final charset = _charsetOf(contentType);
      final css = charset.decode(bodyBytes);
      bodyBytes = Uint8List.fromList(
        charset.encode(
          await _rewriteDocument(css, target, extraOrigins, isCss: true),
        ),
      );
      response.headers.contentType = ContentType(
        'text',
        'css',
        charset: charset.name,
      );
    } else if (contentType.isNotEmpty) {
      response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }

    response.headers.set(
      'Content-Security-Policy',
      contentSecurityPolicy(extraOrigins),
    );
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('x-content-type-options', 'nosniff');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.contentLength = bodyBytes.length;
    if (request.method != 'HEAD') {
      response.add(bodyBytes);
    }
    await response.close();
  }

  Future<String> _rewriteDocument(
    String content,
    Uri pageUrl,
    Set<Uri> extraOrigins, {
    required bool isCss,
  }) async {
    const rewriter = BrowserProxiedContentRewriter();
    final needed = rewriter.collectCrossOriginTargets(content, pageUrl);
    final cache = <Uri, Uri>{};
    for (final uri in needed) {
      try {
        final proxied = await proxyUrlFor(uri);
        cache[uri] = proxied;
        extraOrigins.add(_originOnly(proxied));
      } on EgressPolicyException {
        // Leave the original reference; CSP and resource policy still deny it.
      }
    }
    Uri? lookup(Uri target) => cache[target];
    return isCss
        ? rewriter.rewriteCss(content, pageUrl, proxyUrlFor: lookup)
        : rewriter.rewriteHtml(content, pageUrl, proxyUrlFor: lookup);
  }

  Future<String?> _rewriteLocation(
    String? location,
    Uri pageUrl,
    Set<Uri> extraOrigins,
  ) async {
    if (location == null || location.trim().isEmpty) return null;
    final resolved = pageUrl.resolve(location.trim());
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    if (_sameOrigin(resolved, pageUrl)) {
      return _pathQueryFragment(resolved);
    }
    try {
      final proxied = await proxyUrlFor(resolved);
      extraOrigins.add(_originOnly(proxied));
      return proxied.toString();
    } on EgressPolicyException {
      return null;
    }
  }

  Uri? _mapIncomingOrigin(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) return null;
    final upstream = targetFromProxyUrl(parsed);
    if (upstream == null) return null;
    return _originOf(upstream);
  }

  Uri? _mapIncomingReferer(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) return null;
    return targetFromProxyUrl(parsed);
  }

  Future<List<int>?> _readRequestBody(HttpRequest request) async {
    if (request.method == 'GET' || request.method == 'HEAD') return null;
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in request) {
      received += chunk.length;
      if (received > _maxRequestBodyBytes) {
        throw const EgressPolicyException(
          'request_too_large',
          'The browser request exceeded the configured byte limit.',
        );
      }
      builder.add(chunk);
    }
    if (received == 0) return null;
    return builder.takeBytes();
  }

  void _writePlain(HttpResponse response, int status, String message) {
    try {
      final bytes = utf8.encode(message);
      response.statusCode = status;
      response.headers.contentType = ContentType.text;
      response.headers.set('Content-Security-Policy', contentSecurityPolicy());
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.contentLength = bytes.length;
      response.add(bytes);
      unawaited(response.close());
    } catch (_) {}
  }

  void _assertSafeToMap(Uri target) {
    _httpClient.destinationPolicy.validateUri(target);
    final literal = InternetAddress.tryParse(target.host);
    if (literal != null) {
      _httpClient.destinationPolicy.approveResolvedAddresses(target, [literal]);
    }
  }

  void _assertNotStopped() {
    if (_stopped) {
      throw StateError('BrowserMediationProxy has been stopped.');
    }
  }

  _OriginSlot? _slotForProxyUrl(Uri url) {
    if (url.scheme.toLowerCase() != 'http') return null;
    final host = url.host.toLowerCase();
    if (host != '127.0.0.1' && host != 'localhost') return null;
    if (!url.hasPort) return null;
    return _slotsByPort[url.port];
  }

  bool _isHtml(String contentType) {
    final lower = contentType.toLowerCase();
    return lower.contains('text/html') || lower.contains('application/xhtml');
  }

  bool _isCss(String contentType) =>
      contentType.toLowerCase().contains('text/css');

  Encoding _charsetOf(String contentType) {
    try {
      final charset = ContentType.parse(contentType).charset;
      if (charset == null) return utf8;
      return Encoding.getByName(charset) ?? utf8;
    } catch (_) {
      return utf8;
    }
  }

  static String _originKey(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
    return '$scheme|$host|$port';
  }

  static Uri _originOf(Uri uri) {
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  static Uri _originOnly(Uri uri) {
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
  }

  static String _originLiteral(Uri uri) {
    if (uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }

  static const int _maxRequestBodyBytes = 1024 * 1024;
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
  static const Set<String> _blockedRequestHeaders = {
    HttpHeaders.hostHeader,
    HttpHeaders.connectionHeader,
    'keep-alive',
    HttpHeaders.cookieHeader,
    HttpHeaders.contentLengthHeader,
    HttpHeaders.transferEncodingHeader,
    HttpHeaders.upgradeHeader,
    'proxy-authorization',
  };
}

class _OriginSlot {
  _OriginSlot({
    required this.key,
    required this.upstreamOrigin,
    required this.server,
  });

  final String key;
  final Uri upstreamOrigin;
  final HttpServer server;

  Uri toProxyUrl(Uri target) {
    return Uri(
      scheme: 'http',
      host: server.address.address,
      port: server.port,
      path: target.path.isEmpty ? '/' : target.path,
      query: target.hasQuery ? target.query : null,
      fragment: target.hasFragment ? target.fragment : null,
    );
  }

  Uri toUpstream(Uri proxyUrl) {
    return Uri(
      scheme: upstreamOrigin.scheme,
      host: upstreamOrigin.host,
      port: upstreamOrigin.hasPort ? upstreamOrigin.port : null,
      path: proxyUrl.path.isEmpty ? '/' : proxyUrl.path,
      query: proxyUrl.hasQuery ? proxyUrl.query : null,
      fragment: proxyUrl.hasFragment ? proxyUrl.fragment : null,
    );
  }
}

bool _sameOrigin(Uri first, Uri second) {
  return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      _effectivePort(first) == _effectivePort(second);
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}

String _pathQueryFragment(Uri uri) {
  final buffer = StringBuffer(uri.path.isEmpty ? '/' : uri.path);
  if (uri.hasQuery) {
    buffer
      ..write('?')
      ..write(uri.query);
  }
  if (uri.hasFragment) {
    buffer
      ..write('#')
      ..write(uri.fragment);
  }
  return buffer.toString();
}
