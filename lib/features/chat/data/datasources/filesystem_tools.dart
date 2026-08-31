import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

export 'filesystem_text_snapshot.dart';

import 'bounded_text_file_classifier.dart';
import 'filesystem_diff_builder.dart';
import 'filesystem_mutation_operations.dart';
import 'filesystem_pdf_reader.dart';
import 'filesystem_overview_format.dart';
import 'filesystem_path_resolver.dart';
import 'filesystem_text_snapshot.dart';
import 'first_party_tool_execution_result.dart';

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

  /// Size ceiling for computing a read's whole-file content hash.
  ///
  /// The hash reads the file into memory, which the streaming read path
  /// deliberately avoids, so it is skipped above this bound rather than paying
  /// an unbounded cost for a fact that is only an optimisation. Source files
  /// are orders of magnitude below it. Absent means "unknown", never
  /// "unchanged" — see [ToolOutcome.contentHash].
  static const int _maxContentHashBytes = 8 * 1024 * 1024;

  /// Hard cap on how many characters a single streamed line may buffer before
  /// it is truncated. Bounds memory on pathological single-giant-line files
  /// (e.g. minified JSON) where a newline never arrives. All callers truncate
  /// further (read_file by max_chars, inspect_file / search_files by their line
  /// clamps), so this is invisible for normal line-oriented files.
  static const int _maxStreamLineChars = 1024 * 1024;

  static const int _maxEntries = 300;
  static const int _maxSearchResults = 200;
  static final _mutationOperations = FilesystemMutationOperations(
    contentHash: _contentHash,
    buildError: _buildFilesystemError,
  );
  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  /// Delegates to [FilesystemPathResolver.resolve]; retained because callers
  /// outside this file resolve paths through the tool surface.
  static String? resolvePath(String? rawPath, {String? defaultRoot}) =>
      FilesystemPathResolver.resolve(rawPath, defaultRoot: defaultRoot);

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
          lines.add(
            '[$type] $relativePath (${FilesystemOverviewFormat.formatBytes(size)})',
          );
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
    int startPage = 1,
  }) async => (await readFileResult(
    path: path,
    maxChars: maxChars,
    offset: offset,
    limit: limit,
    startPage: startPage,
  )).result;

  static Future<FirstPartyToolExecutionResult> readFileResult({
    required String path,
    int maxChars = _maxReadChars,
    int offset = 1,
    int? limit,
    int startPage = 1,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({'error': 'File does not exist: $path'}),
      );
    }
    if (offset < 1) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({'error': 'offset must be greater than or equal to 1'}),
      );
    }
    if (limit != null && limit < 1) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({'error': 'limit must be greater than or equal to 1'}),
      );
    }

    final absolutePath = file.absolute.path;
    if (FilesystemPathResolver.isBlockedReadPath(absolutePath)) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error': 'Special device files are not supported by read_file.',
          'path': absolutePath,
        }),
      );
    }

    try {
      // One prefix read answers both questions. PDFs are asked about first:
      // an uncompressed one is printable ASCII, so the encoding check would
      // wave it through and the tool would return raw `%PDF` syntax.
      final prefix = await BoundedTextFileClassifier.sniff(file);
      final pdf = await FilesystemPdfReader.readFileResult(
        file: file,
        absolutePath: absolutePath,
        prefix: prefix.bytes,
        offset: offset,
        limit: limit,
        maxChars: maxChars,
        startPage: startPage,
      );
      if (pdf != null) return pdf;
      if (prefix.looksBinary) {
        return FirstPartyToolExecutionResult.payloadOnly(
          jsonEncode({
            'error':
                'File is not valid UTF-8 text. Binary files are not supported.',
            'path': absolutePath,
          }),
        );
      }

      final sizeBytes = await file.length();
      final selection = await _streamLineRange(
        file: file,
        offset: offset,
        limit: limit,
        maxChars: maxChars,
        maxScanBytes: _maxScanBytes,
      );

      final contentHash = await _contentHash(absolutePath, sizeBytes);
      final response = <String, dynamic>{
        'path': absolutePath,
        'content': selection.content,
        'content_hash': contentHash,
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
      return FirstPartyToolExecutionResult(
        result: jsonEncode(response),
        outcome: contentHash == null || selection.totalLinesIsEstimate
            ? null
            : ToolOutcome(
                readOutcome: ToolReadOutcome(
                  path: absolutePath,
                  contentHash: contentHash,
                  byteSize: sizeBytes,
                  lineCount: selection.totalLines,
                ),
              ),
      );
    } on FormatException {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error':
              'File is not valid UTF-8 text. Binary files are not supported.',
          'path': absolutePath,
        }),
      );
    } on FileSystemException catch (error) {
      return FirstPartyToolExecutionResult.payloadOnly(
        _buildFilesystemError(
          path: absolutePath,
          operation: 'read_file',
          error: error,
        ),
      );
    }
  }

  /// Whole-file content hash for a read, or null when it cannot be computed.
  ///
  /// Deliberately hashes the *file*, not the returned selection: the point is
  /// to answer "is this the same file I saw before" across different paging
  /// windows, which a hash of the window cannot do. It reuses the mutation
  /// precondition's fingerprint so a read and a pending edit agree on what
  /// identity means.
  ///
  /// Returns null above [_maxContentHashBytes] or on any read failure, because
  /// a missing hash means unknown and a caller must not read it as unchanged.
  static Future<String?> _contentHash(String path, int sizeBytes) async {
    if (sizeBytes > _maxContentHashBytes) {
      return null;
    }
    try {
      final snapshot = await captureTextSnapshot(path);
      if (!snapshot.exists || snapshot.error != null) {
        return null;
      }
      return textSnapshotFingerprintForSnapshot(snapshot);
    } catch (_) {
      return null;
    }
  }

  static Future<String> deleteFile({required String path}) async =>
      (await deleteFileResult(path: path)).result;

  static Future<FirstPartyToolExecutionResult> deleteFileResult({
    required String path,
  }) => _mutationOperations.deleteFileResult(path: path);

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
      final prefix = await BoundedTextFileClassifier.sniff(file);
      final pdf = await FilesystemPdfReader.inspectFile(
        file: file,
        absolutePath: absolutePath,
        prefix: prefix.bytes,
        headLimit: headLimit,
        tailLimit: tailLimit,
      );
      if (pdf != null) return pdf;
      if (prefix.looksBinary) {
        return jsonEncode({
          'path': absolutePath,
          'size_bytes': sizeBytes,
          'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
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
          final clipped = FilesystemOverviewFormat.clipLine(line);
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
        'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
        'total_lines': result.lineCount,
        'encoding': 'utf-8',
        'is_binary': false,
        'format_hint': FilesystemOverviewFormat.detectFormatHint(
          absolutePath,
          firstNonEmpty,
        ),
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
  }) async => (await writeFileResult(
    path: path,
    content: content,
    createParents: createParents,
  )).result;

  static Future<FirstPartyToolExecutionResult> writeFileResult({
    required String path,
    required String content,
    bool createParents = true,
  }) => _mutationOperations.writeFileResult(
    path: path,
    content: content,
    createParents: createParents,
  );

  static Future<String> editFile({
    required String path,
    required String oldText,
    required String newText,
    bool replaceAll = false,
  }) async => (await editFileResult(
    path: path,
    oldText: oldText,
    newText: newText,
    replaceAll: replaceAll,
  )).result;

  static Future<FirstPartyToolExecutionResult> editFileResult({
    required String path,
    required String oldText,
    required String newText,
    bool replaceAll = false,
  }) => _mutationOperations.editFileResult(
    path: path,
    oldText: oldText,
    newText: newText,
    replaceAll: replaceAll,
  );

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
      final result = _mutationOperations.editPreconditionResult(
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

    final lineClamp = maxLineLength.clamp(
      40,
      FilesystemOverviewFormat.maxOverviewLineChars,
    );
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
          if (await BoundedTextFileClassifier.looksBinary(entity)) continue;
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

  static Future<TextFileSnapshot> captureTextSnapshot(String path) =>
      FilesystemTextSnapshot.capture(path);

  static Future<String> textSnapshotFingerprint(String path) =>
      FilesystemTextSnapshot.fingerprint(path);

  static String textSnapshotFingerprintForSnapshot(TextFileSnapshot snapshot) =>
      FilesystemTextSnapshot.fingerprintSnapshot(snapshot);

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
    final preconditionResult = _mutationOperations.editPreconditionResult(
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
