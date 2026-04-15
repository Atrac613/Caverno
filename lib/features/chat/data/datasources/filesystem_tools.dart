import 'dart:convert';
import 'dart:io';

class TextFileSnapshot {
  const TextFileSnapshot({
    required this.path,
    required this.exists,
    this.content,
    this.error,
  });

  final String path;
  final bool exists;
  final String? content;
  final String? error;
}

class FilesystemTools {
  FilesystemTools._();

  static const int _maxReadChars = 120000;
  static const int _maxEntries = 300;
  static const int _maxSearchResults = 200;
  static const int _maxFileBytesForSearch = 1024 * 1024;
  static const int _maxDiffPreviewLines = 400;
  static const int _maxDiffPreviewChars = 12000;
  static const int _maxLcsCells = 60000;

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

    try {
      final entities = <FileSystemEntity>[];
      await for (final entity in directory.list(
        recursive: recursive,
        followLinks: false,
      )) {
        entities.add(entity);
        if (entities.length >= maxEntries) break;
      }
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
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: directory.absolute.path,
        operation: 'list_directory',
        error: error,
      );
    }
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
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: file.absolute.path,
        operation: 'read_file',
        error: error,
      );
    }
  }

  static Future<String> writeFile({
    required String path,
    required String content,
    bool createParents = true,
  }) async {
    final file = File(path);
    final existedBefore = file.existsSync();
    try {
      if (createParents) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(content);
      return jsonEncode({
        'path': file.absolute.path,
        'bytes_written': utf8.encode(content).length,
        'created': !existedBefore,
      });
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: file.absolute.path,
        operation: 'write_file',
        error: error,
      );
    }
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

    try {
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
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: file.absolute.path,
        operation: 'edit_file',
        error: error,
      );
    }
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

    try {
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
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: directory.absolute.path,
        operation: 'find_files',
        error: error,
      );
    }
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

    try {
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
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: directory.absolute.path,
        operation: 'search_files',
        error: error,
      );
    }
  }

  static Future<TextFileSnapshot> captureTextSnapshot(String path) async {
    final absolutePath = File(path).absolute.path;
    final entityType = FileSystemEntity.typeSync(path, followLinks: false);

    if (entityType == FileSystemEntityType.notFound) {
      return TextFileSnapshot(path: absolutePath, exists: false);
    }

    if (entityType != FileSystemEntityType.file &&
        entityType != FileSystemEntityType.link) {
      return TextFileSnapshot(
        path: absolutePath,
        exists: true,
        error: 'Path is not a regular text file.',
      );
    }

    final file = File(path);
    try {
      final rawBytes = await file.readAsBytes();
      final content = utf8.decode(rawBytes, allowMalformed: false);
      return TextFileSnapshot(
        path: file.absolute.path,
        exists: true,
        content: content,
      );
    } on FormatException {
      return TextFileSnapshot(
        path: file.absolute.path,
        exists: true,
        error:
            'File is not valid UTF-8 text. Diff preview is unavailable for '
            'binary or non-text files.',
      );
    } on FileSystemException catch (error) {
      return TextFileSnapshot(
        path: file.absolute.path,
        exists: true,
        error: error.toString(),
      );
    }
  }

  static Future<String> buildWriteDiffPreview({
    required String path,
    required String newContent,
  }) async {
    final snapshot = await captureTextSnapshot(path);
    if (snapshot.error != null) {
      return _buildPreviewUnavailableMessage(
        snapshot.error!,
        fallbackContent: newContent,
      );
    }

    return buildUnifiedDiff(
      path: snapshot.path,
      oldContent: snapshot.exists ? snapshot.content : null,
      newContent: newContent,
    );
  }

  static Future<String> buildEditDiffPreview({
    required String path,
    required String oldText,
    required String newText,
    bool replaceAll = false,
  }) async {
    final snapshot = await captureTextSnapshot(path);
    if (!snapshot.exists) {
      return _buildPreviewUnavailableMessage('File does not exist: $path');
    }
    if (snapshot.error != null) {
      return _buildPreviewUnavailableMessage(snapshot.error!);
    }
    if (oldText.isEmpty) {
      return _buildPreviewUnavailableMessage('old_text must not be empty');
    }

    final content = snapshot.content ?? '';
    final occurrences = _countOccurrences(content, oldText);
    if (occurrences == 0) {
      return _buildPreviewUnavailableMessage(
        'old_text was not found in the target file',
      );
    }
    if (!replaceAll && occurrences > 1) {
      return _buildPreviewUnavailableMessage(
        'old_text matched multiple locations. Set replace_all=true or make '
        'the target text more specific.',
      );
    }

    final updatedContent = replaceAll
        ? content.replaceAll(oldText, newText)
        : content.replaceFirst(oldText, newText);

    return buildUnifiedDiff(
      path: snapshot.path,
      oldContent: content,
      newContent: updatedContent,
    );
  }

  static Future<String> restoreTextSnapshot({
    required String path,
    required bool existedBefore,
    String? content,
  }) async {
    final file = File(path);

    try {
      if (!existedBefore) {
        final existedAtRollback = await file.exists();
        if (existedAtRollback) {
          await file.delete();
        }
        return jsonEncode({
          'path': file.absolute.path,
          'restored': true,
          'deleted': existedAtRollback,
        });
      }

      await file.parent.create(recursive: true);
      final restoredContent = content ?? '';
      await file.writeAsString(restoredContent);
      return jsonEncode({
        'path': file.absolute.path,
        'restored': true,
        'bytes_written': utf8.encode(restoredContent).length,
      });
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: file.absolute.path,
        operation: 'restore_text_snapshot',
        error: error,
      );
    }
  }

  static String buildUnifiedDiff({
    required String path,
    required String? oldContent,
    required String? newContent,
  }) {
    final oldLines = _splitLines(oldContent);
    final newLines = _splitLines(newContent);
    final operations = _buildDiffOperations(oldLines, newLines);
    final body = _renderUnifiedDiffBody(operations);

    return _truncatePreviewLines([
      '--- ${oldContent == null ? "/dev/null" : path}',
      '+++ ${newContent == null ? "/dev/null" : path}',
      ...body,
    ]);
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

  static List<String> _splitLines(String? content) {
    if (content == null || content.isEmpty) return const [];
    return const LineSplitter().convert(content);
  }

  static List<_DiffOp> _buildDiffOperations(
    List<String> oldLines,
    List<String> newLines,
  ) {
    final cellCount = oldLines.length * newLines.length;
    if (cellCount <= _maxLcsCells) {
      return _buildDiffOperationsWithLcs(oldLines, newLines);
    }
    return _buildDiffOperationsWithAnchors(oldLines, newLines);
  }

  static List<_DiffOp> _buildDiffOperationsWithLcs(
    List<String> oldLines,
    List<String> newLines,
  ) {
    final lcs = List.generate(
      oldLines.length + 1,
      (_) => List<int>.filled(newLines.length + 1, 0),
    );

    for (var i = oldLines.length - 1; i >= 0; i--) {
      for (var j = newLines.length - 1; j >= 0; j--) {
        lcs[i][j] = oldLines[i] == newLines[j]
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }

    final operations = <_DiffOp>[];
    var i = 0;
    var j = 0;
    while (i < oldLines.length && j < newLines.length) {
      if (oldLines[i] == newLines[j]) {
        operations.add(_DiffOp(' ', oldLines[i]));
        i += 1;
        j += 1;
        continue;
      }

      if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        operations.add(_DiffOp('-', oldLines[i]));
        i += 1;
      } else {
        operations.add(_DiffOp('+', newLines[j]));
        j += 1;
      }
    }

    while (i < oldLines.length) {
      operations.add(_DiffOp('-', oldLines[i]));
      i += 1;
    }
    while (j < newLines.length) {
      operations.add(_DiffOp('+', newLines[j]));
      j += 1;
    }

    return operations;
  }

  static List<_DiffOp> _buildDiffOperationsWithAnchors(
    List<String> oldLines,
    List<String> newLines,
  ) {
    var prefix = 0;
    while (prefix < oldLines.length &&
        prefix < newLines.length &&
        oldLines[prefix] == newLines[prefix]) {
      prefix += 1;
    }

    var suffix = 0;
    while (suffix < oldLines.length - prefix &&
        suffix < newLines.length - prefix &&
        oldLines[oldLines.length - 1 - suffix] ==
            newLines[newLines.length - 1 - suffix]) {
      suffix += 1;
    }

    final operations = <_DiffOp>[
      for (var index = 0; index < prefix; index++)
        _DiffOp(' ', oldLines[index]),
      for (var index = prefix; index < oldLines.length - suffix; index++)
        _DiffOp('-', oldLines[index]),
      for (var index = prefix; index < newLines.length - suffix; index++)
        _DiffOp('+', newLines[index]),
      for (var index = 0; index < suffix; index++)
        _DiffOp(' ', oldLines[oldLines.length - suffix + index]),
    ];

    return operations;
  }

  static List<String> _renderUnifiedDiffBody(List<_DiffOp> operations) {
    final changedIndexes = <int>[];
    for (var index = 0; index < operations.length; index++) {
      if (operations[index].prefix != ' ') {
        changedIndexes.add(index);
      }
    }

    if (changedIndexes.isEmpty) {
      return const ['@@', '(no changes)'];
    }

    final includedIndexes = <int>{};
    for (final index in changedIndexes) {
      final start = index - 3 < 0 ? 0 : index - 3;
      final end = index + 3 >= operations.length
          ? operations.length - 1
          : index + 3;
      for (var current = start; current <= end; current++) {
        includedIndexes.add(current);
      }
    }

    final sortedIndexes = includedIndexes.toList()..sort();
    final rendered = <String>[];
    int? previousIndex;
    for (final index in sortedIndexes) {
      if (previousIndex == null || index != previousIndex + 1) {
        rendered.add('@@');
      }
      final operation = operations[index];
      rendered.add('${operation.prefix}${operation.line}');
      previousIndex = index;
    }

    return rendered;
  }

  static String _truncatePreviewLines(List<String> lines) {
    final buffer = StringBuffer();
    var lineCount = 0;
    var charCount = 0;
    var truncated = false;

    for (final line in lines) {
      final separatorLength = lineCount == 0 ? 0 : 1;
      if (lineCount >= _maxDiffPreviewLines ||
          charCount + separatorLength + line.length > _maxDiffPreviewChars) {
        truncated = true;
        break;
      }

      if (lineCount > 0) {
        buffer.writeln();
      }
      buffer.write(line);
      lineCount += 1;
      charCount += separatorLength + line.length;
    }

    if (truncated) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write('... diff preview truncated ...');
    }

    return buffer.toString();
  }

  static String _buildPreviewUnavailableMessage(
    String reason, {
    String? fallbackContent,
  }) {
    final lines = <String>['Diff preview unavailable: $reason'];
    if (fallbackContent != null && fallbackContent.isNotEmpty) {
      lines
        ..add('')
        ..add('Proposed content:')
        ..addAll(_splitLines(fallbackContent).map((line) => '+$line'));
    }
    return _truncatePreviewLines(lines);
  }

  static String _buildFilesystemError({
    required String path,
    required String operation,
    required FileSystemException error,
  }) {
    final message = error.message.trim();
    final osMessage = error.osError?.message.trim();
    final permissionDenied =
        error.osError?.errorCode == 1 ||
        error.osError?.errorCode == 13 ||
        message.contains('Operation not permitted') ||
        message.contains('Permission denied') ||
        (osMessage?.contains('Operation not permitted') ?? false) ||
        (osMessage?.contains('Permission denied') ?? false);

    return jsonEncode({
      'error': permissionDenied
          ? 'Permission denied while trying to $operation.'
          : 'Filesystem operation failed during $operation.',
      'code': permissionDenied ? 'permission_denied' : 'filesystem_error',
      'path': path,
      'details': error.toString(),
      if (permissionDenied && Platform.isMacOS)
        'suggestion':
            'Re-select the project folder in Coding mode, then allow access in the macOS prompt or System Settings > Privacy & Security > Files and Folders.',
    });
  }
}

class _DiffOp {
  const _DiffOp(this.prefix, this.line);

  final String prefix;
  final String line;
}
