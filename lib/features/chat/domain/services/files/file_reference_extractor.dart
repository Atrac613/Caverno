import 'dart:convert';

class FileReference {
  const FileReference({required this.path, this.line});

  final String path;
  final int? line;

  String get label => line == null ? path : '$path:$line';
}

class FileReferenceExtractor {
  FileReferenceExtractor._();

  static const int defaultMaxReferences = 24;

  static final RegExp _pathPattern = RegExp(
    r'(?<![A-Za-z0-9_@:/.])'
    r'((?:[A-Za-z]:[\\/]|/|\.{1,2}[\\/])?[A-Za-z0-9._~+@-]+'
    r'(?:[\\/][A-Za-z0-9._~+@-]+)*\.[A-Za-z0-9]{1,12})'
    r'(?::(\d{1,7})(?::\d{1,7})?)?',
  );

  static final RegExp _namedFilePattern = RegExp(
    r'(?<![A-Za-z0-9_@:/.])'
    r'('
    r'AGENTS\.md|README(?:\.[A-Za-z0-9]{1,12})?|CHANGELOG\.md|'
    r'LICENSE(?:\.[A-Za-z0-9]{1,12})?|Dockerfile|Makefile|Gemfile|'
    r'Podfile|Rakefile|pubspec\.yaml|analysis_options\.yaml|'
    r'build\.gradle|settings\.gradle|Package\.swift|go\.mod|go\.sum|'
    r'Cargo\.toml|Cargo\.lock|package\.json|package-lock\.json|'
    r'pnpm-lock\.yaml|yarn\.lock|tsconfig\.json'
    r')'
    r'(?::(\d{1,7})(?::\d{1,7})?)?',
    caseSensitive: false,
  );

  static const Set<String> _knownBareExtensions = {
    'bash',
    'c',
    'cc',
    'cpp',
    'cs',
    'css',
    'csv',
    'dart',
    'env',
    'go',
    'gradle',
    'gql',
    'graphql',
    'h',
    'hpp',
    'html',
    'ini',
    'java',
    'jpeg',
    'jpg',
    'js',
    'json',
    'jsonl',
    'jsx',
    'kt',
    'kts',
    'lock',
    'm',
    'md',
    'mm',
    'plist',
    'png',
    'properties',
    'proto',
    'py',
    'rb',
    'rs',
    'sass',
    'scss',
    'sh',
    'sql',
    'storyboard',
    'svg',
    'svelte',
    'swift',
    'toml',
    'ts',
    'tsv',
    'tsx',
    'txt',
    'vue',
    'xcconfig',
    'xib',
    'xml',
    'yaml',
    'yml',
    'zsh',
  };

  static List<FileReference> extract(
    String content, {
    int maxReferences = defaultMaxReferences,
  }) {
    if (content.trim().isEmpty || maxReferences <= 0) {
      return const <FileReference>[];
    }

    final matches = _scanContent(content);
    final deduped = <String, FileReference>{};
    for (final match in matches) {
      final reference = FileReference(path: match.path, line: match.line);
      deduped.putIfAbsent(reference.label, () => reference);
      if (deduped.length >= maxReferences) {
        break;
      }
    }

    return deduped.values.toList(growable: false);
  }

  static List<_FileReferenceMatch> _scanContent(String content) {
    final matches = <_FileReferenceMatch>[];
    var insideFence = false;
    var offset = 0;
    final lines = content.split('\n');

    for (final line in lines) {
      if (line.trimLeft().startsWith('```')) {
        insideFence = !insideFence;
        offset += line.length + 1;
        continue;
      }

      if (!insideFence) {
        matches.addAll(_scanLine(line, offset));
      }
      offset += line.length + 1;
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static List<_FileReferenceMatch> _scanLine(String line, int lineOffset) {
    final matches = <_FileReferenceMatch>[];
    _collectMatches(line, lineOffset, _pathPattern, matches);
    _collectMatches(line, lineOffset, _namedFilePattern, matches);
    matches.sort((a, b) => a.start.compareTo(b.start));

    final nonOverlapping = <_FileReferenceMatch>[];
    var lastEnd = -1;
    for (final match in matches) {
      if (match.start < lastEnd) {
        continue;
      }
      nonOverlapping.add(match);
      lastEnd = match.end;
    }
    return nonOverlapping;
  }

  static void _collectMatches(
    String line,
    int lineOffset,
    RegExp pattern,
    List<_FileReferenceMatch> matches,
  ) {
    for (final match in pattern.allMatches(line)) {
      final path = match.group(1)?.trim();
      if (path == null || !_isLikelyFilePath(path)) {
        continue;
      }
      final lineNumber = int.tryParse(match.group(2) ?? '');
      matches.add(
        _FileReferenceMatch(
          path: path,
          line: lineNumber == null || lineNumber <= 0 ? null : lineNumber,
          start: lineOffset + match.start,
          end: lineOffset + match.end,
          localStart: match.start,
          localEnd: match.end,
        ),
      );
    }
  }

  static bool _isLikelyFilePath(String path) {
    if (path.length > 260 || path.contains('://')) {
      return false;
    }

    final normalized = path.replaceAll('\\', '/');
    final hasDirectory = normalized.contains('/');
    final extension = _extensionFor(normalized);
    if (extension == null) {
      return _namedFilePattern.hasMatch(path);
    }

    if (!hasDirectory && !_knownBareExtensions.contains(extension)) {
      return false;
    }

    return true;
  }

  static String? _extensionFor(String path) {
    final lastSegment = path.split('/').last;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == lastSegment.length - 1) {
      return null;
    }
    return lastSegment.substring(dotIndex + 1).toLowerCase();
  }
}

class FileReferenceMarkdownLinkifier {
  FileReferenceMarkdownLinkifier._();

  static const String scheme = 'caverno-file';

  static String linkify(String content) {
    if (content.trim().isEmpty) {
      return content;
    }

    final buffer = StringBuffer();
    var insideFence = false;
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        insideFence = !insideFence;
        buffer.write(line);
      } else if (insideFence) {
        buffer.write(line);
      } else {
        buffer.write(_linkifyLine(line));
      }

      if (i != lines.length - 1) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  static String hrefForPath(String path) {
    return '$scheme:${base64Url.encode(utf8.encode(path))}';
  }

  static String? decodeHref(String? href) {
    if (href == null || !href.startsWith('$scheme:')) {
      return null;
    }

    final payload = href.substring('$scheme:'.length);
    try {
      return utf8.decode(base64Url.decode(payload));
    } catch (_) {
      return null;
    }
  }

  static String _linkifyLine(String line) {
    final matches = FileReferenceExtractor._scanLine(line, 0);
    if (matches.isEmpty) {
      return line;
    }

    final codeRanges = _inlineCodeRanges(line);
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in matches) {
      if (match.localStart < cursor ||
          _isInsideAnyRange(match.localStart, match.localEnd, codeRanges) ||
          _looksLikeExistingMarkdownLink(line, match)) {
        continue;
      }

      buffer.write(line.substring(cursor, match.localStart));
      final label = line.substring(match.localStart, match.localEnd);
      buffer.write('[$label](${hrefForPath(match.path)})');
      cursor = match.localEnd;
    }
    buffer.write(line.substring(cursor));
    return buffer.toString();
  }

  static List<_TextRange> _inlineCodeRanges(String line) {
    final ranges = <_TextRange>[];
    var start = -1;
    for (var i = 0; i < line.length; i++) {
      if (line[i] != '`') {
        continue;
      }
      if (start == -1) {
        start = i;
      } else {
        ranges.add(_TextRange(start: start, end: i + 1));
        start = -1;
      }
    }
    return ranges;
  }

  static bool _isInsideAnyRange(int start, int end, List<_TextRange> ranges) {
    for (final range in ranges) {
      if (start >= range.start && end <= range.end) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikeExistingMarkdownLink(
    String line,
    _FileReferenceMatch match,
  ) {
    final isLinkLabel =
        match.localStart > 0 &&
        line[match.localStart - 1] == '[' &&
        match.localEnd < line.length &&
        line[match.localEnd] == ']';
    final isLinkTarget =
        match.localStart > 0 && line[match.localStart - 1] == '(';
    return isLinkLabel || isLinkTarget;
  }
}

class _FileReferenceMatch {
  const _FileReferenceMatch({
    required this.path,
    required this.line,
    required this.start,
    required this.end,
    required this.localStart,
    required this.localEnd,
  });

  final String path;
  final int? line;
  final int start;
  final int end;
  final int localStart;
  final int localEnd;
}

class _TextRange {
  const _TextRange({required this.start, required this.end});

  final int start;
  final int end;
}
