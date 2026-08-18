import 'dart:async';
import 'dart:io';

import 'dart_project_tooling.dart';

/// Serves one project's files on loopback HTTP for the built-in browser.
///
/// Bound to 127.0.0.1 only. Requests that escape [projectRoot] receive 404,
/// including `..` traversal and symlink targets outside the root.
class HtmlPreviewStaticServer {
  HtmlPreviewStaticServer({
    Future<HttpServer> Function(InternetAddress address, int port)? bind,
  }) : _bind = bind ?? ((address, port) => HttpServer.bind(address, port));

  final Future<HttpServer> Function(InternetAddress address, int port) _bind;

  HttpServer? _server;
  Future<void>? _serving;

  /// Origin such as `http://127.0.0.1:49152`. Null while stopped.
  Uri? get origin {
    final server = _server;
    if (server == null) return null;
    return Uri(scheme: 'http', host: server.address.address, port: server.port);
  }

  bool get isRunning => _server != null;

  Future<Uri> start({required String projectRoot}) async {
    if (_server != null) {
      await stop();
    }
    final root = Directory(projectRoot).absolute;
    if (!root.existsSync()) {
      throw FileSystemException('Project root does not exist', root.path);
    }
    final canonicalRoot = Directory(root.resolveSymbolicLinksSync()).path;
    final server = await _bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _serving = _serve(server, canonicalRoot);
    return origin!;
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    await server.close(force: true);
    await _serving;
    _serving = null;
  }

  Future<void> _serve(HttpServer server, String projectRoot) async {
    await for (final request in server) {
      try {
        await _handle(request, projectRoot);
      } catch (_) {
        _send(request.response, HttpStatus.internalServerError, 'text/plain');
      }
    }
  }

  Future<void> _handle(HttpRequest request, String projectRoot) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      _send(response, HttpStatus.methodNotAllowed, 'text/plain');
      return;
    }

    final relative = _requestedRelativePath(request.uri);
    if (relative == null || isBlockedRelativePath(relative)) {
      _send(response, HttpStatus.notFound, 'text/plain');
      return;
    }

    final file = _resolveReadableFile(projectRoot, relative);
    if (file == null) {
      _send(response, HttpStatus.notFound, 'text/plain');
      return;
    }

    final mime = mimeTypeFor(file.path);
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, mime);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  /// Root `/` maps to `index.html`. Other paths stay relative to the project.
  String? _requestedRelativePath(Uri uri) {
    var path = uri.path;
    if (path.isEmpty || path == '/') return 'index.html';
    if (path.startsWith('/')) path = path.substring(1);
    try {
      path = Uri.decodeComponent(path);
    } on FormatException {
      return null;
    }
    if (path.contains('\u0000')) return null;
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty);
    if (parts.contains('..')) return null;
    return path;
  }

  /// Dotfiles, VCS metadata, dependency trees, and key material stay unpublished.
  static bool isBlockedRelativePath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.contains('\u0000')) return true;
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    for (final part in parts) {
      if (part == '..') return true;
      if (part == '.') continue;
      if (part.startsWith('.')) return true;
      if (_blockedDirectoryNames.contains(part.toLowerCase())) return true;
    }
    if (parts.isEmpty) return false;
    final name = parts.last.toLowerCase();
    if (_blockedFileNames.contains(name)) return true;
    return name.endsWith('.pem') ||
        name.endsWith('.key') ||
        name.endsWith('.p12') ||
        name.endsWith('.pfx');
  }

  static const _blockedDirectoryNames = {
    'node_modules',
    '.dart_tool',
    '.git',
    '.hg',
    '.svn',
  };

  static const _blockedFileNames = {
    'id_rsa',
    'id_dsa',
    'id_ecdsa',
    'id_ed25519',
    'credentials.json',
    'google-services.json',
    'serviceaccount.json',
    'service-account.json',
  };

  File? _resolveReadableFile(String projectRoot, String relativePath) {
    final candidate = File.fromUri(
      Directory(projectRoot).uri.resolve(relativePath),
    );
    File resolved;
    try {
      resolved = File(candidate.resolveSymbolicLinksSync());
    } on FileSystemException {
      if (!candidate.existsSync()) return null;
      resolved = candidate.absolute;
    }
    if (!DartProjectPath.isInsideRoot(resolved.path, projectRoot)) {
      return null;
    }
    if (!resolved.existsSync()) {
      // A directory URL such as `/src/` can still resolve to index.html.
      final asDirectory = Directory(resolved.path);
      if (asDirectory.existsSync()) {
        final nested = File.fromUri(asDirectory.uri.resolve('index.html'));
        if (nested.existsSync() &&
            DartProjectPath.isInsideRoot(nested.path, projectRoot)) {
          return nested;
        }
      }
      return null;
    }
    return resolved;
  }

  void _send(HttpResponse response, int status, String contentType) {
    response.statusCode = status;
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    unawaited(response.close());
  }

  static String mimeTypeFor(String path) {
    final name = path.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    return switch (ext) {
      'html' || 'htm' => 'text/html; charset=utf-8',
      'js' || 'mjs' => 'text/javascript; charset=utf-8',
      'css' => 'text/css; charset=utf-8',
      'json' => 'application/json; charset=utf-8',
      'svg' => 'image/svg+xml',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'wasm' => 'application/wasm',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'ttf' => 'font/ttf',
      'map' => 'application/json',
      'txt' => 'text/plain; charset=utf-8',
      _ => 'application/octet-stream',
    };
  }
}
