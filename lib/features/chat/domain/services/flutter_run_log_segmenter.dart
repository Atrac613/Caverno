import '../entities/flutter_run_issue.dart';
import '../entities/flutter_run_session.dart';
import 'flutter_run_candidate_factory.dart';

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
class FlutterRunLogSegmenter with FlutterRunCandidateFactory {
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

  /// Terminal failure banners the platform toolchains print. Fixed strings
  /// rather than message matching: the error inside them differs with every
  /// platform and SDK version, but the banner does not.
  static final _buildFailureBanners = <RegExp>[
    RegExp(r'^\*\*\s*BUILD FAILED'),
    RegExp(r'^Error \(Xcode\):'),
    RegExp(r'^Could not build the (application|project)'),
    RegExp(r'^Error running application on '),
    RegExp(r'^Command\s+\S+\s+failed with a nonzero exit code'),
    RegExp(r'^FAILURE: Build failed with an exception'),
    RegExp(r'^Exception: (Gradle task|Failed to)'),
  ];

  /// Lines that are output but never a failure: banners, service URLs and
  /// progress chatter. Excluded here so the analyser is never asked about a
  /// DevTools link.
  static final neverAFailure = <RegExp>[
    RegExp(r'^Flutter run key commands'),
    RegExp(r'A Dart VM Service on .* is available at'),
    RegExp(r'The Flutter DevTools debugger and profiler'),
    RegExp(r'^A new version of Flutter is available'),
    RegExp(r'^Running Gradle task'),
    RegExp(r'^Syncing files to device'),
  ];

  /// Cuts [logs] into candidates.
  ///
  /// [allowUnterminated] keeps a framework block whose closing rule has not
  /// arrived. False while output is streaming: a half-arrived block has no
  /// stack frame yet, so it would take a different signature from the finished
  /// one and the same failure would be listed twice. True once the stream is
  /// over, where an unterminated block is all there will ever be.
  List<FlutterRunLogCandidate> segment(
    List<FlutterRunLogLine> logs, {
    bool allowUnterminated = false,
  }) {
    final lines = [for (final line in logs) line.text];
    final candidates = <FlutterRunLogCandidate>[];
    var index = 0;
    while (index < lines.length) {
      final consumed =
          _frameworkBlock(lines, index, candidates, allowUnterminated)
          ? _frameworkBlockEnd(lines, index)
          : _unhandledBlock(lines, index, candidates)
          ? _unhandledBlockEnd(lines, index)
          : _compileErrorLine(lines, index, candidates)
          ? index + 1
          : _buildFailureLine(lines, index, candidates)
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
    bool allowUnterminated,
  ) {
    if (!_frameworkBanner.hasMatch(lines[start])) return false;
    if (!allowUnterminated && !_isTerminated(lines, start)) return false;
    final end = _frameworkBlockEnd(lines, start);
    final block = lines.sublist(start, end);
    final headline = _firstMeaningfulLine(block.skip(1));
    if (headline.isEmpty) return false;
    out.add(
      buildCandidate(
        kind: FlutterRunIssueKind.frameworkException,
        headline: headline,
        block: block,
        startIndex: start,
      ),
    );
    return true;
  }

  /// Whether the closing rule (or the next banner) has arrived yet.
  bool _isTerminated(List<String> lines, int start) {
    for (var index = start + 1; index < lines.length; index += 1) {
      if (_bannerRule.hasMatch(lines[index])) return true;
      if (_frameworkBanner.hasMatch(lines[index])) return true;
    }
    return false;
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
      buildCandidate(
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
      buildCandidate(
        kind: FlutterRunIssueKind.compileError,
        headline: (match.namedGroup('message') ?? '').trim(),
        block: lines.sublist(start, end),
        startIndex: start,
        location: '${match.namedGroup('path')}:${match.namedGroup('line')}',
      ),
    );
    return true;
  }

  /// A platform build failure, kept with the lines around it: the banner names
  /// the failure but the cause is usually printed just above it.
  bool _buildFailureLine(
    List<String> lines,
    int start,
    List<FlutterRunLogCandidate> out,
  ) {
    final line = lines[start].trim();
    if (!_buildFailureBanners.any((pattern) => pattern.hasMatch(line))) {
      return false;
    }
    const leading = 12;
    final from = start - leading < 0 ? 0 : start - leading;
    final to = start + 3 > lines.length ? lines.length : start + 3;
    out.add(
      buildCandidate(
        kind: FlutterRunIssueKind.buildFailure,
        headline: line,
        block: lines.sublist(from, to),
        startIndex: from,
      ),
    );
    return true;
  }

  static String _firstMeaningfulLine(Iterable<String> lines) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (_bannerRule.hasMatch(trimmed)) continue;
      if (neverAFailure.any((pattern) => pattern.hasMatch(trimmed))) continue;
      return trimmed;
    }
    return '';
  }
}
