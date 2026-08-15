import 'dart:async';

import '../../data/datasources/chat_datasource.dart';
import '../entities/flutter_run_issue.dart';
import '../entities/flutter_run_session.dart';
import 'flutter_run_issue_analyser.dart';
import 'flutter_run_log_segmenter.dart';

/// Turns a growing run log into a deduplicated issue list.
///
/// Analysis runs as the app is exercised, which only works because a model is
/// asked about a *problem*, not about an occurrence:
///
/// - a block whose signature is already known bumps a counter and costs nothing
/// - new signatures wait out a quiet period, so a burst at startup is one batch
/// - a run is capped, so a log that produces novel failures forever cannot
///   spend without limit
///
/// The effective number of model calls is therefore the number of distinct
/// failures in the run, not the number of lines.
class FlutterRunIssueCollector {
  FlutterRunIssueCollector({
    required ChatDataSource Function() dataSource,
    required String Function() model,
    FlutterRunLogSegmenter segmenter = const FlutterRunLogSegmenter(),
    FlutterRunIssueAnalyser analyser = const FlutterRunIssueAnalyser(),
    Duration debounce = const Duration(seconds: 3),
    this.analysisBudget = 20,
  }) : _dataSource = dataSource,
       _model = model,
       _segmenter = segmenter,
       _analyser = analyser,
       _debounce = debounce;

  final ChatDataSource Function() _dataSource;
  final String Function() _model;
  final FlutterRunLogSegmenter _segmenter;
  final FlutterRunIssueAnalyser _analyser;
  final Duration _debounce;

  /// Model calls allowed per run. Reached rather than exceeded: the issues are
  /// still collected, they just stop being analysed until the user asks.
  final int analysisBudget;

  final _issues = <String, FlutterRunIssue>{};
  final _pending = <String, FlutterRunLogCandidate>{};
  final _controller = StreamController<List<FlutterRunIssue>>.broadcast();

  List<FlutterRunLogLine> _lastLogs = const [];
  Timer? _debounceTimer;
  bool _analysing = false;
  int _analysisCount = 0;

  List<FlutterRunIssue> get issues => List.unmodifiable(_issues.values);

  Stream<List<FlutterRunIssue>> get changes => _controller.stream;

  /// True once the run has spent its budget; the UI offers a manual resume.
  bool get budgetExhausted => _analysisCount >= analysisBudget;

  int get analysisCount => _analysisCount;

  /// Re-reads [logs] and queues anything new. Idempotent: the segmenter runs
  /// over the whole buffer every time and known signatures are dropped here.
  void observe(List<FlutterRunLogLine> logs, {bool streamEnded = false}) {
    _lastLogs = logs;
    var discovered = false;
    for (final candidate in _segmenter.segment(
      logs,
      allowUnterminated: streamEnded,
    )) {
      final known = _issues[candidate.signature];
      if (known != null) {
        // The same problem again. Counting it is the whole point of the
        // signature: a re-thrown exception must not become a second issue or
        // a second model call.
        _issues[candidate.signature] = known.copyWith(
          occurrences: known.occurrences + 1,
        );
        discovered = true;
        continue;
      }
      if (_pending.containsKey(candidate.signature)) continue;

      _pending[candidate.signature] = candidate;
      _issues[candidate.signature] = FlutterRunIssue(
        signature: candidate.signature,
        kind: candidate.kind,
        title: candidate.headline,
        evidence: candidate.evidence,
        location: candidate.location,
      );
      discovered = true;
    }
    if (discovered) _publish();
    if (_pending.isNotEmpty) _scheduleAnalysis();
  }

  /// Analyses whatever is queued now, ignoring the quiet period. Also the way
  /// back from an exhausted budget, which is why it lifts the cap by a batch.
  Future<void> analyseNow() {
    _debounceTimer?.cancel();
    _analysisCount = 0;
    // Nothing more is coming, so a block still missing its closing rule is
    // all there will ever be of it.
    if (_lastLogs.isNotEmpty) observe(_lastLogs, streamEnded: true);
    return _drain();
  }

  void clear() {
    _debounceTimer?.cancel();
    _issues.clear();
    _pending.clear();
    _analysisCount = 0;
    _publish();
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _controller.close();
  }

  void _scheduleAnalysis() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(_drain()));
  }

  Future<void> _drain() async {
    if (_analysing) return;
    _analysing = true;
    try {
      while (_pending.isNotEmpty && !budgetExhausted) {
        final signature = _pending.keys.first;
        final candidate = _pending.remove(signature)!;
        _analysisCount += 1;
        final analysed = await _analyser.analyse(
          dataSource: _dataSource(),
          candidate: candidate,
          model: _model(),
          occurrences: _issues[signature]?.occurrences ?? 1,
        );
        // The count may have grown while the model was thinking.
        _issues[signature] = analysed.copyWith(
          occurrences: _issues[signature]?.occurrences ?? analysed.occurrences,
        );
        _publish();
      }
    } finally {
      _analysing = false;
    }
  }

  void _publish() {
    if (_controller.isClosed) return;
    _controller.add(issues);
  }
}
