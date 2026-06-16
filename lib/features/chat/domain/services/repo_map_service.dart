import 'dart:convert';
import 'dart:io';
import 'dart:math';

class RepoMapService {
  RepoMapService._();

  static const defaultMaxFiles = 60;
  static const defaultMaxSymbols = 120;
  static const _maxVisitedEntries = 1800;
  static const _maxBytesPerFile = 16000;
  static const _defaultOutputChars = 6000;
  static const _minOutputChars = 2400;
  static const _maxOutputChars = 9000;

  static final RegExp _dartTypeDeclarationPattern = RegExp(
    r'^\s*(?:abstract\s+|base\s+|final\s+|interface\s+|sealed\s+|mixin\s+)*'
    r'(class|mixin|enum|extension|typedef)\s+([A-Za-z_]\w*)',
    multiLine: true,
  );
  static final RegExp _dartFunctionPattern = RegExp(
    r'^\s*(?:static\s+)?'
    r'(?:Future(?:<[^>\n]+>)?|Stream(?:<[^>\n]+>)?|void|bool|int|double|'
    r'num|String|Object|Map<[^>\n]+>|List<[^>\n]+>|Set<[^>\n]+>)\s+'
    r'([A-Za-z_]\w*)\s*\(',
    multiLine: true,
  );
  static final RegExp _dartProviderPattern = RegExp(
    r'^\s*final\s+([A-Za-z_]\w*Provider)\s*=',
    multiLine: true,
  );

  static String? buildForProject({
    required String? rootPath,
    int? usableContextTokens,
    int maxFiles = defaultMaxFiles,
    int maxSymbols = defaultMaxSymbols,
  }) {
    final normalizedRootPath = rootPath?.trim();
    if (normalizedRootPath == null || normalizedRootPath.isEmpty) return null;

    final root = Directory(normalizedRootPath);
    if (!root.existsSync()) return null;

    final files = _scanFiles(root)..sort(_compareFiles);
    if (files.isEmpty) return null;

    final fileLimit = maxFiles.clamp(1, defaultMaxFiles).toInt();
    final selectedFiles = files.take(fileLimit);
    final symbolEntries = <_RepoMapSymbolEntry>[];
    var remainingSymbols = maxSymbols.clamp(0, defaultMaxSymbols).toInt();
    for (final file in selectedFiles) {
      if (remainingSymbols <= 0) break;
      final symbols = _extractDartSymbols(file.file, limit: remainingSymbols);
      if (symbols.isEmpty) continue;
      symbolEntries.add(
        _RepoMapSymbolEntry(relativePath: file.relativePath, symbols: symbols),
      );
      remainingSymbols -= symbols.length;
    }

    final buffer = StringBuffer()
      ..writeln('Root: ${_displayPath(root.path)}')
      ..writeln('Key files:');
    for (final file in selectedFiles) {
      buffer.writeln('- ${file.relativePath}');
    }
    if (symbolEntries.isNotEmpty) {
      buffer.writeln('Dart symbols:');
      for (final entry in symbolEntries) {
        buffer.writeln('- ${entry.relativePath}: ${entry.symbols.join(', ')}');
      }
    }

    return _trimToBudget(
      buffer.toString().trim(),
      _charBudgetForTokens(usableContextTokens),
    );
  }

  /// Cheap fingerprint of every input that affects [buildForProject] output, so
  /// a precompute cache (LL22) can tell whether a stored map is still valid
  /// without re-running the expensive symbol extraction.
  ///
  /// The signature folds in the effective character budget (not the raw token
  /// count, since two token counts that clamp to the same budget produce an
  /// identical map), the file limits, and a `path:size:mtime` triple for each
  /// selected file. It is a stat-only walk: directory ranking/skip rules are
  /// shared with [buildForProject], but no file contents are read.
  ///
  /// Returns null when there is no buildable map (no root, missing directory,
  /// or no ranked files), matching [buildForProject].
  static String? computeSignatureForProject({
    required String? rootPath,
    int? usableContextTokens,
    int maxFiles = defaultMaxFiles,
    int maxSymbols = defaultMaxSymbols,
  }) {
    final normalizedRootPath = rootPath?.trim();
    if (normalizedRootPath == null || normalizedRootPath.isEmpty) return null;

    final root = Directory(normalizedRootPath);
    if (!root.existsSync()) return null;

    final files = _scanFiles(root)..sort(_compareFiles);
    if (files.isEmpty) return null;

    final fileLimit = maxFiles.clamp(1, defaultMaxFiles).toInt();
    final symbolLimit = maxSymbols.clamp(0, defaultMaxSymbols).toInt();
    final selectedFiles = files.take(fileLimit);

    final buffer = StringBuffer()
      ..write('root=${_displayPath(root.path)}')
      ..write(';budget=${_charBudgetForTokens(usableContextTokens)}')
      ..write(';maxFiles=$fileLimit')
      ..write(';maxSymbols=$symbolLimit');
    for (final file in selectedFiles) {
      final stat = _safeStat(file.file);
      buffer.write(
        ';${file.relativePath}:${stat?.size ?? -1}:'
        '${stat?.modified.microsecondsSinceEpoch ?? -1}',
      );
    }
    return buffer.toString();
  }

  static FileStat? _safeStat(File file) {
    try {
      return file.statSync();
    } on FileSystemException {
      return null;
    }
  }

  static List<_RepoMapFile> _scanFiles(Directory root) {
    final files = <_RepoMapFile>[];
    final pendingDirectories = <Directory>[root];
    var visitedEntries = 0;

    while (pendingDirectories.isNotEmpty &&
        visitedEntries < _maxVisitedEntries) {
      final directory = pendingDirectories.removeAt(0);
      final children = _safeList(directory)..sort(_compareEntities);
      for (final child in children) {
        if (visitedEntries >= _maxVisitedEntries) break;
        visitedEntries += 1;

        final relativePath = _relativePath(child.path, root.path);
        if (relativePath.isEmpty) continue;
        final entityType = child.statSync().type;
        if (entityType == FileSystemEntityType.directory) {
          if (!_shouldSkipDirectory(relativePath)) {
            pendingDirectories.add(Directory(child.path));
          }
          continue;
        }
        if (entityType != FileSystemEntityType.file ||
            _shouldSkipFile(relativePath)) {
          continue;
        }

        final rank = _rankFile(relativePath);
        if (rank <= 0) continue;
        files.add(
          _RepoMapFile(
            file: File(child.path),
            relativePath: relativePath,
            rank: rank,
          ),
        );
      }
    }
    return files;
  }

  static List<FileSystemEntity> _safeList(Directory directory) {
    try {
      return directory.listSync(followLinks: false);
    } on FileSystemException {
      return const [];
    }
  }

  static int _compareEntities(FileSystemEntity a, FileSystemEntity b) {
    return _pathKey(a.path).compareTo(_pathKey(b.path));
  }

  static int _compareFiles(_RepoMapFile a, _RepoMapFile b) {
    final rankComparison = b.rank.compareTo(a.rank);
    if (rankComparison != 0) return rankComparison;
    return a.relativePath.compareTo(b.relativePath);
  }

  static bool _shouldSkipDirectory(String relativePath) {
    final segments = relativePath.split('/');
    final name = segments.last;
    if (_skippedDirectoryNames.contains(name)) return true;
    if (name.startsWith('.') && name != '.github') return true;
    return relativePath == 'ios/Pods' ||
        relativePath == 'macos/Pods' ||
        relativePath.endsWith('/flutter/ephemeral');
  }

  static bool _shouldSkipFile(String relativePath) {
    final lowerPath = relativePath.toLowerCase();
    final name = lowerPath.split('/').last;
    if (name.startsWith('.') && name != '.gitignore') return true;
    if (_skippedFileNames.contains(name)) return true;
    if (lowerPath.endsWith('.g.dart') ||
        lowerPath.endsWith('.freezed.dart') ||
        lowerPath.endsWith('.mocks.dart') ||
        lowerPath.endsWith('.gen.dart')) {
      return true;
    }
    return !_allowedExtensions.any(lowerPath.endsWith);
  }

  static int _rankFile(String relativePath) {
    if (relativePath == 'pubspec.yaml') return 1000;
    if (relativePath == 'README.md') return 980;
    if (relativePath == 'analysis_options.yaml') return 960;
    if (relativePath == 'lib/main.dart') return 940;
    if (relativePath.startsWith('lib/features/')) return 820;
    if (relativePath.startsWith('lib/')) return 780;
    if (relativePath.startsWith('test/')) return 650;
    if (relativePath.startsWith('integration_test/')) return 630;
    if (relativePath.startsWith('tool/')) return 520;
    if (relativePath.startsWith('docs/')) return 420;
    if (relativePath.startsWith('.github/')) return 360;
    return 220;
  }

  static List<String> _extractDartSymbols(File file, {required int limit}) {
    if (limit <= 0 || !file.path.toLowerCase().endsWith('.dart')) {
      return const [];
    }
    final contents = _readPrefix(file);
    if (contents.isEmpty) return const [];

    final symbols = <String>[];
    final seen = <String>{};
    void addSymbol(String symbol) {
      if (symbols.length >= limit || !seen.add(symbol)) return;
      symbols.add(symbol);
    }

    for (final match in _dartTypeDeclarationPattern.allMatches(contents)) {
      addSymbol('${match.group(1)} ${match.group(2)}');
    }
    for (final match in _dartProviderPattern.allMatches(contents)) {
      addSymbol('provider ${match.group(1)}');
    }
    for (final match in _dartFunctionPattern.allMatches(contents)) {
      addSymbol('function ${match.group(1)}');
    }
    return symbols;
  }

  static String _readPrefix(File file) {
    RandomAccessFile? openedFile;
    try {
      final length = min(file.lengthSync(), _maxBytesPerFile);
      openedFile = file.openSync();
      return utf8.decode(openedFile.readSync(length), allowMalformed: true);
    } on FileSystemException {
      return '';
    } finally {
      openedFile?.closeSync();
    }
  }

  static int _charBudgetForTokens(int? usableContextTokens) {
    if (usableContextTokens == null || usableContextTokens <= 0) {
      return _defaultOutputChars;
    }
    final scaledBudget = (usableContextTokens * 0.45).round();
    return scaledBudget.clamp(_minOutputChars, _maxOutputChars).toInt();
  }

  static String _trimToBudget(String text, int budget) {
    if (text.length <= budget) return text;
    const marker = '\n...';
    final targetLength = max(0, budget - marker.length);
    final lineBoundary = text.lastIndexOf('\n', targetLength);
    final cutLength = lineBoundary > 0 ? lineBoundary : targetLength;
    return '${text.substring(0, cutLength).trimRight()}$marker';
  }

  static String _relativePath(String path, String rootPath) {
    final normalizedPath = _pathKey(path);
    final normalizedRoot = _pathKey(rootPath).replaceFirst(RegExp(r'/+$'), '');
    if (normalizedPath == normalizedRoot) return '';
    final prefix = '$normalizedRoot/';
    if (!normalizedPath.startsWith(prefix)) return normalizedPath;
    return normalizedPath.substring(prefix.length);
  }

  static String _displayPath(String path) {
    return _pathKey(path).replaceFirst(RegExp(r'/+$'), '');
  }

  static String _pathKey(String path) {
    return path.replaceAll('\\', '/');
  }

  static const Set<String> _skippedDirectoryNames = {
    '.dart_tool',
    '.fvm',
    '.git',
    '.idea',
    '.symlinks',
    '.vscode',
    'DerivedData',
    'Pods',
    'build',
    'node_modules',
  };

  static const Set<String> _skippedFileNames = {
    'package-lock.json',
    'podfile.lock',
    'pubspec.lock',
    'yarn.lock',
  };

  static const List<String> _allowedExtensions = [
    '.dart',
    '.json',
    '.md',
    '.sh',
    '.yaml',
    '.yml',
  ];
}

class _RepoMapFile {
  const _RepoMapFile({
    required this.file,
    required this.relativePath,
    required this.rank,
  });

  final File file;
  final String relativePath;
  final int rank;
}

class _RepoMapSymbolEntry {
  const _RepoMapSymbolEntry({
    required this.relativePath,
    required this.symbols,
  });

  final String relativePath;
  final List<String> symbols;
}
