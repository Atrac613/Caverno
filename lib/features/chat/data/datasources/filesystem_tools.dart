import 'dart:convert';
import 'dart:io';

class FilesystemTools {
  FilesystemTools._();

  static const int _maxReadChars = 120000;
  static const int _maxEntries = 300;
  static const int _maxSearchResults = 200;
  static const int _maxFileBytesForSearch = 1024 * 1024;

  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  static String? resolvePath(String? rawPath, {String? defaultRoot}) {
    final trimmed = rawPath?.trim() ?? '';
    final normalizedDefaultRoot = defaultRoot?.trim();

    if (trimmed.isEmpty) {
      if (normalizedDefaultRoot == null || normalizedDefaultRoot.isEmpty) {
        return null;
      }
      return Directory(normalizedDefaultRoot).absolute.path;
    }

    if (_isAbsolutePath(trimmed)) {
      return File(trimmed).absolute.path;
    }

    if (normalizedDefaultRoot == null || normalizedDefaultRoot.isEmpty) {
      return null;
    }

    return File.fromUri(
      Directory(normalizedDefaultRoot).uri.resolve(trimmed),
    ).absolute.path;
  }

  static Future<String> listDirectory({
    required String path,
    bool recursive = false,
    int maxEntries = _maxEntries,
  }) async {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return jsonEncode({'error': 'Directory does not exist: $path'});
    }

    final entities = await directory
        .list(recursive: recursive, followLinks: false)
        .take(maxEntries)
        .toList();
    entities.sort((a, b) => a.path.compareTo(b.path));

    final lines = <String>[];
    for (final entity in entities) {
      final type = switch (await FileSystemEntity.type(entity.path)) {
        FileSystemEntityType.directory => 'dir',
        FileSystemEntityType.file => 'file',
        FileSystemEntityType.link => 'link',
        FileSystemEntityType.notFound => 'missing',
        _ => 'unknown',
      };
      final relativePath = _relativePath(entity.path, directory.path);
      if (type == 'file') {
        final size = await File(entity.path).length();
        lines.add('[$type] $relativePath (${_formatBytes(size)})');
      } else {
        lines.add('[$type] $relativePath');
      }
    }

    return jsonEncode({
      'path': directory.absolute.path,
      'recursive': recursive,
      'entry_count': lines.length,
      'entries': lines,
      if (lines.length >= maxEntries) 'truncated': true,
    });
  }

  static Future<String> readFile({
    required String path,
    int maxChars = _maxReadChars,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      return jsonEncode({'error': 'File does not exist: $path'});
    }

    try {
      final rawBytes = await file.readAsBytes();
      final content = utf8.decode(rawBytes, allowMalformed: false);
      final truncated = content.length > maxChars;
      return jsonEncode({
        'path': file.absolute.path,
        'content': truncated ? content.substring(0, maxChars) : content,
        'size_bytes': rawBytes.length,
        if (truncated) 'truncated': true,
      });
    } on FormatException {
      return jsonEncode({
        'error':
            'File is not valid UTF-8 text. Binary files are not supported.',
        'path': file.absolute.path,
      });
    }
  }

  static Future<String> writeFile({
    required String path,
    required String content,
    bool createParents = true,
  }) async {
    final file = File(path);
    final existedBefore = file.existsSync();
    if (createParents) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(content);
    return jsonEncode({
      'path': file.absolute.path,
      'bytes_written': utf8.encode(content).length,
      'created': !existedBefore,
    });
  }

  static Future<String> editFile({
    required String path,
    required String oldText,
    required String newText,
    bool replaceAll = false,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      return jsonEncode({'error': 'File does not exist: $path'});
    }
    if (oldText.isEmpty) {
      return jsonEncode({'error': 'old_text must not be empty'});
    }

    final content = await file.readAsString();
    final occurrences = _countOccurrences(content, oldText);
    if (occurrences == 0) {
      return jsonEncode({
        'error': 'old_text was not found in the target file',
        'path': file.absolute.path,
      });
    }
    if (!replaceAll && occurrences > 1) {
      return jsonEncode({
        'error':
            'old_text matched multiple locations. Set replace_all=true or make the target text more specific.',
        'path': file.absolute.path,
        'occurrences': occurrences,
      });
    }

    final updatedContent = replaceAll
        ? content.replaceAll(oldText, newText)
        : content.replaceFirst(oldText, newText);
    await file.writeAsString(updatedContent);

    return jsonEncode({
      'path': file.absolute.path,
      'replacements': replaceAll ? occurrences : 1,
      'replace_all': replaceAll,
    });
  }

  static Future<String> findFiles({
    required String path,
    required String pattern,
    bool recursive = true,
    int maxResults = _maxSearchResults,
  }) async {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return jsonEncode({'error': 'Directory does not exist: $path'});
    }
    if (pattern.trim().isEmpty) {
      return jsonEncode({'error': 'pattern is required'});
    }

    final matcher = _wildcardToRegExp(pattern.trim());
    final matches = <String>[];

    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relativePath = _relativePath(entity.path, directory.path);
      final fileName = entity.uri.pathSegments.isEmpty
          ? relativePath
          : entity.uri.pathSegments.last;
      if (matcher.hasMatch(relativePath) || matcher.hasMatch(fileName)) {
        matches.add(relativePath);
        if (matches.length >= maxResults) break;
      }
    }

    matches.sort();
    return jsonEncode({
      'path': directory.absolute.path,
      'pattern': pattern,
      'matches': matches,
      'match_count': matches.length,
      if (matches.length >= maxResults) 'truncated': true,
    });
  }

  static Future<String> searchFiles({
    required String path,
    required String query,
    String? filePattern,
    bool caseSensitive = false,
    int maxResults = _maxSearchResults,
  }) async {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return jsonEncode({'error': 'Directory does not exist: $path'});
    }
    if (query.trim().isEmpty) {
      return jsonEncode({'error': 'query is required'});
    }

    final normalizedQuery = caseSensitive ? query : query.toLowerCase();
    final fileMatcher = filePattern == null || filePattern.trim().isEmpty
        ? null
        : _wildcardToRegExp(filePattern.trim());

    final matches = <String>[];
    var scannedFiles = 0;

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relativePath = _relativePath(entity.path, directory.path);
      if (fileMatcher != null &&
          !fileMatcher.hasMatch(relativePath) &&
          !fileMatcher.hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }

      final length = await entity.length();
      if (length > _maxFileBytesForSearch) continue;

      String content;
      try {
        content = await entity.readAsString();
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }

      scannedFiles += 1;
      final lines = const LineSplitter().convert(content);
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        final haystack = caseSensitive ? line : line.toLowerCase();
        if (haystack.contains(normalizedQuery)) {
          matches.add('$relativePath:${index + 1}: $line');
          if (matches.length >= maxResults) {
            return jsonEncode({
              'path': directory.absolute.path,
              'query': query,
              'matches': matches,
              'match_count': matches.length,
              'scanned_files': scannedFiles,
              'truncated': true,
            });
          }
        }
      }
    }

    return jsonEncode({
      'path': directory.absolute.path,
      'query': query,
      'matches': matches,
      'match_count': matches.length,
      'scanned_files': scannedFiles,
    });
  }

  static int _countOccurrences(String source, String target) {
    var count = 0;
    var start = 0;
    while (true) {
      final index = source.indexOf(target, start);
      if (index == -1) return count;
      count += 1;
      start = index + target.length;
    }
  }

  static bool _isAbsolutePath(String path) {
    return path.startsWith('/') ||
        path.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  static String _relativePath(String candidatePath, String basePath) {
    final absoluteCandidate = File(candidatePath).absolute.path;
    final absoluteBase = Directory(basePath).absolute.path;
    if (absoluteCandidate == absoluteBase) {
      return '.';
    }

    final prefix = absoluteBase.endsWith(Platform.pathSeparator)
        ? absoluteBase
        : '$absoluteBase${Platform.pathSeparator}';
    if (!absoluteCandidate.startsWith(prefix)) {
      return absoluteCandidate;
    }
    return absoluteCandidate.substring(prefix.length);
  }

  static RegExp _wildcardToRegExp(String pattern) {
    final buffer = StringBuffer('^');
    for (final rune in pattern.runes) {
      final char = String.fromCharCode(rune);
      if (char == '*') {
        buffer.write('.*');
      } else if (char == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
