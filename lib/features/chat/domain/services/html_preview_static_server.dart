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

  Future<Uri> start({
    required String projectRoot,
    required String entryRelativePath,
  }) async {
    if (_server != null) {
      await stop();
    }
    final root = Directory(projectRoot).absolute;
    if (!root.existsSync()) {
      throw FileSystemException('Project root does not exist', root.path);
    }
    final canonicalRoot = Directory(root.resolveSymbolicLinksSync()).path;
    final normalizedEntry = _normalizeRelativePath(entryRelativePath);
    if (normalizedEntry == null ||
        !isAllowedPreviewAsset(
          normalizedEntry,
          entryRelativePath: normalizedEntry,
        )) {
      throw FileSystemException(
        'HTML preview entry is not a readable web asset',
        entryRelativePath,
      );
    }
    final entryCandidate = File.fromUri(
      Directory(canonicalRoot).uri.resolve(normalizedEntry),
    );
    final File entryFile;
    try {
      entryFile = File(entryCandidate.resolveSymbolicLinksSync());
    } on FileSystemException {
      throw FileSystemException(
        'HTML preview entry is not a readable web asset',
        entryRelativePath,
      );
    }
    if (!entryFile.existsSync() ||
        !DartProjectPath.isInsideRoot(entryFile.path, canonicalRoot)) {
      throw FileSystemException(
        'HTML preview entry is not a readable web asset',
        entryRelativePath,
      );
    }
    final previewRoot = Directory(
      entryFile.parent.resolveSymbolicLinksSync(),
    ).path;
    final previewEntryName = normalizedEntry.substring(
      normalizedEntry.lastIndexOf('/') + 1,
    );
    final server = await _bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _serving = _serve(server, canonicalRoot, previewRoot, previewEntryName);
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

  Future<void> _serve(
    HttpServer server,
    String projectRoot,
    String previewRoot,
    String entryRelativePath,
  ) async {
    await for (final request in server) {
      try {
        await _handle(request, projectRoot, previewRoot, entryRelativePath);
      } catch (_) {
        _send(request.response, HttpStatus.internalServerError, 'text/plain');
      }
    }
  }

  Future<void> _handle(
    HttpRequest request,
    String projectRoot,
    String previewRoot,
    String entryRelativePath,
  ) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      _send(response, HttpStatus.methodNotAllowed, 'text/plain');
      return;
    }

    final relative = _requestedRelativePath(
      request.uri,
      entryRelativePath: entryRelativePath,
    );
    if (relative == null ||
        !isAllowedPreviewAsset(
          relative,
          entryRelativePath: entryRelativePath,
        )) {
      _send(response, HttpStatus.notFound, 'text/plain');
      return;
    }

    final file = _resolveReadableFile(projectRoot, previewRoot, relative);
    if (file == null) {
      _send(response, HttpStatus.notFound, 'text/plain');
      return;
    }

    final mime = mimeTypeFor(file.path);
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, mime);
    _setSecurityHeaders(response);
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  /// Root `/` maps to the selected entry. Other paths stay project-relative.
  String? _requestedRelativePath(Uri uri, {required String entryRelativePath}) {
    var path = uri.path;
    if (path.isEmpty || path == '/') return entryRelativePath;
    if (path.startsWith('/')) path = path.substring(1);
    try {
      path = Uri.decodeComponent(path);
    } on FormatException {
      return null;
    }
    return _normalizeRelativePath(path);
  }

  static String? _normalizeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.contains('\u0000') || normalized.startsWith('/')) {
      return null;
    }
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty || parts.any((part) => part == '..')) return null;
    return parts.join('/');
  }

  /// Allows only browser-consumable assets inside the selected entry directory.
  static bool isAllowedPreviewAsset(
    String relativePath, {
    required String entryRelativePath,
  }) {
    final normalized = _normalizeRelativePath(relativePath);
    final entry = _normalizeRelativePath(entryRelativePath);
    if (normalized == null || entry == null) return false;
    if (isBlockedRelativePath(normalized)) return false;
    final slash = entry.lastIndexOf('/');
    final entryDirectory = slash < 0 ? '' : entry.substring(0, slash + 1);
    if (entryDirectory.isNotEmpty && !normalized.startsWith(entryDirectory)) {
      return false;
    }
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _previewAssetExtensions.contains(
      name.substring(dot + 1).toLowerCase(),
    );
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

  static const _previewAssetExtensions = {
    'html',
    'htm',
    'css',
    'js',
    'mjs',
    'svg',
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'avif',
    'ico',
    'wasm',
    'woff',
    'woff2',
    'ttf',
    'otf',
    'mp3',
    'mp4',
    'webm',
    'ogg',
    'wav',
  };

  File? _resolveReadableFile(
    String projectRoot,
    String previewRoot,
    String relativePath,
  ) {
    final candidate = File.fromUri(
      Directory(previewRoot).uri.resolve(relativePath),
    );
    File resolved;
    try {
      resolved = File(candidate.resolveSymbolicLinksSync());
    } on FileSystemException {
      return null;
    }
    if (!DartProjectPath.isInsideRoot(resolved.path, projectRoot) ||
        !DartProjectPath.isInsideRoot(resolved.path, previewRoot)) {
      return null;
    }
    if (!resolved.existsSync()) return null;
    return resolved;
  }

  void _send(HttpResponse response, int status, String contentType) {
    response.statusCode = status;
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    _setSecurityHeaders(response);
    unawaited(response.close());
  }

  void _setSecurityHeaders(HttpResponse response) {
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'none'; script-src 'self' 'unsafe-inline'; "
          "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
          "font-src 'self' data:; media-src 'self' blob:; "
          "connect-src 'none'; form-action 'none'; frame-src 'none'; "
          "frame-ancestors 'none'; object-src 'none'; worker-src 'none'; "
          "manifest-src 'none'; base-uri 'none'",
    );
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('X-DNS-Prefetch-Control', 'off');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
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
      'avif' => 'image/avif',
      'ico' => 'image/x-icon',
      'wasm' => 'application/wasm',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      _ => 'application/octet-stream',
    };
  }
}
