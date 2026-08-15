import '../entities/flutter_run_issue.dart';
import '../entities/flutter_run_session.dart';
import 'flutter_run_log_segmenter.dart';

/// Builds candidates and gives them the identity the whole feature turns on.
///
/// Kept apart from the recognisers: what counts as a failure-shaped block is
/// one question, and what makes two of them the same problem is another.
mixin FlutterRunCandidateFactory {
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

  FlutterRunLogCandidate buildCandidate({
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

  /// One candidate carrying the tail of a run that ended badly with nothing
  /// recognisable in it.
  ///
  /// The generalisation that keeps an unknown failure shape from being
  /// invisible: rather than widening the patterns until they match everything
  /// (and fire on healthy output), the window is handed over whole and the
  /// model is allowed to say it contains no failure. Bounded and only on a bad
  /// exit, so a healthy run still sends nothing.
  FlutterRunLogCandidate? unclassifiedTail(
    List<FlutterRunLogLine> logs, {
    int maxLines = 120,
  }) {
    final meaningful = [
      for (final line in logs)
        if (line.text.trim().isNotEmpty &&
            !FlutterRunLogSegmenter.neverAFailure.any(
              (p) => p.hasMatch(line.text.trim()),
            ))
          line.text,
    ];
    if (meaningful.isEmpty) return null;
    final tail = meaningful.length <= maxLines
        ? meaningful
        : meaningful.sublist(meaningful.length - maxLines);
    return buildCandidate(
      kind: FlutterRunIssueKind.unclassifiedFailure,
      headline: tail.last.trim(),
      block: tail,
      startIndex: logs.length - tail.length,
    );
  }
}
