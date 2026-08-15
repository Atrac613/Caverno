import '../entities/flutter_run_issue.dart';
import '../entities/flutter_run_session.dart';

/// Cuts failure-shaped blocks out of run output.
///
/// Shape only: a block is recognised by the framing the toolchain prints
/// around it, never by whether its wording sounds bad. Deciding what a block
/// means -- or whether it is worth the user's attention at all -- belongs to
/// the analyser, so that a bad heuristic here can at worst waste one analysis
/// call, not silently rule a real failure out.
///
/// Runs over the whole buffer and is idempotent, so callers re-segment after
/// every batch of lines and drop signatures they have already seen instead of
/// keeping incremental parser state.
class FlutterRunLogSegmenter {
  const FlutterRunLogSegmenter();

  static final _frameworkBanner = RegExp(r'^[═╡╞\s]*EXCEPTION CAUGHT BY');
  static final _bannerRule = RegExp(r'^[═]{10,}');
  static final _unhandledException = RegExp(
    r'(Unhandled Exception:|Unhandled exception:)\s*(.*)$',
  );
  static final _stackFrame = RegExp(r'^#\d+\s');
  static final _compileError = RegExp(
    r'^(?<path>[^\s:]+\.dart):(?<line>\d+):(?<column>\d+):\s*Error:\s*(?<message>.+)$',
  );

  /// Both spellings a frame can use for the same file. Normalised to a
  /// project-relative `lib/...` path, which is what the user can open --
  /// `package:app/home_page.dart` and an absolute `file:///.../lib/home_page.dart`
  /// name the same line and must not become two issues.
  static final _appFrame = RegExp(
    r'(?:package:[\w.]+/(?<packagePath>[\w/.]+)|file://\S*?/(?<filePath>lib/[\w/.]+))'
    r':(?<line>\d+)(?::\d+)?',
  );
  static final _flutterFrameworkFrame = RegExp(r'package:flutter/');
  static final _digits = RegExp(r'\d+');

  /// Lines that are output but never a failure: banners, service URLs and
  /// progress chatter. Excluded here so the analyser is never asked about a
  /// DevTools link.
  static final _neverAFailure = <RegExp>[
    RegExp(r'^Flutter run key commands'),
    RegExp(r'A Dart VM Service on .* is available at'),
    RegExp(r'The Flutter DevTools debugger and profiler'),
    RegExp(r'^A new version of Flutter is available'),
    RegExp(r'^Running Gradle task'),
    RegExp(r'^Syncing files to device'),
  ];

  List<FlutterRunLogCandidate> segment(List<FlutterRunLogLine> logs) {
    final lines = [for (final line in logs) line.text];
    final candidates = <FlutterRunLogCandidate>[];
    var index = 0;
    while (index < lines.length) {
      final consumed = _frameworkBlock(lines, index, candidates)
          ? _frameworkBlockEnd(lines, index)
          : _unhandledBlock(lines, index, candidates)
          ? _unhandledBlockEnd(lines, index)
          : _compileErrorLine(lines, index, candidates)
          ? index + 1
          : index + 1;
      index = consumed > index ? consumed : index + 1;
    }
    return List.unmodifiable(candidates);
  }

  bool _frameworkBlock(
    List<String> lines,
    int start,
    List<FlutterRunLogCandidate> out,
  ) {
    if (!_frameworkBanner.hasMatch(lines[start])) return false;
    final end = _frameworkBlockEnd(lines, start);
    final block = lines.sublist(start, end);
    final headline = _firstMeaningfulLine(block.skip(1));
    if (headline.isEmpty) return false;
    out.add(
      _candidate(
        kind: FlutterRunIssueKind.frameworkException,
        headline: headline,
        block: block,
        startIndex: start,
      ),
    );
    return true;
  }

  int _frameworkBlockEnd(List<String> lines, int start) {
    for (var index = start + 1; index < lines.length; index += 1) {
      if (_bannerRule.hasMatch(lines[index])) return index + 1;
      if (_frameworkBanner.hasMatch(lines[index])) return index;
    }
    return lines.length;
  }

  bool _unhandledBlock(
    List<String> lines,
    int start,
    List<FlutterRunLogCandidate> out,
  ) {
    final match = _unhandledException.firstMatch(lines[start]);
    if (match == null) return false;
    final end = _unhandledBlockEnd(lines, start);
    out.add(
      _candidate(
        kind: FlutterRunIssueKind.unhandledException,
        headline: (match.group(2) ?? '').trim().isEmpty
            ? lines[start].trim()
            : match.group(2)!.trim(),
        block: lines.sublist(start, end),
        startIndex: start,
      ),
    );
    return true;
  }

  int _unhandledBlockEnd(List<String> lines, int start) {
    var end = start + 1;
    while (end < lines.length && _stackFrame.hasMatch(lines[end])) {
      end += 1;
    }
    return end;
  }

  bool _compileErrorLine(
    List<String> lines,
    int start,
    List<FlutterRunLogCandidate> out,
  ) {
    final match = _compileError.firstMatch(lines[start].trim());
    if (match == null) return false;
    // The frontend prints the offending source line and a caret under it.
    var end = start + 1;
    while (end < lines.length &&
        end - start <= 3 &&
        lines[end].trim().isNotEmpty &&
        !_compileError.hasMatch(lines[end].trim())) {
      end += 1;
    }
    out.add(
      _candidate(
        kind: FlutterRunIssueKind.compileError,
        headline: (match.namedGroup('message') ?? '').trim(),
        block: lines.sublist(start, end),
        startIndex: start,
        location: '${match.namedGroup('path')}:${match.namedGroup('line')}',
      ),
    );
    return true;
  }

  FlutterRunLogCandidate _candidate({
    required FlutterRunIssueKind kind,
    required String headline,
    required List<String> block,
    required int startIndex,
    String? location,
  }) {
    final appFrame = location ?? _firstAppFrame(block);
    return FlutterRunLogCandidate(
      kind: kind,
      headline: headline,
      lines: List.unmodifiable(block),
      signature: _signature(kind, headline, appFrame),
      location: appFrame,
      startIndex: startIndex,
    );
  }

  /// `path:line` of the first frame outside the framework, which is the line
  /// the user can act on. Framework frames are skipped because every Flutter
  /// exception shares them.
  String? _firstAppFrame(List<String> block) {
    for (final line in block) {
      if (_flutterFrameworkFrame.hasMatch(line)) continue;
      final match = _appFrame.firstMatch(line);
      if (match == null) continue;
      final packagePath = match.namedGroup('packagePath');
      final path = packagePath != null
          ? 'lib/$packagePath'
          : match.namedGroup('filePath');
      if (path == null) continue;
      return '$path:${match.namedGroup('line')}';
    }
    return null;
  }

  /// Identity of the problem behind a block.
  ///
  /// Numbers are masked because the same overflow reports a different pixel
  /// count every frame, and a signature that moved with it would defeat the
  /// deduplication it exists for.
  static String _signature(
    FlutterRunIssueKind kind,
    String headline,
    String? appFrame,
  ) {
    final normalized = headline
        .replaceAll(_digits, '#')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    return '${kind.name}|$normalized|${appFrame ?? ''}';
  }

  static String _firstMeaningfulLine(Iterable<String> lines) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (_bannerRule.hasMatch(trimmed)) continue;
      if (_neverAFailure.any((pattern) => pattern.hasMatch(trimmed))) continue;
      return trimmed;
    }
    return '';
  }
}
