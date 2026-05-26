import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

final agentsMdLoaderProvider = Provider<AgentsMdLoader>((_) => AgentsMdLoader());

class _CacheEntry {
  const _CacheEntry({
    required this.sourcePath,
    required this.lastModified,
    required this.length,
    required this.content,
  });

  final String sourcePath;
  final DateTime lastModified;
  final int length;
  final String? content;
}

/// Loads AGENTS.md (and the higher-priority AGENTS.override.md) from a project
/// root and caches the result by mtime. The cache is keyed by the normalized
/// project root path; callers should pass the same root every time so cache
/// hits actually fire.
///
/// Reads are synchronous because the file is expected to be small (32 KiB
/// cap, per the AGENTS.md spec) and is fetched at system-prompt build time.
class AgentsMdLoader {
  static const int maxBytes = 32 * 1024;
  static const String fileName = 'AGENTS.md';
  static const String overrideFileName = 'AGENTS.override.md';
  static const String _truncationMarker =
      '\n\n[truncated: AGENTS.md exceeded 32 KiB cap]';

  final Map<String, _CacheEntry> _cache = {};

  String? loadForProject(String? rootPath) {
    final normalized = rootPath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    final overridePath = _joinRoot(normalized, overrideFileName);
    final primaryPath = _joinRoot(normalized, fileName);

    final overrideContent = _readIfPresent(normalized, overridePath);
    if (overrideContent != null) {
      return overrideContent;
    }
    return _readIfPresent(normalized, primaryPath);
  }

  static String _joinRoot(String rootPath, String basename) {
    final uri = Directory(rootPath).uri.resolve(basename);
    return File.fromUri(uri).absolute.path;
  }

  void invalidate(String? rootPath) {
    final normalized = rootPath?.trim();
    if (normalized == null || normalized.isEmpty) {
      _cache.clear();
      return;
    }
    _cache.remove(_cacheKey(normalized, fileName));
    _cache.remove(_cacheKey(normalized, overrideFileName));
  }

  String _basename(String path) {
    final separator = Platform.isWindows ? r'\' : '/';
    final index = path.lastIndexOf(separator);
    if (index < 0) return path;
    return path.substring(index + 1);
  }

  String? _readIfPresent(String rootPath, String filePath) {
    final file = File(filePath);
    FileStat stat;
    try {
      stat = file.statSync();
    } on FileSystemException catch (error) {
      appLog('[AgentsMd] stat failed for $filePath: ${error.message}');
      return null;
    }
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }

    final cacheKey = _cacheKey(rootPath, _basename(filePath));
    final cached = _cache[cacheKey];
    if (cached != null &&
        cached.sourcePath == filePath &&
        cached.lastModified == stat.modified &&
        cached.length == stat.size) {
      return cached.content;
    }

    String? content;
    try {
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) {
        content = null;
      } else if (bytes.length <= maxBytes) {
        content = utf8.decode(bytes, allowMalformed: true);
      } else {
        final head = utf8.decode(bytes.sublist(0, maxBytes), allowMalformed: true);
        content = '$head$_truncationMarker';
      }
    } on FileSystemException catch (error) {
      appLog('[AgentsMd] read failed for $filePath: ${error.message}');
      _cache[cacheKey] = _CacheEntry(
        sourcePath: filePath,
        lastModified: stat.modified,
        length: stat.size,
        content: null,
      );
      return null;
    }

    _cache[cacheKey] = _CacheEntry(
      sourcePath: filePath,
      lastModified: stat.modified,
      length: stat.size,
      content: content,
    );
    return content;
  }

  String _cacheKey(String rootPath, String basename) => '$rootPath::$basename';
}
