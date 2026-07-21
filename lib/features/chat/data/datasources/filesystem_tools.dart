import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'filesystem_diff_builder.dart';
import 'filesystem_path_resolver.dart';

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

class _LineRangeSelection {
  const _LineRangeSelection({
    required this.content,
    required this.startLine,
    required this.lineCount,
    required this.totalLines,
    required this.truncatedByLimit,
    this.truncatedByChars = false,
    this.scanCeilingHit = false,
    this.totalLinesIsEstimate = false,
  });

  final String content;
  final int startLine;
  final int lineCount;
  final int totalLines;
  final bool truncatedByLimit;
  final bool truncatedByChars;
  final bool scanCeilingHit;
  final bool totalLinesIsEstimate;
}

class FilesystemTools {
  FilesystemTools._();

  static const int _maxReadChars = 120000;

  /// Upper bound on bytes scanned for any single-file streaming operation
  /// (read_file, inspect_file, search_files). Keeps memory and latency bounded
  /// on huge files; tighter on mobile where RAM is scarce.
  static int get _maxScanBytes => (Platform.isIOS || Platform.isAndroid)
      ? 64 * 1024 * 1024
      : 256 * 1024 * 1024;

  /// Number of leading bytes sampled to detect binary / non-UTF-8 files
  /// without reading the whole file into memory.
  static const int _binarySniffBytes = 8192;

  /// Per-line character cap for inspect_file head/tail and search_files
  /// matches, so a single pathologically long line cannot blow the output
  /// (or the scan's memory) on minified or single-line files.
  static const int _maxOverviewLineChars = 1000;

  /// Hard cap on how many characters a single streamed line may buffer before
  /// it is truncated. Bounds memory on pathological single-giant-line files
  /// (e.g. minified JSON) where a newline never arrives. All callers truncate
  /// further (read_file by max_chars, inspect_file / search_files by their line
  /// clamps), so this is invisible for normal line-oriented files.
  static const int _maxStreamLineChars = 1024 * 1024;

  static const int _maxEntries = 300;
  static const int _maxSearchResults = 200;
  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  /// Delegates to [FilesystemPathResolver.resolve]; retained because callers
  /// outside this file resolve paths through the tool surface.
  static String? resolvePath(String? rawPath, {String? defaultRoot}) =>
      FilesystemPathResolver.resolve(rawPath, defaultRoot: defaultRoot);

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
    int offset = 1,
    int? limit,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      return jsonEncode({'error': 'File does not exist: $path'});
    }
    if (offset < 1) {
      return jsonEncode({'error': 'offset must be greater than or equal to 1'});
    }
    if (limit != null && limit < 1) {
      return jsonEncode({'error': 'limit must be greater than or equal to 1'});
    }

    final absolutePath = file.absolute.path;
    if (FilesystemPathResolver.isBlockedReadPath(absolutePath)) {
      return jsonEncode({
        'error': 'Special device files are not supported by read_file.',
        'path': absolutePath,
      });
    }

    try {
      if (await _looksBinary(file)) {
        return jsonEncode({
          'error':
              'File is not valid UTF-8 text. Binary files are not supported.',
          'path': absolutePath,
        });
      }

      final sizeBytes = await file.length();
      final selection = await _streamLineRange(
        file: file,
        offset: offset,
        limit: limit,
        maxChars: maxChars,
        maxScanBytes: _maxScanBytes,
      );

      final response = <String, dynamic>{
        'path': absolutePath,
        'content': selection.content,
        'size_bytes': sizeBytes,
        'start_line': selection.startLine,
        'line_count': selection.lineCount,
        'total_lines': selection.totalLines,
        if (offset > 1) 'offset': offset,
        'limit': limit,
        if (selection.truncatedByChars ||
            selection.truncatedByLimit ||
            selection.scanCeilingHit)
          'truncated': true,
        if (selection.truncatedByChars) 'truncated_by_chars': true,
        if (selection.truncatedByLimit) 'truncated_by_limit': true,
        if (selection.scanCeilingHit) 'scan_ceiling_hit': true,
        if (selection.totalLinesIsEstimate) 'total_lines_is_estimate': true,
      };
      response.removeWhere((_, value) => value == null);
      return jsonEncode(response);
    } on FormatException {
      return jsonEncode({
        'error':
            'File is not valid UTF-8 text. Binary files are not supported.',
        'path': absolutePath,
      });
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: absolutePath,
        operation: 'read_file',
        error: error,
      );
    }
  }

  static Future<String> deleteFile({required String path}) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return jsonEncode({'error': 'File does not exist: $path'});
    }
    if (type != FileSystemEntityType.file) {
      return jsonEncode({
        'error': 'delete_file supports regular files only.',
        'path': File(path).absolute.path,
      });
    }
    final snapshot = await captureTextSnapshot(path);
    if (snapshot.error != null) {
      return jsonEncode({
        'error':
            'delete_file requires a readable UTF-8 text file so the change can be rolled back.',
        'path': File(path).absolute.path,
      });
    }
    try {
      await File(path).delete();
      return jsonEncode({'deleted': true, 'path': File(path).absolute.path});
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: File(path).absolute.path,
        operation: 'delete_file',
        error: error,
      );
    }
  }

  /// Cheap overview of a (potentially huge) text file without reading it all.
  ///
  /// Returns byte size, total line count, head/tail samples, detected encoding
  /// and a format hint — the entry point the model should call first on a
  /// large or unknown file before searching or range-reading it. Memory stays
  /// bounded: only [headLines] + [tailLines] clipped lines are retained.
  static Future<String> inspectFile({
    required String path,
    int headLines = 50,
    int tailLines = 20,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      return jsonEncode({'error': 'File does not exist: $path'});
    }
    final absolutePath = file.absolute.path;
    if (FilesystemPathResolver.isBlockedReadPath(absolutePath)) {
      return jsonEncode({
        'error': 'Special device files are not supported by inspect_file.',
        'path': absolutePath,
      });
    }

    final headLimit = headLines.clamp(0, 100);
    final tailLimit = tailLines.clamp(0, 50);

    try {
      final sizeBytes = await file.length();
      if (await _looksBinary(file)) {
        return jsonEncode({
          'path': absolutePath,
          'size_bytes': sizeBytes,
          'size_human': _formatBytes(sizeBytes),
          'is_binary': true,
          'encoding': 'binary',
        });
      }

      final head = <String>[];
      final tail = ListQueue<String>();
      final result = await _forEachLine(
        file,
        maxScanBytes: _maxScanBytes,
        onLine: (lineNo, line) {
          final clipped = _clipLine(line);
          if (head.length < headLimit) head.add(clipped);
          if (tailLimit > 0) {
            tail.addLast(clipped);
            if (tail.length > tailLimit) tail.removeFirst();
          }
          return true;
        },
      );

      final firstNonEmpty = head.firstWhere(
        (line) => line.trim().isNotEmpty,
        orElse: () => '',
      );

      final response = <String, dynamic>{
        'path': absolutePath,
        'size_bytes': sizeBytes,
        'size_human': _formatBytes(sizeBytes),
        'total_lines': result.lineCount,
        'encoding': 'utf-8',
        'is_binary': false,
        'format_hint': _detectFormatHint(absolutePath, firstNonEmpty),
        'head': head,
        if (tailLimit > 0) 'tail': tail.toList(),
        if (result.scanCeilingHit) 'line_count_capped': true,
        if (result.scanCeilingHit) 'total_lines_is_estimate': true,
      };
      return jsonEncode(response);
    } on FormatException {
      return jsonEncode({
        'error':
            'File is not valid UTF-8 text. Binary files are not supported.',
        'path': absolutePath,
      });
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: absolutePath,
        operation: 'inspect_file',
        error: error,
      );
    }
  }

  static String _clipLine(String line) => line.length > _maxOverviewLineChars
      ? '${line.substring(0, _maxOverviewLineChars)}…'
      : line;

  static final RegExp _logLinePrefix = RegExp(
    r'^\[?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}' // 2026-06-05 12:34:56
    r'|^\[?\d{2}:\d{2}:\d{2}' // 12:34:56
    r'|^\[?(ERROR|WARN|WARNING|INFO|DEBUG|TRACE|FATAL)\b', // level prefix
    caseSensitive: false,
  );

  /// Best-effort, cheap format classification from the file extension first,
  /// then the first non-empty line. Used only as a hint for the model.
  static String _detectFormatHint(String path, String firstNonEmptyLine) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jsonl') || lower.endsWith('.ndjson')) return 'jsonl';
    if (lower.endsWith('.json')) return 'json';
    if (lower.endsWith('.csv')) return 'csv';
    if (lower.endsWith('.tsv')) return 'tsv';
    if (lower.endsWith('.log')) return 'log';
    if (lower.endsWith('.xml')) return 'xml';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'yaml';
    if (lower.endsWith('.md')) return 'markdown';

    final trimmed = firstNonEmptyLine.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return 'json';
    if (_logLinePrefix.hasMatch(trimmed)) return 'log';
    if (trimmed.contains(',') && firstNonEmptyLine.split(',').length >= 3) {
      return 'csv';
    }
    return 'text';
  }

  /// Sniffs the first [_binarySniffBytes] of [file] to decide whether it is a
  /// binary / non-UTF-8 file, without loading the whole file into memory.
  ///
  /// Treats a NUL byte as a definitive binary marker. For UTF-8 validation it
  /// tolerates a multi-byte rune that happens to be split at the sniff
  /// boundary (UTF-8 runes are at most 4 bytes) before declaring the file
  /// binary.
  static Future<bool> _looksBinary(File file) async {
    try {
      final prefix = <int>[];
      await for (final chunk in file.openRead(0, _binarySniffBytes)) {
        prefix.addAll(chunk);
        if (prefix.length >= _binarySniffBytes) break;
      }
      if (prefix.isEmpty) return false;
      final sample = prefix.length > _binarySniffBytes
          ? prefix.sublist(0, _binarySniffBytes)
          : prefix;
      if (sample.contains(0)) return true;
      for (var drop = 0; drop <= 3 && sample.length - drop > 0; drop++) {
        try {
          utf8.decode(
            sample.sublist(0, sample.length - drop),
            allowMalformed: false,
          );
          return false;
        } on FormatException {
          // A trailing rune may be split at the boundary; retry with fewer
          // bytes. If every attempt fails the content is genuinely binary.
        }
      }
      return true;
    } on FileSystemException {
      // Let the caller's own open attempt surface the I/O error instead.
      return false;
    }
  }

  /// Streams UTF-8 text lines from [file], invoking [onLine] for each line.
  ///
  /// Iteration stops when [onLine] returns false, or when more than
  /// [maxScanBytes] raw bytes have been read (a safety ceiling that keeps
  /// latency and memory bounded on huge files). Memory stays bounded with
  /// respect to file size: lines are not retained, and a single line that never
  /// terminates is truncated at [_maxStreamLineChars] rather than buffered in
  /// full. The byte ceiling is checked per chunk — so even a giant
  /// newline-less line is cut off — and bytes are counted on the raw byte
  /// stream (before decoding) for an encoding-independent measure.
  ///
  /// Splits on `\n` and `\r\n`; lone `\r` (classic Mac) line endings are not
  /// treated as separators, which is acceptable for modern logs/text.
  static Future<({int lineCount, bool scanCeilingHit})> _forEachLine(
    File file, {
    required int maxScanBytes,
    required bool Function(int lineNo, String line) onLine,
  }) async {
    var lineNo = 0;
    var bytesScanned = 0;
    var scanCeilingHit = false;
    var stopped = false;

    final carry = StringBuffer();
    var carryTruncated = false;

    void appendCarry(String text) {
      if (carryTruncated || text.isEmpty) return;
      final room = _maxStreamLineChars - carry.length;
      if (text.length <= room) {
        carry.write(text);
      } else {
        if (room > 0) carry.write(text.substring(0, room));
        carryTruncated = true;
      }
    }

    String takeLine(String tail) {
      appendCarry(tail);
      var line = carry.toString();
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      carry.clear();
      carryTruncated = false;
      return line;
    }

    final textStream = file
        .openRead()
        .map<List<int>>((chunk) {
          bytesScanned += chunk.length;
          return chunk;
        })
        .transform(utf8.decoder);

    await for (final text in textStream) {
      var start = 0;
      while (true) {
        final newlineIndex = text.indexOf('\n', start);
        if (newlineIndex < 0) {
          appendCarry(text.substring(start));
          break;
        }
        final line = takeLine(text.substring(start, newlineIndex));
        lineNo += 1;
        if (!onLine(lineNo, line)) {
          stopped = true;
          break;
        }
        start = newlineIndex + 1;
      }
      if (stopped) break;
      if (bytesScanned > maxScanBytes) {
        scanCeilingHit = true;
        break;
      }
    }

    // Emit the final line when the file does not end in a newline. Skipped when
    // we stopped early or hit the byte ceiling mid-line (that line is partial).
    if (!stopped && !scanCeilingHit && (carry.isNotEmpty || carryTruncated)) {
      final line = takeLine('');
      lineNo += 1;
      onLine(lineNo, line);
    }

    return (lineCount: lineNo, scanCeilingHit: scanCeilingHit);
  }

  /// Streaming replacement for the previous whole-file line selection. Collects
  /// the line window `[offset, offset + limit)` (clamped to [maxChars]) while
  /// counting total lines, all in a single pass with bounded memory.
  static Future<_LineRangeSelection> _streamLineRange({
    required File file,
    required int offset,
    required int? limit,
    required int maxChars,
    required int maxScanBytes,
  }) async {
    final buffer = StringBuffer();
    var selectedLineCount = 0;
    var charsCollected = 0;
    var truncatedByChars = false;
    final endLineExclusive = limit == null ? null : offset + limit;

    final result = await _forEachLine(
      file,
      maxScanBytes: maxScanBytes,
      onLine: (lineNo, line) {
        final inWindow =
            lineNo >= offset &&
            (endLineExclusive == null || lineNo < endLineExclusive);
        if (inWindow) {
          if (!truncatedByChars) {
            final separator = selectedLineCount == 0 ? 0 : 1;
            final projected = charsCollected + separator + line.length;
            if (projected > maxChars) {
              final remaining = maxChars - charsCollected - separator;
              if (remaining > 0) {
                if (selectedLineCount > 0) buffer.write('\n');
                buffer.write(line.substring(0, remaining));
                charsCollected += separator + remaining;
              }
              truncatedByChars = true;
            } else {
              if (selectedLineCount > 0) buffer.write('\n');
              buffer.write(line);
              charsCollected = projected;
            }
          }
          selectedLineCount += 1;
        }
        // Always keep going so total_lines reflects the whole file (until the
        // byte ceiling enforced by _forEachLine).
        return true;
      },
    );

    final totalLines = result.lineCount;
    final truncatedByLimit = limit != null && totalLines > (offset - 1) + limit;

    return _LineRangeSelection(
      content: buffer.toString(),
      startLine: totalLines == 0 ? 0 : offset,
      lineCount: selectedLineCount,
      totalLines: totalLines,
      truncatedByLimit: truncatedByLimit,
      truncatedByChars: truncatedByChars,
      scanCeilingHit: result.scanCeilingHit,
      totalLinesIsEstimate: result.scanCeilingHit,
    );
  }

  static Future<String> writeFile({
    required String path,
    required String content,
    bool createParents = true,
  }) async {
    final file = File(path);
    final existedBefore = file.existsSync();
    try {
      final newBytes = utf8.encode(content);
      // Whether the write changed anything is not derivable from the response
      // otherwise: a byte-identical write reports the same bytes_written as a
      // real edit, which is what lets an edit/re-read loop repeat forever
      // while nothing moves. Compare lengths first so the content read only
      // happens when a no-op is actually possible.
      var changed = true;
      if (existedBefore) {
        try {
          changed =
              await file.length() != newBytes.length ||
              !_bytesEqual(await file.readAsBytes(), newBytes);
        } on FileSystemException {
          changed = true;
        }
      }
      if (createParents) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(content);
      return jsonEncode({
        'path': file.absolute.path,
        'bytes_written': newBytes.length,
        'created': !existedBefore,
        'changed': changed,
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
      final preconditionResult = _editPreconditionResult(
        path: file.absolute.path,
        content: content,
        oldText: oldText,
        newText: newText,
        replaceAll: replaceAll,
      );
      if (preconditionResult != null) {
        return jsonEncode(preconditionResult);
      }

      final occurrences = _countOccurrences(content, oldText);
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

  static Future<String?> preflightEditFile({
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
      final result = _editPreconditionResult(
        path: file.absolute.path,
        content: content,
        oldText: oldText,
        newText: newText,
        replaceAll: replaceAll,
      );
      return result == null ? null : jsonEncode(result);
    } on FileSystemException catch (error) {
      return _buildFilesystemError(
        path: file.absolute.path,
        operation: 'edit_file_preflight',
        error: error,
      );
    }
  }

  static Map<String, dynamic>? _editPreconditionResult({
    required String path,
    required String content,
    required String oldText,
    required String newText,
    required bool replaceAll,
  }) {
    final oldTextOffsets = _occurrenceOffsets(content, oldText);
    if (oldTextOffsets.isEmpty) {
      return _oldTextNotFoundError(path: path, content: content);
    }
    if (oldText == newText) {
      return {
        'error': 'no_change',
        'path': path,
        'message':
            'The edit made no change: new_text is identical to old_text, so '
            'the file is unchanged and your intended fix did not apply. Do '
            'not re-read expecting a change. Provide a new_text that actually '
            'differs from old_text, or use write_file to overwrite the file.',
      };
    }

    final coveredOffsets = _oldTextOffsetsCoveredByNewText(
      content: content,
      oldText: oldText,
      newText: newText,
    );
    if (coveredOffsets.length == oldTextOffsets.length) {
      return {
        'path': path,
        'replacements': 0,
        'replace_all': replaceAll,
        'already_applied': true,
        'message':
            'new_text is already present at every old_text match; the file was left unchanged.',
      };
    }
    if (coveredOffsets.isNotEmpty) {
      return {
        'error': 'ambiguous_edit_overlap',
        'path': path,
        'occurrences': oldTextOffsets.length,
        'already_applied_occurrences': coveredOffsets.length,
        'message':
            'Some old_text matches are already contained inside new_text. Re-read the file and use a more specific old_text so an applied edit is not expanded again.',
      };
    }
    if (!replaceAll && oldTextOffsets.length > 1) {
      return {
        'error':
            'old_text matched multiple locations. Set replace_all=true or make the target text more specific.',
        'path': path,
        'occurrences': oldTextOffsets.length,
      };
    }
    return null;
  }

  static Set<int> _oldTextOffsetsCoveredByNewText({
    required String content,
    required String oldText,
    required String newText,
  }) {
    if (newText.isEmpty || !newText.contains(oldText)) {
      return const <int>{};
    }
    final relativeOldTextOffsets = _occurrenceOffsets(newText, oldText);
    final coveredOffsets = <int>{};
    for (final newTextOffset in _occurrenceOffsets(content, newText)) {
      for (final relativeOffset in relativeOldTextOffsets) {
        coveredOffsets.add(newTextOffset + relativeOffset);
      }
    }
    return coveredOffsets;
  }

  /// Maximum file size (UTF-8 bytes) for which a failed [editFile] echoes the
  /// full current content inline, so the model can copy `old_text` verbatim or
  /// overwrite via `write_file` without another `read_file` round-trip.
  static const int _editErrorInlineContentMaxBytes = 4096;

  /// Build an actionable "old_text not found" error for [editFile].
  ///
  /// Keeps the exact `old_text was not found in the target file` phrase that
  /// tool-loop recovery and edit telemetry match on, but adds the current file
  /// content (for small files) plus a hint. Live canary traces showed a model
  /// react to the bare error by retrying with a guessed block body, then with
  /// the desired *new* value as `old_text`, then looping on `read_file` without
  /// ever landing a fix; the inline content and hint target exactly that
  /// failure at the point it happens.
  static Map<String, dynamic> _oldTextNotFoundError({
    required String path,
    required String content,
  }) {
    final error = <String, dynamic>{
      'error': 'old_text was not found in the target file',
      'path': path,
    };
    if (utf8.encode(content).length <= _editErrorInlineContentMaxBytes) {
      error['current_content'] = content;
      error['hint'] =
          'old_text must be copied verbatim from current_content; do not pass '
          'the desired new value as old_text. If matching is hard, call '
          'write_file with the full corrected file content instead.';
    } else {
      error['hint'] =
          'Re-read the file and copy old_text verbatim from its current '
          'content; do not guess and do not pass the desired new value as '
          'old_text.';
    }
    return error;
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
    int offset = 0,
    int maxLineLength = 500,
    int? maxBytesScanned,
  }) async {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return jsonEncode({'error': 'Directory does not exist: $path'});
    }
    if (query.trim().isEmpty) {
      return jsonEncode({'error': 'query is required'});
    }
    if (offset < 0) {
      return jsonEncode({'error': 'offset must be greater than or equal to 0'});
    }

    final lineClamp = maxLineLength.clamp(40, _maxOverviewLineChars);
    var remainingBudget = (maxBytesScanned ?? _maxScanBytes).clamp(
      1,
      _maxScanBytes,
    );

    try {
      final normalizedQuery = caseSensitive ? query : query.toLowerCase();
      final fileMatcher = filePattern == null || filePattern.trim().isEmpty
          ? null
          : _wildcardToRegExp(filePattern.trim());

      final matches = <String>[];
      var scannedFiles = 0;
      var matchedLinesSeen = 0;
      var bytesScanned = 0;
      var scanCeilingHit = false;
      var resultLimitHit = false;

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

        if (remainingBudget <= 0) {
          scanCeilingHit = true;
          break;
        }

        // Skip binary files cheaply (sampled prefix) instead of reading them
        // fully like the previous implementation did.
        try {
          if (await _looksBinary(entity)) continue;
        } on FileSystemException {
          continue;
        }

        final fileLength = await entity.length();
        scannedFiles += 1;

        try {
          final fileResult = await _forEachLine(
            entity,
            maxScanBytes: remainingBudget,
            onLine: (lineNo, line) {
              final haystack = caseSensitive ? line : line.toLowerCase();
              if (haystack.contains(normalizedQuery)) {
                if (matchedLinesSeen < offset) {
                  matchedLinesSeen += 1;
                  return true;
                }
                final clipped = line.length > lineClamp
                    ? '${line.substring(0, lineClamp)}…'
                    : line;
                matches.add('$relativePath:$lineNo: $clipped');
                matchedLinesSeen += 1;
                if (matches.length >= maxResults) {
                  resultLimitHit = true;
                  return false;
                }
              }
              return true;
            },
          );

          if (fileResult.scanCeilingHit) {
            bytesScanned += remainingBudget;
            remainingBudget = 0;
            scanCeilingHit = true;
            break;
          }
          bytesScanned += fileLength;
          remainingBudget -= fileLength;
        } on FormatException {
          // Not valid UTF-8 after the prefix; skip.
          continue;
        } on FileSystemException {
          continue;
        }

        if (resultLimitHit) break;
      }

      return jsonEncode({
        'path': directory.absolute.path,
        'query': query,
        'matches': matches,
        'match_count': matches.length,
        'scanned_files': scannedFiles,
        'bytes_scanned': bytesScanned,
        if (offset > 0) 'offset': offset,
        'matches_seen': matchedLinesSeen,
        if (resultLimitHit) 'truncated': true,
        if (scanCeilingHit) 'scan_ceiling_hit': true,
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

  static Future<String> textSnapshotFingerprint(String path) async {
    final snapshot = await captureTextSnapshot(path);
    final payload = jsonEncode({
      'exists': snapshot.exists,
      'content': snapshot.content,
      'error': snapshot.error,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static Future<String> buildWriteDiffPreview({
    required String path,
    required String newContent,
  }) async {
    final snapshot = await captureTextSnapshot(path);
    if (snapshot.error != null) {
      return FilesystemDiffBuilder.buildUnavailableMessage(
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
      return FilesystemDiffBuilder.buildUnavailableMessage(
        'File does not exist: $path',
      );
    }
    if (snapshot.error != null) {
      return FilesystemDiffBuilder.buildUnavailableMessage(snapshot.error!);
    }
    if (oldText.isEmpty) {
      return FilesystemDiffBuilder.buildUnavailableMessage(
        'old_text must not be empty',
      );
    }

    final content = snapshot.content ?? '';
    final preconditionResult = _editPreconditionResult(
      path: snapshot.path,
      content: content,
      oldText: oldText,
      newText: newText,
      replaceAll: replaceAll,
    );
    if (preconditionResult?['already_applied'] == true) {
      return 'No file changes: new_text is already present at every old_text match.';
    }
    if (preconditionResult != null) {
      return FilesystemDiffBuilder.buildUnavailableMessage(
        preconditionResult['message']?.toString() ??
            preconditionResult['error']?.toString() ??
            'The edit precondition is not satisfied.',
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
  }) => FilesystemDiffBuilder.buildUnifiedDiff(
    path: path,
    oldContent: oldContent,
    newContent: newContent,
  );

  static int _countOccurrences(String source, String target) {
    return _occurrenceOffsets(source, target).length;
  }

  static List<int> _occurrenceOffsets(String source, String target) {
    if (target.isEmpty) {
      return const [];
    }
    final offsets = <int>[];
    var start = 0;
    while (true) {
      final index = source.indexOf(target, start);
      if (index == -1) return offsets;
      offsets.add(index);
      start = index + target.length;
    }
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
