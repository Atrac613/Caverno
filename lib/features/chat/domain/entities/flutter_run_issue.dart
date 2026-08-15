/// What kind of failure a candidate block came from.
///
/// The kind is decided by the block's shape alone -- the toolchain's own
/// framing -- never by reading the message. Judging what a failure *means* is
/// the analyser's job.
enum FlutterRunIssueKind {
  /// A framework assertion, fenced by the `EXCEPTION CAUGHT BY` banner.
  frameworkException,

  /// An unhandled Dart exception followed by a `#0`-style stack.
  unhandledException,

  /// A compile or hot-reload failure from the frontend.
  compileError,
}

/// A block of log lines that looks like a failure, before anything has decided
/// whether it is one.
class FlutterRunLogCandidate {
  const FlutterRunLogCandidate({
    required this.kind,
    required this.headline,
    required this.lines,
    required this.signature,
    required this.startIndex,
    this.location,
  });

  final FlutterRunIssueKind kind;

  /// First meaningful line, used as the fallback title before analysis.
  final String headline;

  /// The block verbatim. Kept whole because it is the evidence the user reads
  /// when the analysis is wrong.
  final List<String> lines;

  /// Identity of the underlying problem, stable across repeats. A Flutter
  /// exception is re-thrown every frame; without this the list would grow by
  /// sixty entries a second for one bug.
  final String signature;

  /// `path:line` of the first application frame, when the block names one.
  final String? location;

  final int startIndex;

  String get evidence => lines.join('\n');
}

/// An analysed problem, ready to show.
class FlutterRunIssue {
  const FlutterRunIssue({
    required this.signature,
    required this.kind,
    required this.title,
    required this.evidence,
    this.severity = FlutterRunIssueSeverity.error,
    this.cause = '',
    this.location,
    this.occurrences = 1,
    this.analysed = false,
  });

  final String signature;
  final FlutterRunIssueKind kind;
  final String title;

  /// The block that produced this, verbatim. Never replaced by the model's
  /// rendering of it.
  final String evidence;
  final FlutterRunIssueSeverity severity;

  /// One line on why it happens, from the analyser. Empty until analysed.
  final String cause;
  final String? location;
  final int occurrences;

  /// False while the entry is still the segmenter's own reading of the block.
  /// The UI says so rather than presenting an unanalysed title as a verdict.
  final bool analysed;

  FlutterRunIssue copyWith({
    String? title,
    FlutterRunIssueSeverity? severity,
    String? cause,
    String? location,
    int? occurrences,
    bool? analysed,
  }) {
    return FlutterRunIssue(
      signature: signature,
      kind: kind,
      title: title ?? this.title,
      evidence: evidence,
      severity: severity ?? this.severity,
      cause: cause ?? this.cause,
      location: location ?? this.location,
      occurrences: occurrences ?? this.occurrences,
      analysed: analysed ?? this.analysed,
    );
  }
}

enum FlutterRunIssueSeverity { error, warning, info }
