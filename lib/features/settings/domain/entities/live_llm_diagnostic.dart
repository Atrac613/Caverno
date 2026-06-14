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
  });

  final String id;
  final LiveLlmDiagnosticStatus status;
  final String summary;
  final String details;
  final String modelContent;
  final List<String> toolCalls;
  final Duration elapsed;
  final LiveLlmDiagnosticTokenUsage usage;

  LiveLlmDiagnosticProbeResult copyWith({
    LiveLlmDiagnosticStatus? status,
    String? summary,
    String? details,
    String? modelContent,
    List<String>? toolCalls,
    Duration? elapsed,
    LiveLlmDiagnosticTokenUsage? usage,
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

  LiveLlmDiagnosticReport copyWith({
    DateTime? finishedAt,
    LiveLlmDiagnosticToolCatalog? toolCatalog,
    List<LiveLlmDiagnosticProbeResult>? results,
    List<LiveLlmDiagnosticSamplerTrial>? samplerCalibrationTrials,
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
    'results': results.map((result) => result.toJson()).toList(),
    if (samplerCalibrationTrials.isNotEmpty)
      'samplerCalibrationTrials': samplerCalibrationTrials
          .map((trial) => trial.toJson())
          .toList(),
    if (samplerCalibrationTrials.isNotEmpty)
      'samplerCalibrationSummary': _samplerCalibrationSummaryToJson(),
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
    this.error,
  });

  final bool isRunning;
  final LiveLlmDiagnosticReport? report;
  final String? error;

  static const initial = LiveLlmDiagnosticState();

  LiveLlmDiagnosticState copyWith({
    bool? isRunning,
    LiveLlmDiagnosticReport? report,
    String? error,
    bool clearError = false,
  }) {
    return LiveLlmDiagnosticState(
      isRunning: isRunning ?? this.isRunning,
      report: report ?? this.report,
      error: clearError ? null : error ?? this.error,
    );
  }
}
