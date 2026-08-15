enum LiveLlmDiagnosticStatus {
  pending,
  running,
  passed,
  warning,
  failed,
  skipped,
}

extension LiveLlmDiagnosticStatusX on LiveLlmDiagnosticStatus {
  bool get isTerminal => switch (this) {
    LiveLlmDiagnosticStatus.pending || LiveLlmDiagnosticStatus.running => false,
    LiveLlmDiagnosticStatus.passed ||
    LiveLlmDiagnosticStatus.warning ||
    LiveLlmDiagnosticStatus.failed ||
    LiveLlmDiagnosticStatus.skipped => true,
  };

  String get label => switch (this) {
    LiveLlmDiagnosticStatus.pending => 'Pending',
    LiveLlmDiagnosticStatus.running => 'Running',
    LiveLlmDiagnosticStatus.passed => 'Passed',
    LiveLlmDiagnosticStatus.warning => 'Warning',
    LiveLlmDiagnosticStatus.failed => 'Failed',
    LiveLlmDiagnosticStatus.skipped => 'Skipped',
  };
}

class LiveLlmDiagnosticProbeDefinition {
  const LiveLlmDiagnosticProbeDefinition({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
  });

  final String id;
  final String titleKey;
  final String descriptionKey;
}

class LiveLlmDiagnosticTokenUsage {
  const LiveLlmDiagnosticTokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  static const zero = LiveLlmDiagnosticTokenUsage();

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'totalTokens': totalTokens,
  };
}

class LiveLlmDiagnosticProbeResult {
  const LiveLlmDiagnosticProbeResult({
    required this.id,
    required this.status,
    required this.summary,
    this.details = '',
    this.modelContent = '',
    this.toolCalls = const <String>[],
    this.elapsed = Duration.zero,
    this.usage = LiveLlmDiagnosticTokenUsage.zero,
    this.passedChecks = 0,
    this.totalChecks = 0,
    this.metadata = const <String, String>{},
  });

  final String id;
  final LiveLlmDiagnosticStatus status;
  final String summary;
  final String details;
  final String modelContent;
  final List<String> toolCalls;
  final Duration elapsed;
  final LiveLlmDiagnosticTokenUsage usage;

  /// Sub-checks a multi-case probe passed, when it has any. LL39 scores a
  /// `warning` at this ratio: a probe that preserved two of three exact values
  /// used to be worth exactly as much as one that preserved none.
  final int passedChecks;

  /// Sub-checks a multi-case probe ran. Zero means the probe is single-shot
  /// and a `warning` falls back to flat partial credit.
  final int totalChecks;

  /// Machine-readable probe findings consumed by capability-profile builders.
  /// Human-readable explanations belong in [details]; consumers must not parse
  /// localized or presentation-oriented prose to recover a capability value.
  final Map<String, String> metadata;

  LiveLlmDiagnosticProbeResult copyWith({
    LiveLlmDiagnosticStatus? status,
    String? summary,
    String? details,
    String? modelContent,
    List<String>? toolCalls,
    Duration? elapsed,
    LiveLlmDiagnosticTokenUsage? usage,
    int? passedChecks,
    int? totalChecks,
    Map<String, String>? metadata,
  }) {
    return LiveLlmDiagnosticProbeResult(
      id: id,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      modelContent: modelContent ?? this.modelContent,
      toolCalls: toolCalls ?? this.toolCalls,
      elapsed: elapsed ?? this.elapsed,
      usage: usage ?? this.usage,
      passedChecks: passedChecks ?? this.passedChecks,
      totalChecks: totalChecks ?? this.totalChecks,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.label,
    'summary': summary,
    if (details.isNotEmpty) 'details': details,
    if (modelContent.isNotEmpty) 'modelContent': modelContent,
    if (toolCalls.isNotEmpty) 'toolCalls': toolCalls,
    'elapsedMs': elapsed.inMilliseconds,
    'usage': usage.toJson(),
    if (totalChecks > 0) 'passedChecks': passedChecks,
    if (totalChecks > 0) 'totalChecks': totalChecks,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class LiveLlmDiagnosticToolCatalog {
  const LiveLlmDiagnosticToolCatalog({
    this.totalToolCount = 0,
    this.initialToolCount = 0,
    this.remoteToolCount = 0,
    this.remoteServerCount = 0,
    this.toolSearchEnabled = false,
    this.toolNames = const <String>[],
    this.initialToolNames = const <String>[],
    this.remoteToolNames = const <String>[],
    this.mcpConnectionSummary = '',
  });

  final int totalToolCount;
  final int initialToolCount;
  final int remoteToolCount;
  final int remoteServerCount;
  final bool toolSearchEnabled;
  final List<String> toolNames;
  final List<String> initialToolNames;
  final List<String> remoteToolNames;
  final String mcpConnectionSummary;

  static const empty = LiveLlmDiagnosticToolCatalog();

  bool get hasTools => totalToolCount > 0;

  Map<String, dynamic> toJson() => {
    'totalToolCount': totalToolCount,
    'initialToolCount': initialToolCount,
    'remoteToolCount': remoteToolCount,
    'remoteServerCount': remoteServerCount,
    'toolSearchEnabled': toolSearchEnabled,
    'toolNames': toolNames,
    'initialToolNames': initialToolNames,
    'remoteToolNames': remoteToolNames,
    if (mcpConnectionSummary.isNotEmpty)
      'mcpConnectionSummary': mcpConnectionSummary,
  };
}

class LiveLlmDiagnosticSamplerTrial {
  const LiveLlmDiagnosticSamplerTrial({
    required this.requestClass,
    required this.temperature,
    required this.passed,
    this.jsonRepairEventCount = 0,
    this.malformedToolCallCount = 0,
    this.editApplyFailureCount = 0,
    this.repetitionDetected = false,
  });

  final String requestClass;
  final double temperature;
  final bool passed;
  final int jsonRepairEventCount;
  final int malformedToolCallCount;
  final int editApplyFailureCount;
  final bool repetitionDetected;

  Map<String, dynamic> toJson() => {
    'requestClass': requestClass,
    'temperature': temperature,
    'passed': passed,
    if (jsonRepairEventCount > 0) 'jsonRepairEventCount': jsonRepairEventCount,
    if (malformedToolCallCount > 0)
      'malformedToolCallCount': malformedToolCallCount,
    if (editApplyFailureCount > 0)
      'editApplyFailureCount': editApplyFailureCount,
    if (repetitionDetected) 'repetitionDetected': true,
  };
}

/// LL39 unbounded capability tier: what the streaming path actually cost.
///
/// Physical units only, never weighted points. Conformance saturates — a
/// capable model earns every attempted point — so the figures that keep
/// ranking models after that must carry their own units and no denominator,
/// which is what makes them comparable across suite versions and across years.
///
/// A response can contain many protocol chunks and still be buffered upstream,
/// then released as one short burst near the end. Such a run remains useful as
/// conformance evidence, but cannot honestly report model decode throughput.
class LiveLlmDiagnosticStreamingMetrics {
  const LiveLlmDiagnosticStreamingMetrics({
    required this.timeToFirstToken,
    required this.totalElapsed,
    required this.completionTokens,
    required this.chunkCount,
    this.finishReason = '',
  });

  final Duration timeToFirstToken;
  final Duration totalElapsed;
  final int completionTokens;
  final int chunkCount;
  final String finishReason;

  Duration get decodeWindow => totalElapsed - timeToFirstToken;

  /// Whether the observed delivery shape cannot support a decode-rate claim.
  ///
  /// A single chunk is unambiguously buffered. The second arm catches gateways
  /// that preserve every SSE event but queue them until generation is complete:
  /// at least 20 tokens arrive within 100 ms and that burst occupies less than
  /// 10% of the request. This avoids reporting the queue-drain speed as the
  /// model's generation speed.
  bool get isLikelyBuffered {
    if (chunkCount <= 1) {
      return true;
    }
    final decodeMicros = decodeWindow.inMicroseconds;
    return completionTokens >= 20 &&
        decodeMicros < const Duration(milliseconds: 100).inMicroseconds &&
        decodeMicros * 10 < totalElapsed.inMicroseconds;
  }

  /// Tokens per second over the decode phase, excluding the wait for the first
  /// token — prompt processing is a different cost and averaging it in would
  /// make a long prompt look like a slow model.
  ///
  /// Null when the endpoint reported no completion tokens or the decode window
  /// is too short to divide by.
  double? get decodeTokensPerSecond {
    final decodeMicros = decodeWindow.inMicroseconds;
    if (completionTokens <= 0 || decodeMicros <= 0 || isLikelyBuffered) {
      return null;
    }
    return completionTokens / (decodeMicros / Duration.microsecondsPerSecond);
  }

  Map<String, dynamic> toJson() => {
    'timeToFirstTokenMs': timeToFirstToken.inMilliseconds,
    'totalElapsedMs': totalElapsed.inMilliseconds,
    'completionTokens': completionTokens,
    'chunkCount': chunkCount,
    'likelyBuffered': isLikelyBuffered,
    if (finishReason.isNotEmpty) 'finishReason': finishReason,
    if (decodeTokensPerSecond != null)
      'decodeTokensPerSecond': double.parse(
        decodeTokensPerSecond!.toStringAsFixed(2),
      ),
  };
}

/// LL39 unbounded capability tier: the physical cost of one sequential tool
/// task.
///
/// This stays separate from weighted conformance points. A model can satisfy
/// the compatibility contract while still needing more turns or tokens than a
/// stronger model, and those quantities remain comparable without inventing a
/// second denominator.
class LiveLlmDiagnosticMultiRoundToolLoopMetrics {
  const LiveLlmDiagnosticMultiRoundToolLoopMetrics({
    required this.totalElapsed,
    required this.modelTurnCount,
    required this.toolCallCount,
    required this.successfulToolExecutionCount,
    required this.promptTokens,
    required this.completionTokens,
    required this.taskCompleted,
  });

  final Duration totalElapsed;
  final int modelTurnCount;
  final int toolCallCount;
  final int successfulToolExecutionCount;
  final int promptTokens;
  final int completionTokens;

  /// False preserves a partial measurement from an early-exit failure instead
  /// of making the whole capability block disappear.
  final bool taskCompleted;

  int get totalTokens => promptTokens + completionTokens;

  Map<String, dynamic> toJson() => {
    'totalElapsedMs': totalElapsed.inMilliseconds,
    'modelTurnCount': modelTurnCount,
    'toolCallCount': toolCallCount,
    'successfulToolExecutionCount': successfulToolExecutionCount,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'totalTokens': totalTokens,
    'taskCompleted': taskCompleted,
  };
}

/// LL39 embedding capability in physical units and direct vector comparisons.
///
/// Endpoint protocol acceptance belongs to COMPAT1. This block records what
/// Caverno's production embeddings client actually received and whether the
/// selected embedding model placed a semantic paraphrase closer than an
/// unrelated sentence.
class LiveLlmDiagnosticEmbeddingMetrics {
  const LiveLlmDiagnosticEmbeddingMetrics({
    required this.totalElapsed,
    required this.inputCount,
    required this.returnedVectorCount,
    required this.dimension,
    required this.model,
    required this.similarCosine,
    required this.unrelatedCosine,
  });

  final Duration totalElapsed;
  final int inputCount;
  final int returnedVectorCount;
  final int dimension;
  final String model;
  final double similarCosine;
  final double unrelatedCosine;

  double get semanticMargin => similarCosine - unrelatedCosine;

  Map<String, dynamic> toJson() => {
    'totalElapsedMs': totalElapsed.inMilliseconds,
    'inputCount': inputCount,
    'returnedVectorCount': returnedVectorCount,
    'dimension': dimension,
    'model': model,
    'similarCosine': _roundMetric(similarCosine),
    'unrelatedCosine': _roundMetric(unrelatedCosine),
    'semanticMargin': _roundMetric(semanticMargin),
  };

  static double _roundMetric(double value) {
    return double.parse(value.toStringAsFixed(6));
  }
}

class LiveLlmDiagnosticContextTrial {
  const LiveLlmDiagnosticContextTrial({
    required this.requestedApproximateTokens,
    required this.elapsed,
    required this.passed,
    this.promptTokens = 0,
    this.failure = '',
    this.failureKind = '',
    this.finishReason = '',
    this.responsePreview = '',
  });

  final int requestedApproximateTokens;
  final Duration elapsed;
  final bool passed;
  final int promptTokens;
  final String failure;
  final String failureKind;
  final String finishReason;
  final String responsePreview;

  Map<String, dynamic> toJson() => {
    'requestedApproximateTokens': requestedApproximateTokens,
    'elapsedMs': elapsed.inMilliseconds,
    'passed': passed,
    if (promptTokens > 0) 'promptTokens': promptTokens,
    if (failure.isNotEmpty) 'failure': failure,
    if (failureKind.isNotEmpty) 'failureKind': failureKind,
    if (finishReason.isNotEmpty) 'finishReason': finishReason,
    if (responsePreview.isNotEmpty) 'responsePreview': responsePreview,
  };
}

/// LL39 effective-context evidence in physical prompt-token units.
///
/// Only successful requests with endpoint-reported usage contribute to
/// [maxSuccessfulPromptTokens]. The requested sizes are approximations used to
/// build the ladder; they are never persisted as measured context capacity.
class LiveLlmDiagnosticEffectiveContextMetrics {
  const LiveLlmDiagnosticEffectiveContextMetrics({
    required this.configuredMaximumTokens,
    required this.trials,
  });

  final int configuredMaximumTokens;
  final List<LiveLlmDiagnosticContextTrial> trials;

  int get maxSuccessfulPromptTokens => trials
      .where((trial) => trial.passed && trial.promptTokens > 0)
      .fold<int>(
        0,
        (maximum, trial) =>
            trial.promptTokens > maximum ? trial.promptTokens : maximum,
      );

  bool get reachedConfiguredMaximum =>
      trials.isNotEmpty &&
      trials.last.passed &&
      trials.last.requestedApproximateTokens == configuredMaximumTokens;

  int? get firstFailedApproximateTokens {
    for (final trial in trials) {
      if (!trial.passed) return trial.requestedApproximateTokens;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'configuredMaximumTokens': configuredMaximumTokens,
    'maxSuccessfulPromptTokens': maxSuccessfulPromptTokens,
    'reachedConfiguredMaximum': reachedConfiguredMaximum,
    if (firstFailedApproximateTokens != null)
      'firstFailedApproximateTokens': firstFailedApproximateTokens,
    'trials': trials.map((trial) => trial.toJson()).toList(growable: false),
  };
}

class LiveLlmDiagnosticReport {
  const LiveLlmDiagnosticReport({
    required this.startedAt,
    this.finishedAt,
    required this.baseUrl,
    required this.model,
    required this.demoMode,
    required this.mcpEnabled,
    this.toolCatalog = LiveLlmDiagnosticToolCatalog.empty,
    this.results = const <LiveLlmDiagnosticProbeResult>[],
    this.samplerCalibrationTrials = const <LiveLlmDiagnosticSamplerTrial>[],
    this.samplerCalibrationUnmeasuredReason = '',
    this.streamingMetrics,
    this.multiRoundToolLoopMetrics,
    this.embeddingMetrics,
    this.effectiveContextMetrics,
  });

  final DateTime startedAt;
  final DateTime? finishedAt;
  final String baseUrl;
  final String model;
  final bool demoMode;
  final bool mcpEnabled;
  final LiveLlmDiagnosticToolCatalog toolCatalog;
  final List<LiveLlmDiagnosticProbeResult> results;
  final List<LiveLlmDiagnosticSamplerTrial> samplerCalibrationTrials;

  /// Why no sampler sweep was run, or empty when it was. A temperature sweep is
  /// only a measurement when the endpoint honours the temperature; on endpoints
  /// that reject the parameter the trials would all be the same request, so
  /// they are not run and this says why instead of reporting a clean sweep.
  final String samplerCalibrationUnmeasuredReason;

  /// Null until the streaming probe runs, and after a run where it was skipped
  /// or threw. Absent means unmeasured, not zero.
  final LiveLlmDiagnosticStreamingMetrics? streamingMetrics;

  /// Null means this capability was not measured. A non-null incomplete value
  /// retains the work spent before the loop failed.
  final LiveLlmDiagnosticMultiRoundToolLoopMetrics? multiRoundToolLoopMetrics;

  /// Null means no embeddings model was configured or the capability was not
  /// measured. A returned but semantically weak vector set remains present so
  /// the failure can be inspected without conflating it with no endpoint.
  final LiveLlmDiagnosticEmbeddingMetrics? embeddingMetrics;

  /// Null unless the expensive context ladder was explicitly enabled.
  final LiveLlmDiagnosticEffectiveContextMetrics? effectiveContextMetrics;

  LiveLlmDiagnosticReport copyWith({
    DateTime? finishedAt,
    LiveLlmDiagnosticToolCatalog? toolCatalog,
    List<LiveLlmDiagnosticProbeResult>? results,
    List<LiveLlmDiagnosticSamplerTrial>? samplerCalibrationTrials,
    String? samplerCalibrationUnmeasuredReason,
    LiveLlmDiagnosticStreamingMetrics? streamingMetrics,
    LiveLlmDiagnosticMultiRoundToolLoopMetrics? multiRoundToolLoopMetrics,
    LiveLlmDiagnosticEmbeddingMetrics? embeddingMetrics,
    LiveLlmDiagnosticEffectiveContextMetrics? effectiveContextMetrics,
  }) {
    return LiveLlmDiagnosticReport(
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      baseUrl: baseUrl,
      model: model,
      demoMode: demoMode,
      mcpEnabled: mcpEnabled,
      toolCatalog: toolCatalog ?? this.toolCatalog,
      results: results ?? this.results,
      samplerCalibrationTrials:
          samplerCalibrationTrials ?? this.samplerCalibrationTrials,
      samplerCalibrationUnmeasuredReason:
          samplerCalibrationUnmeasuredReason ??
          this.samplerCalibrationUnmeasuredReason,
      streamingMetrics: streamingMetrics ?? this.streamingMetrics,
      multiRoundToolLoopMetrics:
          multiRoundToolLoopMetrics ?? this.multiRoundToolLoopMetrics,
      embeddingMetrics: embeddingMetrics ?? this.embeddingMetrics,
      effectiveContextMetrics:
          effectiveContextMetrics ?? this.effectiveContextMetrics,
    );
  }

  LiveLlmDiagnosticReport withProbeResult(LiveLlmDiagnosticProbeResult result) {
    final index = results.indexWhere((item) => item.id == result.id);
    if (index == -1) {
      return copyWith(results: [...results, result]);
    }
    final updated = [...results];
    updated[index] = result;
    return copyWith(results: updated);
  }

  Duration get elapsed => (finishedAt ?? DateTime.now()).difference(startedAt);

  int get completedProbeCount =>
      results.where((result) => result.status.isTerminal).length;

  int get scoredProbeCount => results
      .where((result) => result.status != LiveLlmDiagnosticStatus.skipped)
      .where((result) => result.status.isTerminal)
      .length;

  int get passedProbeCount => results
      .where((result) => result.status == LiveLlmDiagnosticStatus.passed)
      .length;

  List<LiveLlmDiagnosticSamplerTrialSummary> get samplerCalibrationSummaries {
    final summaries = <String, LiveLlmDiagnosticSamplerTrialSummary>{};
    for (final trial in samplerCalibrationTrials) {
      summaries
          .putIfAbsent(
            trial.requestClass,
            () => LiveLlmDiagnosticSamplerTrialSummary(
              requestClass: trial.requestClass,
            ),
          )
          .add(trial);
    }
    return summaries.values.toList(growable: false)
      ..sort((left, right) => left.requestClass.compareTo(right.requestClass));
  }

  double get score {
    final scored = scoredProbeCount;
    if (scored == 0) {
      return 0;
    }
    return passedProbeCount / scored;
  }

  LiveLlmDiagnosticStatus get overallStatus {
    if (results.any(
      (result) => result.status == LiveLlmDiagnosticStatus.running,
    )) {
      return LiveLlmDiagnosticStatus.running;
    }
    if (results.any(
      (result) => result.status == LiveLlmDiagnosticStatus.failed,
    )) {
      return LiveLlmDiagnosticStatus.failed;
    }
    if (results.any(
      (result) => result.status == LiveLlmDiagnosticStatus.warning,
    )) {
      return LiveLlmDiagnosticStatus.warning;
    }
    if (results.any(
      (result) => result.status == LiveLlmDiagnosticStatus.passed,
    )) {
      return LiveLlmDiagnosticStatus.passed;
    }
    return LiveLlmDiagnosticStatus.pending;
  }

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    'elapsedMs': elapsed.inMilliseconds,
    'baseUrl': baseUrl,
    'model': model,
    'demoMode': demoMode,
    'mcpEnabled': mcpEnabled,
    'overallStatus': overallStatus.label,
    'score': score,
    'toolCatalog': toolCatalog.toJson(),
    if (streamingMetrics != null) 'streaming': streamingMetrics!.toJson(),
    if (multiRoundToolLoopMetrics != null)
      'multiRoundToolLoop': multiRoundToolLoopMetrics!.toJson(),
    if (embeddingMetrics != null) 'embeddings': embeddingMetrics!.toJson(),
    if (effectiveContextMetrics != null)
      'effectiveContext': effectiveContextMetrics!.toJson(),
    'results': results.map((result) => result.toJson()).toList(),
    if (samplerCalibrationTrials.isNotEmpty)
      'samplerCalibrationTrials': samplerCalibrationTrials
          .map((trial) => trial.toJson())
          .toList(),
    if (samplerCalibrationTrials.isNotEmpty)
      'samplerCalibrationSummary': _samplerCalibrationSummaryToJson(),
    if (samplerCalibrationUnmeasuredReason.isNotEmpty)
      'samplerCalibrationUnmeasured': samplerCalibrationUnmeasuredReason,
  };

  Map<String, dynamic> _samplerCalibrationSummaryToJson() {
    return {
      for (final summary in samplerCalibrationSummaries)
        summary.requestClass: summary.toJson(),
    };
  }
}

class LiveLlmDiagnosticSamplerTrialSummary {
  LiveLlmDiagnosticSamplerTrialSummary({required this.requestClass});

  final String requestClass;
  final candidateTemperatures = <double>{};
  int trialCount = 0;
  int passedCount = 0;
  int jsonRepairEventCount = 0;
  int malformedToolCallCount = 0;
  int editApplyFailureCount = 0;
  int repetitionCount = 0;

  List<double> get sortedCandidateTemperatures =>
      candidateTemperatures.toList(growable: false)..sort();

  bool get hasQualityFlags =>
      jsonRepairEventCount != 0 ||
      malformedToolCallCount != 0 ||
      editApplyFailureCount != 0 ||
      repetitionCount != 0;

  void add(LiveLlmDiagnosticSamplerTrial trial) {
    trialCount += 1;
    candidateTemperatures.add(trial.temperature);
    if (trial.passed) {
      passedCount += 1;
    }
    jsonRepairEventCount += _positiveCount(trial.jsonRepairEventCount);
    malformedToolCallCount += _positiveCount(trial.malformedToolCallCount);
    editApplyFailureCount += _positiveCount(trial.editApplyFailureCount);
    if (trial.repetitionDetected) {
      repetitionCount += 1;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'trialCount': trialCount,
      'passedCount': passedCount,
      'candidateTemperatures': sortedCandidateTemperatures,
      if (jsonRepairEventCount != 0)
        'jsonRepairEventCount': jsonRepairEventCount,
      if (malformedToolCallCount != 0)
        'malformedToolCallCount': malformedToolCallCount,
      if (editApplyFailureCount != 0)
        'editApplyFailureCount': editApplyFailureCount,
      if (repetitionCount != 0) 'repetitionCount': repetitionCount,
    };
  }

  int _positiveCount(int value) => value < 0 ? 0 : value;
}

class LiveLlmDiagnosticState {
  const LiveLlmDiagnosticState({
    this.isRunning = false,
    this.report,
    this.history = const <LiveLlmDiagnosticReport>[],
    this.error,
  });

  final bool isRunning;
  final LiveLlmDiagnosticReport? report;
  final List<LiveLlmDiagnosticReport> history;
  final String? error;

  static const initial = LiveLlmDiagnosticState();

  LiveLlmDiagnosticState copyWith({
    bool? isRunning,
    LiveLlmDiagnosticReport? report,
    List<LiveLlmDiagnosticReport>? history,
    String? error,
    bool clearError = false,
  }) {
    return LiveLlmDiagnosticState(
      isRunning: isRunning ?? this.isRunning,
      report: report ?? this.report,
      history: history ?? this.history,
      error: clearError ? null : error ?? this.error,
    );
  }
}
