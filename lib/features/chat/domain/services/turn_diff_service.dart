import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../entities/turn_diff.dart';

class TurnDiffBuildResult {
  const TurnDiffBuildResult({required this.file, required this.operationCount});

  final TurnDiffFile file;
  final int operationCount;
}

class TurnDiffService {
  TurnDiffService._();

  static const int maxPatchLines = 400;
  static const int maxPatchChars = 12000;
  static const int maxLcsCells = 60000;
  static const int maxTextFileBytes = 1024 * 1024;
  static const int promptPreviewLength = 120;

  static TurnDiffBuildResult? buildFileDiff({
    required String filePath,
    required String? oldContent,
    required String? newContent,
    bool oldExists = true,
    bool newExists = true,
    bool isUntracked = false,
    bool isBinary = false,
    bool isLargeFile = false,
    String note = '',
  }) {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      return null;
    }

    if (isBinary || isLargeFile || oldContent == null && newContent == null) {
      return TurnDiffBuildResult(
        file: TurnDiffFile(
          filePath: normalizedPath,
          isNewFile: !oldExists && newExists,
          isDeletedFile: oldExists && !newExists,
          isBinary: isBinary,
          isLargeFile: isLargeFile,
          isUntracked: isUntracked,
          note: note,
        ),
        operationCount: 0,
      );
    }

    if (oldExists == newExists && oldContent == newContent) {
      return null;
    }

    final oldLines = _splitLines(oldExists ? oldContent : null);
    final newLines = _splitLines(newExists ? newContent : null);
    final operations = _buildDiffOperations(oldLines, newLines);
    final stats = _countOperationStats(operations);
    final body = _renderUnifiedDiffBody(operations);
    final oldPath = oldExists ? normalizedPath : '/dev/null';
    final newPath = newExists ? normalizedPath : '/dev/null';
    final truncation = _truncatePatchLines([
      '--- $oldPath',
      '+++ $newPath',
      ...body,
    ]);

    return TurnDiffBuildResult(
      file: TurnDiffFile(
        filePath: normalizedPath,
        isNewFile: !oldExists && newExists,
        isDeletedFile: oldExists && !newExists,
        isUntracked: isUntracked,
        isTruncated: truncation.truncated,
        linesAdded: stats.added,
        linesRemoved: stats.removed,
        unifiedPatch: truncation.text,
        note: note,
      ),
      operationCount: operations
          .where((operation) => operation.prefix != ' ')
          .length,
    );
  }

  static TurnDiffFile mergeFileDiffs(Iterable<TurnDiffFile> files) {
    final values = files.toList(growable: false);
    if (values.isEmpty) {
      return const TurnDiffFile(filePath: '');
    }
    if (values.length == 1) {
      return values.single;
    }

    final patchLines = <String>[];
    var truncated = false;
    for (final file in values) {
      final patch = file.unifiedPatch.trimRight();
      if (patch.isEmpty) {
        continue;
      }
      if (patchLines.isNotEmpty) {
        patchLines.add('');
      }
      patchLines.addAll(const LineSplitter().convert(patch));
      truncated = truncated || file.isTruncated;
    }
    final truncation = _truncatePatchLines(patchLines);

    return TurnDiffFile(
      filePath: values.first.filePath,
      isNewFile: values.any((file) => file.isNewFile),
      isDeletedFile: values.any((file) => file.isDeletedFile),
      isBinary: values.any((file) => file.isBinary),
      isLargeFile: values.any((file) => file.isLargeFile),
      isTruncated: truncated || truncation.truncated,
      isUntracked: values.any((file) => file.isUntracked),
      linesAdded: values.fold<int>(0, (sum, file) => sum + file.linesAdded),
      linesRemoved: values.fold<int>(0, (sum, file) => sum + file.linesRemoved),
      unifiedPatch: truncation.text,
      note: values
          .map((file) => file.note.trim())
          .where((note) => note.isNotEmpty)
          .join('\n'),
    );
  }

  static TurnDiff buildTurnDiff({
    required String assistantMessageId,
    required String userPrompt,
    required Iterable<TurnDiffFile> files,
    TurnDiffSource source = TurnDiffSource.tool,
    DateTime? timestamp,
    String? id,
  }) {
    final merged = _mergeByPath(files);
    final changedPaths = merged
        .where((file) => file.filePath.trim().isNotEmpty && file.hasChanges)
        .map((file) => file.filePath)
        .toList(growable: false);
    return TurnDiff(
      id: id ?? const Uuid().v4(),
      assistantMessageId: assistantMessageId,
      userPromptPreview: previewPrompt(userPrompt),
      timestamp: timestamp ?? DateTime.now(),
      source: source,
      files: merged,
      filesChanged: changedPaths.length,
      linesAdded: merged.fold<int>(0, (sum, file) => sum + file.linesAdded),
      linesRemoved: merged.fold<int>(0, (sum, file) => sum + file.linesRemoved),
      changedFilePaths: changedPaths,
    );
  }

  static String previewPrompt(String prompt) {
    final normalized = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= promptPreviewLength) {
      return normalized;
    }
    return '${normalized.substring(0, promptPreviewLength - 1)}...';
  }

  static TurnDiffFile fileFromGitPatch({
    required String filePath,
    required int linesAdded,
    required int linesRemoved,
    required String unifiedPatch,
    bool isBinary = false,
    bool isUntracked = false,
  }) {
    final lines = unifiedPatch.trimRight().isEmpty
        ? const <String>[]
        : const LineSplitter().convert(unifiedPatch.trimRight());
    final truncation = _truncatePatchLines(lines);
    return TurnDiffFile(
      filePath: filePath,
      isBinary: isBinary,
      isUntracked: isUntracked,
      isTruncated: truncation.truncated,
      linesAdded: linesAdded,
      linesRemoved: linesRemoved,
      unifiedPatch: truncation.text,
    );
  }

  static Map<String, GitNumstatEntry> parseGitNumstat(String output) {
    final entries = <String, GitNumstatEntry>{};
    for (final line in const LineSplitter().convert(output)) {
      if (line.trim().isEmpty) {
        continue;
      }
      final parts = line.split('\t');
      if (parts.length < 3) {
        continue;
      }
      final path = _normalizeGitPath(parts.sublist(2).join('\t'));
      if (path.isEmpty) {
        continue;
      }
      final isBinary = parts[0] == '-' || parts[1] == '-';
      entries[path] = GitNumstatEntry(
        filePath: path,
        linesAdded: isBinary ? 0 : int.tryParse(parts[0]) ?? 0,
        linesRemoved: isBinary ? 0 : int.tryParse(parts[1]) ?? 0,
        isBinary: isBinary,
      );
    }
    return entries;
  }

  static Map<String, String> splitGitPatchesByPath(String output) {
    final lines = const LineSplitter().convert(output);
    final patches = <String, String>{};
    var currentPath = '';
    var buffer = <String>[];

    void flush() {
      if (currentPath.isEmpty || buffer.isEmpty) {
        buffer = <String>[];
        return;
      }
      patches[currentPath] = buffer.join('\n');
      buffer = <String>[];
    }

    for (final line in lines) {
      if (line.startsWith('diff --git ')) {
        flush();
        currentPath = _pathFromDiffGitLine(line);
      }
      if (currentPath.isNotEmpty) {
        buffer.add(line);
        if (line.startsWith('+++ ')) {
          final path = _pathFromPatchHeader(line.substring(4));
          if (path.isNotEmpty && path != '/dev/null') {
            currentPath = path;
          }
        }
      }
    }
    flush();
    return patches;
  }

  static List<TurnDiffFile> buildGitFiles({
    required String numstatOutput,
    required String patchOutput,
  }) {
    final stats = parseGitNumstat(numstatOutput);
    final patches = splitGitPatchesByPath(patchOutput);
    final paths = <String>{...stats.keys, ...patches.keys}.toList()..sort();
    return [
      for (final path in paths)
        fileFromGitPatch(
          filePath: path,
          linesAdded: stats[path]?.linesAdded ?? 0,
          linesRemoved: stats[path]?.linesRemoved ?? 0,
          unifiedPatch: patches[path] ?? '',
          isBinary: stats[path]?.isBinary ?? false,
        ),
    ];
  }

  static List<TurnDiffFile> _mergeByPath(Iterable<TurnDiffFile> files) {
    final grouped = <String, List<TurnDiffFile>>{};
    for (final file in files) {
      final path = file.filePath.trim();
      if (path.isEmpty || !file.hasChanges) {
        continue;
      }
      grouped.putIfAbsent(path, () => <TurnDiffFile>[]).add(file);
    }
    final merged = [
      for (final entry in grouped.entries) mergeFileDiffs(entry.value),
    ]..sort((a, b) => a.filePath.compareTo(b.filePath));
    return merged;
  }

  static _PatchTruncation _truncatePatchLines(List<String> lines) {
    final buffer = StringBuffer();
    var lineCount = 0;
    var charCount = 0;
    var truncated = false;

    for (final line in lines) {
      final separatorLength = lineCount == 0 ? 0 : 1;
      if (lineCount >= maxPatchLines ||
          charCount + separatorLength + line.length > maxPatchChars) {
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
      buffer.write('... diff truncated ...');
    }

    return _PatchTruncation(buffer.toString(), truncated);
  }

  static String _normalizeGitPath(String rawPath) {
    final path = rawPath.trim();
    if (path.isEmpty) {
      return '';
    }
    if (!path.contains('{') || !path.contains('=>') || !path.contains('}')) {
      return path;
    }
    final suffix = path.substring(path.lastIndexOf('=>') + 2);
    final close = suffix.indexOf('}');
    if (close < 0) {
      return path;
    }
    final tail = suffix.substring(close + 1);
    return '${suffix.substring(0, close).trim()}$tail'.trim();
  }

  static String _pathFromDiffGitLine(String line) {
    final match = RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(line);
    if (match == null) {
      return '';
    }
    return _normalizeGitPath(match.group(2) ?? '');
  }

  static String _pathFromPatchHeader(String rawHeaderPath) {
    final path = rawHeaderPath.trim();
    if (path == '/dev/null') {
      return path;
    }
    if (path.startsWith('b/')) {
      return path.substring(2);
    }
    return path;
  }

  static List<String> _splitLines(String? content) {
    if (content == null || content.isEmpty) {
      return const [];
    }
    return const LineSplitter().convert(content);
  }

  static List<_DiffOp> _buildDiffOperations(
    List<String> oldLines,
    List<String> newLines,
  ) {
    final cellCount = oldLines.length * newLines.length;
    if (cellCount <= maxLcsCells) {
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
            : math.max(lcs[i + 1][j], lcs[i][j + 1]);
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
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
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

    return [
      for (var index = 0; index < prefix; index++)
        _DiffOp(' ', oldLines[index]),
      for (var index = prefix; index < oldLines.length - suffix; index++)
        _DiffOp('-', oldLines[index]),
      for (var index = prefix; index < newLines.length - suffix; index++)
        _DiffOp('+', newLines[index]),
      for (var index = 0; index < suffix; index++)
        _DiffOp(' ', oldLines[oldLines.length - suffix + index]),
    ];
  }

  static _OperationStats _countOperationStats(List<_DiffOp> operations) {
    var added = 0;
    var removed = 0;
    for (final operation in operations) {
      switch (operation.prefix) {
        case '+':
          added += 1;
          break;
        case '-':
          removed += 1;
          break;
      }
    }
    return _OperationStats(added: added, removed: removed);
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
      final start = math.max(0, index - 3);
      final end = math.min(operations.length - 1, index + 3);
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
}

class GitNumstatEntry {
  const GitNumstatEntry({
    required this.filePath,
    required this.linesAdded,
    required this.linesRemoved,
    required this.isBinary,
  });

  final String filePath;
  final int linesAdded;
  final int linesRemoved;
  final bool isBinary;
}

class _PatchTruncation {
  const _PatchTruncation(this.text, this.truncated);

  final String text;
  final bool truncated;
}

class _OperationStats {
  const _OperationStats({required this.added, required this.removed});

  final int added;
  final int removed;
}

class _DiffOp {
  const _DiffOp(this.prefix, this.line);

  final String prefix;
  final String line;
}
