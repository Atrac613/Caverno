import 'dart:convert';

final class FilesystemDiffBuilder {
  FilesystemDiffBuilder._();

  static const int _maxPreviewLines = 400;
  static const int _maxPreviewChars = 12000;
  static const int _maxLcsCells = 60000;

  static String buildUnifiedDiff({
    required String path,
    required String? oldContent,
    required String? newContent,
  }) {
    final oldLines = _splitLines(oldContent);
    final newLines = _splitLines(newContent);
    final operations = _buildOperations(oldLines, newLines);
    final body = _renderBody(operations);

    return _truncatePreview([
      '--- ${oldContent == null ? "/dev/null" : path}',
      '+++ ${newContent == null ? "/dev/null" : path}',
      ...body,
    ]);
  }

  static String buildUnavailableMessage(
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
    return _truncatePreview(lines);
  }

  static List<String> _splitLines(String? content) {
    if (content == null || content.isEmpty) return const [];
    return const LineSplitter().convert(content);
  }

  static List<_DiffOperation> _buildOperations(
    List<String> oldLines,
    List<String> newLines,
  ) {
    final cellCount = oldLines.length * newLines.length;
    if (cellCount <= _maxLcsCells) {
      return _buildOperationsWithLcs(oldLines, newLines);
    }
    return _buildOperationsWithAnchors(oldLines, newLines);
  }

  static List<_DiffOperation> _buildOperationsWithLcs(
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

    final operations = <_DiffOperation>[];
    var i = 0;
    var j = 0;
    while (i < oldLines.length && j < newLines.length) {
      if (oldLines[i] == newLines[j]) {
        operations.add(_DiffOperation(' ', oldLines[i]));
        i += 1;
        j += 1;
        continue;
      }

      if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        operations.add(_DiffOperation('-', oldLines[i]));
        i += 1;
      } else {
        operations.add(_DiffOperation('+', newLines[j]));
        j += 1;
      }
    }

    while (i < oldLines.length) {
      operations.add(_DiffOperation('-', oldLines[i]));
      i += 1;
    }
    while (j < newLines.length) {
      operations.add(_DiffOperation('+', newLines[j]));
      j += 1;
    }

    return operations;
  }

  static List<_DiffOperation> _buildOperationsWithAnchors(
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

    return <_DiffOperation>[
      for (var index = 0; index < prefix; index++)
        _DiffOperation(' ', oldLines[index]),
      for (var index = prefix; index < oldLines.length - suffix; index++)
        _DiffOperation('-', oldLines[index]),
      for (var index = prefix; index < newLines.length - suffix; index++)
        _DiffOperation('+', newLines[index]),
      for (var index = 0; index < suffix; index++)
        _DiffOperation(' ', oldLines[oldLines.length - suffix + index]),
    ];
  }

  static List<String> _renderBody(List<_DiffOperation> operations) {
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

  static String _truncatePreview(List<String> lines) {
    final buffer = StringBuffer();
    var lineCount = 0;
    var charCount = 0;
    var truncated = false;

    for (final line in lines) {
      final separatorLength = lineCount == 0 ? 0 : 1;
      if (lineCount >= _maxPreviewLines ||
          charCount + separatorLength + line.length > _maxPreviewChars) {
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
}

final class _DiffOperation {
  const _DiffOperation(this.prefix, this.line);

  final String prefix;
  final String line;
}
