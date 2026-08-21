import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'media_host_listen_policy.dart';

/// One file the server will hand out, and the terms it will hand it out on.
class _MediaHandle {
  _MediaHandle({
    required this.file,
    required this.mimeType,
    required this.expiresAt,
    required this.remainingFetches,
  });

  final File file;
  final String mimeType;
  final DateTime expiresAt;
  int remainingFetches;

  bool isExpiredAt(DateTime now) =>
      remainingFetches <= 0 || !now.isBefore(expiresAt);
}

/// A registered file plus the URL to hand to the model endpoint.
class MediaHostTicket {
  const MediaHostTicket({required this.url, required this.token});

  final Uri url;
  final String token;
}

/// Serves a single attachment over HTTP just long enough for one request.
///
/// The model endpoint fetches the bytes itself instead of receiving a
/// multi-megabyte base64 blob inline. Nothing is browsable: there is no
/// directory listing and no path resolution, only a map from an unguessable
/// token to one registered file, so there is no traversal surface to defend.
/// Handles expire on a timer and on a fetch count, and the listener shuts down
/// as soon as the last handle is gone.
class MediaHostService {
  MediaHostService({
    MediaHostListenPolicy? policy,
    Future<HttpServer> Function(InternetAddress address, int port)? bind,
    Random? random,
    DateTime Function()? clock,
  }) : _policy = policy ?? const MediaHostListenPolicy(),
       _bind = bind ?? ((address, port) => HttpServer.bind(address, port)),
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  /// How long a registered file stays reachable.
  static const Duration ttl = Duration(seconds: 120);

  /// Enough for the request plus one retry, and no more.
  static const int maxFetches = 2;

  final MediaHostListenPolicy _policy;
  final Future<HttpServer> Function(InternetAddress address, int port) _bind;
  final Random _random;
  final DateTime Function() _clock;

  final Map<String, _MediaHandle> _handles = <String, _MediaHandle>{};

  /// Tokens that were served at least once, kept after the handle is gone so
  /// [wasFetched] still answers for a handle that has since been swept.
  final Set<String> _fetchedTokens = <String>{};

  HttpServer? _server;
  Future<void>? _serving;
  String? _advertiseHost;

  bool get isRunning => _server != null;

  /// Origin such as `http://192.168.1.20:49152`. Null while stopped.
  Uri? get origin {
    final server = _server;
    final host = _advertiseHost;
    if (server == null || host == null) return null;
    return Uri(scheme: 'http', host: host, port: server.port);
  }

  /// Publishes [file] so that [endpoint] can fetch it.
  ///
  /// Returns null when this device has no address [endpoint] could reach, which
  /// is the caller's signal to inline the payload instead.
  Future<MediaHostTicket?> publish({
    required File file,
    required String mimeType,
    required Uri endpoint,
  }) async {
    if (!file.existsSync()) {
      throw FileSystemException('Media file does not exist', file.path);
    }
    final binding = await _policy.resolve(endpoint: endpoint);
    if (binding == null) {
      return null;
    }
    await _ensureStarted(binding);
    final token = _newToken();
    _handles[token] = _MediaHandle(
      file: file,
      mimeType: mimeType,
      expiresAt: _clock().add(ttl),
      remainingFetches: maxFetches,
    );
    return MediaHostTicket(url: origin!.replace(path: '/v/$token'), token: token);
  }

  /// Whether the endpoint ever came and got the bytes for [token].
  ///
  /// A handle that expires untouched is the signal that the endpoint could not
  /// reach this device, which is what tells the caller to inline instead.
  bool wasFetched(String token) {
    final handle = _handles[token];
    // Gone means it was either consumed or swept after a fetch drained it.
    if (handle == null) return _fetchedTokens.contains(token);
    return handle.remainingFetches < maxFetches;
  }

  /// Drops [token] immediately; safe to call for an already-expired handle.
  Future<void> revoke(String token) async {
    _handles.remove(token);
    _fetchedTokens.remove(token);
    await _stopIfIdle();
  }

  Future<void> stop() async {
    final server = _server;
    _handles.clear();
    if (server == null) return;
    _server = null;
    _advertiseHost = null;
    await server.close(force: true);
    await _serving;
    _serving = null;
  }

  Future<void> _ensureStarted(MediaHostBinding binding) async {
    final server = _server;
    if (server != null) {
      // A previous publish may have bound loopback for a local endpoint; a LAN
      // endpoint now needs a reachable address, so rebind rather than hand out
      // a URL the endpoint cannot resolve.
      if (_advertiseHost == binding.advertiseHost) {
        return;
      }
      if (_handles.isNotEmpty) {
        throw StateError(
          'Media host is serving $_advertiseHost and cannot move to '
          '${binding.advertiseHost} while handles are live',
        );
      }
      await stop();
    }
    final bound = await _bind(binding.bindAddress, 0);
    _server = bound;
    _advertiseHost = binding.advertiseHost;
    _serving = _serve(bound);
  }

  Future<void> _stopIfIdle() async {
    if (_handles.isEmpty && _server != null) {
      await stop();
    }
  }

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request);
      } catch (_) {
        // The endpoint only needs to know the fetch failed; anything more
        // detailed would describe files it is not entitled to know about.
        _reject(request.response, HttpStatus.internalServerError);
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      _reject(response, HttpStatus.methodNotAllowed);
      return;
    }

    final handle = _lookup(request.uri);
    if (handle == null) {
      // Unknown, expired and exhausted tokens are indistinguishable on purpose.
      _reject(response, HttpStatus.notFound);
      return;
    }

    final length = await handle.file.length();
    final range = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      length,
    );
    if (range == null && request.headers.value(HttpHeaders.rangeHeader) != null) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      await response.close();
      return;
    }

    response.headers.set(HttpHeaders.contentTypeHeader, handle.mimeType);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    if (range == null) {
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = length;
    } else {
      response.statusCode = HttpStatus.partialContent;
      response.headers.contentLength = range.end - range.start + 1;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$length',
      );
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    handle.remainingFetches -= 1;
    _fetchedTokens.add(_tokenOf(request.uri)!);
    final stream = range == null
        ? handle.file.openRead()
        : handle.file.openRead(range.start, range.end + 1);
    await response.addStream(stream);
    await response.close();
    if (handle.remainingFetches <= 0) {
      // Exhausted: drop it so the listener can go away once nothing is live.
      // The token stays in _fetchedTokens so wasFetched still answers.
      _handles.remove(_tokenOf(request.uri));
      await _stopIfIdle();
    }
  }

  static String? _tokenOf(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 2 || segments.first != 'v') {
      return null;
    }
    // Pickers and proxies like a file extension; it is decoration, not identity.
    return segments[1].split('.').first;
  }

  _MediaHandle? _lookup(Uri uri) {
    final token = _tokenOf(uri);
    if (token == null) return null;
    final handle = _handles[token];
    if (handle == null) {
      return null;
    }
    if (handle.isExpiredAt(_clock())) {
      _handles.remove(token);
      return null;
    }
    return handle;
  }

  static ({int start, int end})? _parseRange(String? header, int length) {
    if (header == null || length == 0) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final rawStart = match.group(1) ?? '';
    final rawEnd = match.group(2) ?? '';
    if (rawStart.isEmpty && rawEnd.isEmpty) return null;
    int start;
    int end;
    if (rawStart.isEmpty) {
      final suffix = int.parse(rawEnd);
      if (suffix == 0) return null;
      start = suffix >= length ? 0 : length - suffix;
      end = length - 1;
    } else {
      start = int.parse(rawStart);
      end = rawEnd.isEmpty ? length - 1 : int.parse(rawEnd);
    }
    if (start > end || start >= length) return null;
    if (end >= length) end = length - 1;
    return (start: start, end: end);
  }

  static void _reject(HttpResponse response, int statusCode) {
    response.statusCode = statusCode;
    response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
    response.close();
  }
}
