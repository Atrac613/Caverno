import 'dart:convert';
import 'dart:io';

import 'filesystem_tools.dart';

/// Outcome of one internal `grep` invocation, shaped like a process result.
typedef LocalShellGrepResult = ({int exitCode, String stdout, String stderr});

/// A bounded Dart implementation of the `grep` subset models actually use.
///
/// `grep` reached the native shell until this existed, so every
/// `grep -E '^version:' pubspec.yaml` needed a fresh SEC4.4g host-write
/// approval -- 52 of the 255 such prompts in the approval audit. Running it
/// here keeps SEC4.1's invariant: a command the read-only shortcut accepts is
/// executed by Caverno itself, never by `sh -c`.
///
/// [parse] is the single authority for what is supported. It returns null for
/// anything this class cannot reproduce faithfully -- an unknown flag, `-R`
/// (which follows symlinks out of the project), stdin input, or a pattern
/// whose POSIX meaning Dart's `RegExp` would change. A null sends the command
/// down the ordinary gated shell path instead of failing it, so nothing that
/// worked with approval before stops working. The same parse supplies
/// [readPaths] to the project read fence and drives [execute], so the paths
/// that are fenced are exactly the paths that are read.
final class LocalShellGrep {
  LocalShellGrep._({
    required this.readPaths,
    required bool implicitRoot,
    required RegExp matcher,
    required bool invert,
    required bool lineNumbers,
    required bool count,
    required bool filesWithMatches,
    required bool filesWithoutMatch,
    required bool onlyMatching,
    required bool quiet,
    required bool noMessages,
    required bool recursive,
    required bool withFilename,
    required bool skipBinary,
    required int? maxCount,
    required int before,
    required int after,
    required List<RegExp> includes,
    required List<RegExp> excludes,
    required List<RegExp> excludeDirs,
  }) : _implicitRoot = implicitRoot,
       _matcher = matcher,
       _invert = invert,
       _lineNumbers = lineNumbers,
       _count = count,
       _filesWithMatches = filesWithMatches,
       _filesWithoutMatch = filesWithoutMatch,
       _onlyMatching = onlyMatching,
       _quiet = quiet,
       _noMessages = noMessages,
       _recursive = recursive,
       _withFilename = withFilename,
       _skipBinary = skipBinary,
       _maxCount = maxCount,
       _before = before,
       _after = after,
       _includes = includes,
       _excludes = excludes,
       _excludeDirs = excludeDirs;

  /// Every filesystem operand this invocation reads, as written.
  final List<String> readPaths;

  final bool _implicitRoot;
  final RegExp _matcher;
  final bool _invert;
  final bool _lineNumbers;
  final bool _count;
  final bool _filesWithMatches;
  final bool _filesWithoutMatch;
  final bool _onlyMatching;
  final bool _quiet;
  final bool _noMessages;
  final bool _recursive;
  final bool _withFilename;
  final bool _skipBinary;
  final int? _maxCount;
  final int _before;
  final int _after;
  final List<RegExp> _includes;
  final List<RegExp> _excludes;
  final List<RegExp> _excludeDirs;

  /// Files above this size are reported as an error rather than read whole.
  static const int maxFileBytes = 32 * 1024 * 1024;

  /// Wall-clock budget for one invocation. Matches the shell path's timeout.
  static const Duration searchBudget = Duration(seconds: 60);

  static const String _wordChar = 'A-Za-z0-9_';

  /// Parses grep's arguments (without the leading `grep`), or returns null
  /// when the invocation is outside the supported subset.
  static LocalShellGrep? parse(List<String> args) {
    var extended = false;
    var fixed = false;
    var ignoreCase = false;
    var lineNumbers = false;
    var invert = false;
    var count = false;
    var filesWithMatches = false;
    var filesWithoutMatch = false;
    var word = false;
    var wholeLine = false;
    var onlyMatching = false;
    var quiet = false;
    var noMessages = false;
    var recursive = false;
    var skipBinary = false;
    bool? withFilename;
    int? maxCount;
    int? before;
    int? after;
    int? context;
    final patterns = <String>[];
    final operands = <String>[];
    final includes = <String>[];
    final excludes = <String>[];
    final excludeDirs = <String>[];

    int? parseCount(String value) {
      final parsed = int.tryParse(value);
      return parsed == null || parsed < 0 ? null : parsed;
    }

    var optionsEnded = false;
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (optionsEnded || arg == '-' || !arg.startsWith('-')) {
        // `-` alone reads stdin, which an internal command does not have.
        if (arg == '-') return null;
        operands.add(arg);
        continue;
      }
      if (arg == '--') {
        optionsEnded = true;
        continue;
      }

      if (arg.startsWith('--')) {
        final equals = arg.indexOf('=');
        final name = equals < 0 ? arg.substring(2) : arg.substring(2, equals);
        String? inlineValue = equals < 0 ? null : arg.substring(equals + 1);
        String? takeValue() {
          if (inlineValue != null) return inlineValue;
          if (index + 1 >= args.length) return null;
          index += 1;
          return args[index];
        }

        bool flag() => inlineValue == null;
        switch (name) {
          case 'extended-regexp':
            if (!flag()) return null;
            extended = true;
            fixed = false;
          case 'basic-regexp':
            if (!flag()) return null;
            extended = false;
            fixed = false;
          case 'fixed-strings':
            if (!flag()) return null;
            fixed = true;
          case 'ignore-case':
            if (!flag()) return null;
            ignoreCase = true;
          case 'no-ignore-case':
            if (!flag()) return null;
            ignoreCase = false;
          case 'line-number':
            if (!flag()) return null;
            lineNumbers = true;
          case 'invert-match':
            if (!flag()) return null;
            invert = true;
          case 'count':
            if (!flag()) return null;
            count = true;
          case 'files-with-matches':
            if (!flag()) return null;
            filesWithMatches = true;
          case 'files-without-match':
            if (!flag()) return null;
            filesWithoutMatch = true;
          case 'word-regexp':
            if (!flag()) return null;
            word = true;
          case 'line-regexp':
            if (!flag()) return null;
            wholeLine = true;
          case 'only-matching':
            if (!flag()) return null;
            onlyMatching = true;
          case 'quiet' || 'silent':
            if (!flag()) return null;
            quiet = true;
          case 'no-messages':
            if (!flag()) return null;
            noMessages = true;
          case 'recursive':
            if (!flag()) return null;
            recursive = true;
          case 'with-filename':
            if (!flag()) return null;
            withFilename = true;
          case 'no-filename':
            if (!flag()) return null;
            withFilename = false;
          case 'color' || 'colour':
            // Output is never a terminal, so `auto` is `never`.
            if (inlineValue != null &&
                inlineValue != 'never' &&
                inlineValue != 'auto') {
              return null;
            }
          case 'regexp':
            final value = takeValue();
            if (value == null) return null;
            patterns.add(value);
          case 'max-count':
            final value = takeValue();
            maxCount = value == null ? null : parseCount(value);
            if (maxCount == null) return null;
          case 'after-context':
            final value = takeValue();
            after = value == null ? null : parseCount(value);
            if (after == null) return null;
          case 'before-context':
            final value = takeValue();
            before = value == null ? null : parseCount(value);
            if (before == null) return null;
          case 'context':
            final value = takeValue();
            context = value == null ? null : parseCount(value);
            if (context == null) return null;
          case 'include' || 'exclude' || 'exclude-dir':
            final value = takeValue();
            if (value == null) return null;
            (name == 'include'
                    ? includes
                    : name == 'exclude'
                    ? excludes
                    : excludeDirs)
                .add(value);
          default:
            return null;
        }
        continue;
      }

      // A cluster of short options such as `-rn` or `-nA3`.
      for (var charIndex = 1; charIndex < arg.length; charIndex++) {
        final option = arg[charIndex];
        if ('emABC'.contains(option)) {
          final String value;
          if (charIndex + 1 < arg.length) {
            value = arg.substring(charIndex + 1);
          } else if (index + 1 < args.length) {
            index += 1;
            value = args[index];
          } else {
            return null;
          }
          switch (option) {
            case 'e':
              patterns.add(value);
            case 'm':
              maxCount = parseCount(value);
              if (maxCount == null) return null;
            case 'A':
              after = parseCount(value);
              if (after == null) return null;
            case 'B':
              before = parseCount(value);
              if (before == null) return null;
            case 'C':
              context = parseCount(value);
              if (context == null) return null;
          }
          break;
        }
        switch (option) {
          case 'E':
            extended = true;
            fixed = false;
          case 'G':
            extended = false;
            fixed = false;
          case 'F':
            fixed = true;
          case 'i':
            ignoreCase = true;
          case 'n':
            lineNumbers = true;
          case 'v':
            invert = true;
          case 'c':
            count = true;
          case 'l':
            filesWithMatches = true;
          case 'L':
            filesWithoutMatch = true;
          case 'w':
            word = true;
          case 'x':
            wholeLine = true;
          case 'o':
            onlyMatching = true;
          case 'q':
            quiet = true;
          case 's':
            noMessages = true;
          case 'r':
            recursive = true;
          case 'h':
            withFilename = false;
          case 'H':
            withFilename = true;
          case 'I':
            skipBinary = true;
          default:
            // Includes -R, which follows symlinks during recursion and could
            // walk out of the fenced root.
            return null;
        }
      }
    }

    if (patterns.isEmpty) {
      if (operands.isEmpty) return null;
      patterns.add(operands.removeAt(0));
    }
    // Without a file operand grep reads stdin, unless it is recursive.
    final implicitRoot = operands.isEmpty;
    if (implicitRoot && !recursive) return null;

    final matcher = _compile(
      patterns,
      extended: extended,
      fixed: fixed,
      ignoreCase: ignoreCase,
      word: word,
      wholeLine: wholeLine,
    );
    if (matcher == null) return null;

    final includeMatchers = _compileGlobs(includes);
    final excludeMatchers = _compileGlobs(excludes);
    final excludeDirMatchers = _compileGlobs(excludeDirs);
    if (includeMatchers == null ||
        excludeMatchers == null ||
        excludeDirMatchers == null) {
      return null;
    }

    return LocalShellGrep._(
      readPaths: implicitRoot ? const ['.'] : List.unmodifiable(operands),
      implicitRoot: implicitRoot,
      matcher: matcher,
      invert: invert,
      lineNumbers: lineNumbers,
      count: count,
      filesWithMatches: filesWithMatches,
      filesWithoutMatch: filesWithoutMatch,
      onlyMatching: onlyMatching,
      quiet: quiet,
      noMessages: noMessages,
      recursive: recursive,
      withFilename: withFilename ?? (recursive || operands.length > 1),
      skipBinary: skipBinary,
      maxCount: maxCount,
      before: before ?? context ?? 0,
      after: after ?? context ?? 0,
      includes: includeMatchers,
      excludes: excludeMatchers,
      excludeDirs: excludeDirMatchers,
    );
  }

  /// Runs the search. Stops early once [outputLimit] characters of output
  /// exist, because the caller truncates there anyway.
  Future<LocalShellGrepResult> execute({
    required String workingDirectory,
    required int outputLimit,
  }) async {
    final run = _GrepRun(this, outputLimit);
    for (final operand in readPaths) {
      if (run.finished) break;
      final resolved = FilesystemTools.resolvePath(
        operand,
        defaultRoot: workingDirectory,
      );
      if (resolved == null) {
        run.error('$operand: cannot resolve path');
        continue;
      }
      final type = await FileSystemEntity.type(resolved);
      switch (type) {
        case FileSystemEntityType.directory:
          if (!_recursive) {
            run.error('$operand: Is a directory');
            continue;
          }
          await _walk(run, resolved, _implicitRoot ? '' : operand);
        case FileSystemEntityType.file:
          if (_fileSelected(_basename(operand))) {
            await _searchFile(run, resolved, operand);
          }
        case FileSystemEntityType.notFound:
          run.error('$operand: No such file or directory');
        default:
          run.error('$operand: Not a regular file');
      }
    }
    return run.result();
  }

  Future<void> _walk(_GrepRun run, String directory, String display) async {
    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(directory).list(followLinks: false).toList();
    } on FileSystemException catch (error) {
      run.error(
        '${display.isEmpty ? '.' : display}: '
        '${error.osError?.message ?? error.message}',
      );
      return;
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      if (run.finished) return;
      final name = _basename(entry.path);
      final childDisplay = display.isEmpty
          ? name
          : display.endsWith('/')
          ? '$display$name'
          : '$display/$name';
      // Symlinks met during recursion are skipped, as GNU `grep -r` does.
      // Following them could also leave the fenced project root.
      if (entry is Directory) {
        if (_excludeDirs.any((glob) => glob.hasMatch(name))) continue;
        await _walk(run, entry.path, childDisplay);
      } else if (entry is File && _fileSelected(name)) {
        await _searchFile(run, entry.path, childDisplay);
      }
    }
  }

  bool _fileSelected(String name) {
    if (_includes.isNotEmpty && !_includes.any((glob) => glob.hasMatch(name))) {
      return false;
    }
    return !_excludes.any((glob) => glob.hasMatch(name));
  }

  Future<void> _searchFile(_GrepRun run, String path, String display) async {
    if (run.pastDeadline) {
      run.error('search stopped after ${searchBudget.inSeconds} s');
      run.finished = true;
      return;
    }
    final List<int> bytes;
    try {
      final file = File(path);
      if (await file.length() > maxFileBytes) {
        run.error('$display: larger than the internal grep limit');
        return;
      }
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error) {
      run.error('$display: ${error.osError?.message ?? error.message}');
      return;
    }

    var binary = bytes.contains(0);
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      binary = true;
      content = utf8.decode(bytes, allowMalformed: true);
    }
    if (binary && _skipBinary) return;

    final lines = content.split('\n');
    if (content.endsWith('\n')) lines.removeLast();
    _searchLines(run, lines, display, binary: binary);
  }

  void _searchLines(
    _GrepRun run,
    List<String> lines,
    String display, {
    required bool binary,
  }) {
    final listsFiles = _filesWithMatches || _filesWithoutMatch;
    final printsLines = !_quiet && !listsFiles && !_count && !binary;
    final prefix = _withFilename ? display : null;

    var selectedCount = 0;
    var lastPrinted = -1;
    var afterRemaining = 0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final selected = _matcher.hasMatch(line) != _invert;
      final reachedMax = _maxCount != null && selectedCount >= _maxCount;

      if (selected && !reachedMax) {
        selectedCount += 1;
        run.anySelected = true;
        if (_quiet) {
          run.finished = true;
          return;
        }
        if (listsFiles) break;
        if (!printsLines) continue;

        if (_onlyMatching) {
          if (!_invert) {
            for (final match in _matcher.allMatches(line)) {
              final text = match.group(0)!;
              if (text.isEmpty) continue;
              run.write(_formatLine(prefix, index + 1, ':', text));
            }
          }
        } else {
          final from = index - _before < 0 ? 0 : index - _before;
          final start = from > lastPrinted ? from : lastPrinted + 1;
          // A group in a new file is always separated from the last one.
          if (_hasContext &&
              run.printedGroup &&
              (lastPrinted < 0 || start > lastPrinted + 1)) {
            run.write('--\n');
          }
          for (var ctx = start; ctx < index; ctx++) {
            run.write(_formatLine(prefix, ctx + 1, '-', lines[ctx]));
          }
          run.write(_formatLine(prefix, index + 1, ':', line));
          run.printedGroup = true;
          lastPrinted = index;
          afterRemaining = _after;
        }
      } else if (printsLines && !_onlyMatching && afterRemaining > 0) {
        run.write(_formatLine(prefix, index + 1, '-', line));
        lastPrinted = index;
        afterRemaining -= 1;
      } else if (reachedMax && afterRemaining == 0) {
        break;
      }
      if (run.finished) return;
    }

    if (_filesWithMatches && selectedCount > 0) {
      run.write('$display\n');
    } else if (_filesWithoutMatch && selectedCount == 0) {
      run.write('$display\n');
      run.anyListedWithout = true;
    } else if (!listsFiles && _count && !_quiet) {
      run.write(
        prefix == null ? '$selectedCount\n' : '$prefix:$selectedCount\n',
      );
    } else if (binary && !listsFiles && !_quiet && selectedCount > 0) {
      run.write('Binary file $display matches\n');
    }
  }

  bool get _hasContext => _before > 0 || _after > 0;

  String _formatLine(String? prefix, int lineNumber, String sep, String text) {
    final buffer = StringBuffer();
    if (prefix != null) buffer.write('$prefix$sep');
    if (_lineNumbers) buffer.write('$lineNumber$sep');
    buffer
      ..write(text)
      ..write('\n');
    return buffer.toString();
  }

  static String _basename(String path) {
    var trimmed = path;
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split(RegExp(r'[\\/]')).last;
  }

  static RegExp? _compile(
    List<String> patterns, {
    required bool extended,
    required bool fixed,
    required bool ignoreCase,
    required bool word,
    required bool wholeLine,
  }) {
    final alternatives = <String>[];
    for (final pattern in patterns) {
      // A newline separates patterns, as grep documents.
      for (final part in pattern.split('\n')) {
        final translated = fixed
            ? RegExp.escape(part)
            : translatePattern(part, extended: extended);
        if (translated == null || hasNestedQuantifier(translated)) {
          return null;
        }
        alternatives.add(translated);
      }
    }
    var source = alternatives.map((value) => '(?:$value)').join('|');
    if (wholeLine) {
      source = '^(?:$source)\$';
    } else if (word) {
      source = '(?<![$_wordChar])(?:$source)(?![$_wordChar])';
    }
    try {
      // dotAll: POSIX `.` matches a carriage return, Dart's does not.
      return RegExp(source, caseSensitive: !ignoreCase, dotAll: true);
    } on FormatException {
      return null;
    }
  }

  static List<RegExp>? _compileGlobs(List<String> globs) {
    final result = <RegExp>[];
    for (final glob in globs) {
      final matcher = _globToRegExp(glob);
      if (matcher == null) return null;
      result.add(matcher);
    }
    return result;
  }

  /// fnmatch-style `*`, `?` and `[...]`. Brace alternatives are a shell
  /// feature, not grep's, so they are left to the shell path.
  static RegExp? _globToRegExp(String glob) {
    final buffer = StringBuffer('^');
    for (var index = 0; index < glob.length; index++) {
      final char = glob[index];
      switch (char) {
        case '*':
          buffer.write('.*');
        case '?':
          buffer.write('.');
        case '[':
          final end = glob.indexOf(']', index + 2);
          if (end < 0) return null;
          var body = glob.substring(index + 1, end);
          if (body.contains('[') || body.contains(r'\')) return null;
          if (body.startsWith('!')) body = '^${body.substring(1)}';
          buffer.write('[$body]');
          index = end;
        case '{' || '}' || r'\':
          return null;
        default:
          buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    try {
      return RegExp(buffer.toString());
    } on FormatException {
      return null;
    }
  }

  /// Translates one POSIX basic or extended regular expression into Dart
  /// syntax, or returns null when the translation would change its meaning.
  ///
  /// Rejected rather than approximated: back-references, `\<`/`\>`, escapes
  /// POSIX lacks but Dart honours (`\d`), `(?`, stacked quantifiers (Dart
  /// reads `*?` as lazy), and equivalence or collating classes.
  static String? translatePattern(String pattern, {required bool extended}) {
    final out = StringBuffer();
    var index = 0;
    // Whether the previous token is an atom a quantifier may follow.
    var atomBefore = false;
    // Whether the previous token was itself a quantifier.
    var quantified = false;
    // BRE: `^` anchors only at the start of the pattern or of an alternative.
    var alternativeStart = true;

    void atom(String text) {
      out.write(text);
      atomBefore = true;
      quantified = false;
      alternativeStart = false;
    }

    bool quantifier(String text) {
      if (!atomBefore || quantified) return false;
      out.write(text);
      quantified = true;
      alternativeStart = false;
      return true;
    }

    void structural(String text, {required bool opensAlternative}) {
      out.write(text);
      atomBefore = !opensAlternative;
      quantified = false;
      alternativeStart = opensAlternative;
    }

    // Reads an interval body `n`, `n,`, `n,m` or `,m` ending at [close].
    String? interval(String close) {
      final end = pattern.indexOf(close, index);
      if (end < 0) return null;
      final body = pattern.substring(index, end);
      final match = RegExp(r'^(\d*)(,(\d*))?$').firstMatch(body);
      if (match == null) return null;
      final low = match.group(1)!;
      final comma = match.group(2) != null;
      final high = match.group(3) ?? '';
      if (low.isEmpty && !comma) return null;
      if (low.isNotEmpty &&
          high.isNotEmpty &&
          int.parse(low) > int.parse(high)) {
        return null;
      }
      index = end + close.length;
      return '{${low.isEmpty ? '0' : low}${comma ? ',$high' : ''}}';
    }

    while (index < pattern.length) {
      final char = pattern[index];

      if (char == r'\') {
        if (index + 1 >= pattern.length) return null;
        final next = pattern[index + 1];
        index += 2;
        if (!extended && '(){}|+?'.contains(next)) {
          switch (next) {
            case '(':
              structural('(', opensAlternative: true);
            case ')':
              structural(')', opensAlternative: false);
            case '|':
              structural('|', opensAlternative: true);
            case '{':
              final body = interval(r'\}');
              if (body == null || !quantifier(body)) return null;
            case '+' || '?':
              if (!quantifier(next)) return null;
            default:
              return null;
          }
          continue;
        }
        if (r'.*[]^$\/'.contains(next) ||
            (extended && '(){}|+?'.contains(next))) {
          atom('\\$next');
          continue;
        }
        if ('wWsS'.contains(next)) {
          atom('\\$next');
          continue;
        }
        if ('bB'.contains(next)) {
          out.write('\\$next');
          atomBefore = false;
          quantified = false;
          continue;
        }
        return null;
      }

      if (char == '[') {
        final bracket = _translateBracket(pattern, index);
        if (bracket == null) return null;
        index = bracket.end;
        atom(bracket.source);
        continue;
      }

      index += 1;
      if (!extended) {
        switch (char) {
          case '^':
            if (alternativeStart) {
              out.write('^');
              alternativeStart = false;
              atomBefore = false;
            } else {
              atom(r'\^');
            }
          case r'$':
            final atEnd =
                index == pattern.length ||
                pattern.startsWith(r'\)', index) ||
                pattern.startsWith(r'\|', index);
            if (atEnd) {
              out.write(r'$');
              atomBefore = false;
              quantified = false;
            } else {
              atom(r'\$');
            }
          case '*':
            // A leading `*` is literal in a basic expression.
            if (!atomBefore) {
              atom(r'\*');
            } else if (!quantifier('*')) {
              return null;
            }
          case '.':
            atom('.');
          default:
            atom(RegExp.escape(char));
        }
        continue;
      }

      switch (char) {
        case '(':
          if (index < pattern.length && pattern[index] == '?') return null;
          structural('(', opensAlternative: true);
        case ')':
          structural(')', opensAlternative: false);
        case '|':
          structural('|', opensAlternative: true);
        case '^':
          out.write('^');
          atomBefore = false;
          quantified = false;
        case r'$':
          out.write(r'$');
          atomBefore = false;
          quantified = false;
        case '*' || '+' || '?':
          if (!quantifier(char)) return null;
        case '{':
          final saved = index;
          final body = interval('}');
          if (body == null) {
            // Not an interval: GNU reads the brace literally.
            index = saved;
            atom(r'\{');
          } else if (!quantifier(body)) {
            return null;
          }
        case '.':
          atom('.');
        default:
          atom(RegExp.escape(char));
      }
    }
    return out.toString();
  }

  static const Map<String, String> _posixClasses = {
    'alpha': 'A-Za-z',
    'digit': '0-9',
    'alnum': 'A-Za-z0-9',
    'upper': 'A-Z',
    'lower': 'a-z',
    'space': r' \t\n\r\f\v',
    'blank': r' \t',
    'xdigit': '0-9A-Fa-f',
    'punct': r'!-\/:-@\[-`{-~',
  };

  /// Translates the bracket expression starting at [start].
  static ({String source, int end})? _translateBracket(
    String pattern,
    int start,
  ) {
    var index = start + 1;
    final out = StringBuffer('[');
    if (index < pattern.length && pattern[index] == '^') {
      out.write('^');
      index += 1;
    }
    var first = true;
    while (index < pattern.length) {
      final char = pattern[index];
      if (char == ']' && !first) {
        out.write(']');
        return (source: out.toString(), end: index + 1);
      }
      first = false;
      if (char == '[' && index + 1 < pattern.length) {
        final kind = pattern[index + 1];
        if (kind == '=' || kind == '.') return null;
        if (kind == ':') {
          final close = pattern.indexOf(':]', index + 2);
          if (close < 0) return null;
          final name = pattern.substring(index + 2, close);
          final replacement = _posixClasses[name];
          if (replacement == null) return null;
          out.write(replacement);
          index = close + 2;
          continue;
        }
      }
      // Inside a POSIX bracket a backslash is an ordinary character.
      out.write(switch (char) {
        r'\' => r'\\',
        '[' => r'\[',
        ']' => r'\]',
        _ => char,
      });
      index += 1;
    }
    return null;
  }

  /// Whether a translated pattern repeats a group that itself repeats or
  /// alternates, such as `(a+)+` or `(a|aa)*`.
  ///
  /// Dart's backtracking `RegExp` can take exponential time on those, and an
  /// internal command runs on the app's own isolate with no process to kill.
  /// Real grep is DFA-based and immune, so such patterns go to the shell path.
  static bool hasNestedQuantifier(String source) {
    final groupRisky = <bool>[];
    var closedRiskyGroup = false;
    var index = 0;
    while (index < source.length) {
      final char = source[index];
      switch (char) {
        case r'\':
          index += 2;
          closedRiskyGroup = false;
          continue;
        case '[':
          index += 1;
          if (index < source.length && source[index] == '^') index += 1;
          // The translator escapes every literal `]`, so the first unescaped
          // one closes the class.
          while (index < source.length && source[index] != ']') {
            index += source[index] == r'\' ? 2 : 1;
          }
          index += 1;
          closedRiskyGroup = false;
          continue;
        case '(':
          groupRisky.add(false);
        case ')':
          if (groupRisky.isEmpty) return true;
          final risky = groupRisky.removeLast();
          if (risky && groupRisky.isNotEmpty) groupRisky.last = true;
          closedRiskyGroup = risky;
          index += 1;
          continue;
        case '|':
          if (groupRisky.isNotEmpty) groupRisky.last = true;
        case '*' || '+' || '?' || '{':
          var unbounded = char != '?';
          if (char == '{') {
            final end = source.indexOf('}', index);
            final body = source.substring(index + 1, end);
            final parts = body.split(',');
            unbounded =
                parts.length == 2 &&
                (parts[1].isEmpty || int.parse(parts[1]) > 1);
            index = end;
          }
          if (unbounded && closedRiskyGroup) return true;
          if (groupRisky.isNotEmpty) groupRisky.last = true;
      }
      closedRiskyGroup = false;
      index += 1;
    }
    return false;
  }
}

final class _GrepRun {
  _GrepRun(this.grep, this.outputLimit) : _clock = Stopwatch()..start();

  final LocalShellGrep grep;
  final int outputLimit;
  final Stopwatch _clock;
  final StringBuffer _stdout = StringBuffer();
  final StringBuffer _stderr = StringBuffer();
  bool anySelected = false;
  bool anyListedWithout = false;
  bool hadError = false;
  bool finished = false;
  bool printedGroup = false;

  bool get pastDeadline => _clock.elapsed > LocalShellGrep.searchBudget;

  void write(String text) {
    _stdout.write(text);
    if (_stdout.length > outputLimit) finished = true;
  }

  void error(String message) {
    hadError = true;
    if (!grep._noMessages) _stderr.write('grep: $message\n');
  }

  LocalShellGrepResult result() {
    final succeeded = grep._filesWithoutMatch ? anyListedWithout : anySelected;
    final exitCode = hadError && !(grep._quiet && anySelected)
        ? 2
        : succeeded
        ? 0
        : 1;
    return (
      exitCode: exitCode,
      stdout: _stdout.toString(),
      stderr: _stderr.toString(),
    );
  }
}
