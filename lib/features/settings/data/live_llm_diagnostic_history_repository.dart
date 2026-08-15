import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/live_llm_diagnostic.dart';

class LiveLlmDiagnosticHistoryEntry {
  const LiveLlmDiagnosticHistoryEntry({required this.report});

  final LiveLlmDiagnosticReport report;

  Map<String, dynamic> toJson() => {'report': report.toJson()};

  factory LiveLlmDiagnosticHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LiveLlmDiagnosticHistoryEntry(
      report: _reportFromJson(_map(json['report'])),
    );
  }
}

class LiveLlmDiagnosticHistoryRepository {
  LiveLlmDiagnosticHistoryRepository(this._prefs);

  final SharedPreferences _prefs;

  static const maxEntriesPerModel = 10;
  static const _storageKey = 'live_llm_diagnostic_history.v1';

  List<LiveLlmDiagnosticHistoryEntry> load() {
    final encoded = _prefs.getString(_storageKey);
    if (encoded == null) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) {
            try {
              return LiveLlmDiagnosticHistoryEntry.fromJson(
                Map<String, dynamic>.from(item),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<LiveLlmDiagnosticHistoryEntry>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<LiveLlmDiagnosticHistoryEntry>> append(
    LiveLlmDiagnosticReport report,
  ) async {
    final targetBaseUrl = report.baseUrl.trim();
    final targetModel = report.model.trim();
    var matchingCount = 0;
    final updated = <LiveLlmDiagnosticHistoryEntry>[
      LiveLlmDiagnosticHistoryEntry(report: report),
      for (final entry in load())
        if (!_sameRun(entry.report, report) &&
            (!_sameModel(entry.report, targetBaseUrl, targetModel) ||
                matchingCount++ < maxEntriesPerModel - 1))
          entry,
    ];
    await _prefs.setString(
      _storageKey,
      jsonEncode(updated.map((entry) => entry.toJson()).toList()),
    );
    return updated;
  }

  static bool _sameModel(
    LiveLlmDiagnosticReport report,
    String baseUrl,
    String model,
  ) => report.baseUrl.trim() == baseUrl && report.model.trim() == model;

  static bool _sameRun(
    LiveLlmDiagnosticReport left,
    LiveLlmDiagnosticReport right,
  ) =>
      _sameModel(left, right.baseUrl.trim(), right.model.trim()) &&
      left.startedAt == right.startedAt;
}

LiveLlmDiagnosticReport _reportFromJson(Map<String, dynamic> json) {
  return LiveLlmDiagnosticReport(
    startedAt: DateTime.parse(json['startedAt'] as String),
    finishedAt: _dateTime(json['finishedAt']),
    baseUrl: json['baseUrl'] as String? ?? '',
    model: json['model'] as String? ?? '',
    demoMode: json['demoMode'] as bool? ?? false,
    mcpEnabled: json['mcpEnabled'] as bool? ?? false,
    toolCatalog: _toolCatalogFromJson(_map(json['toolCatalog'])),
    results: _list(
      json['results'],
    ).map((item) => _probeResultFromJson(_map(item))).toList(growable: false),
    samplerCalibrationTrials: _list(
      json['samplerCalibrationTrials'],
    ).map((item) => _samplerTrialFromJson(_map(item))).toList(growable: false),
    streamingMetrics: json['streaming'] == null
        ? null
        : _streamingMetricsFromJson(_map(json['streaming'])),
    multiRoundToolLoopMetrics: json['multiRoundToolLoop'] == null
        ? null
        : _multiRoundMetricsFromJson(_map(json['multiRoundToolLoop'])),
    embeddingMetrics: json['embeddings'] == null
        ? null
        : _embeddingMetricsFromJson(_map(json['embeddings'])),
    effectiveContextMetrics: json['effectiveContext'] == null
        ? null
        : _effectiveContextMetricsFromJson(_map(json['effectiveContext'])),
  );
}

LiveLlmDiagnosticProbeResult _probeResultFromJson(Map<String, dynamic> json) {
  final usage = _map(json['usage']);
  return LiveLlmDiagnosticProbeResult(
    id: json['id'] as String? ?? '',
    status: _status(json['status']),
    summary: json['summary'] as String? ?? '',
    details: json['details'] as String? ?? '',
    modelContent: json['modelContent'] as String? ?? '',
    toolCalls: _list(json['toolCalls']).whereType<String>().toList(),
    elapsed: Duration(milliseconds: _int(json['elapsedMs'])),
    usage: LiveLlmDiagnosticTokenUsage(
      promptTokens: _int(usage['promptTokens']),
      completionTokens: _int(usage['completionTokens']),
      totalTokens: _int(usage['totalTokens']),
    ),
    passedChecks: _int(json['passedChecks']),
    totalChecks: _int(json['totalChecks']),
    metadata: _stringMap(json['metadata']),
  );
}

LiveLlmDiagnosticToolCatalog _toolCatalogFromJson(Map<String, dynamic> json) {
  return LiveLlmDiagnosticToolCatalog(
    totalToolCount: _int(json['totalToolCount']),
    initialToolCount: _int(json['initialToolCount']),
    remoteToolCount: _int(json['remoteToolCount']),
    remoteServerCount: _int(json['remoteServerCount']),
    toolSearchEnabled: json['toolSearchEnabled'] as bool? ?? false,
    toolNames: _list(json['toolNames']).whereType<String>().toList(),
    initialToolNames: _list(
      json['initialToolNames'],
    ).whereType<String>().toList(),
    remoteToolNames: _list(
      json['remoteToolNames'],
    ).whereType<String>().toList(),
    mcpConnectionSummary: json['mcpConnectionSummary'] as String? ?? '',
  );
}

LiveLlmDiagnosticSamplerTrial _samplerTrialFromJson(Map<String, dynamic> json) {
  return LiveLlmDiagnosticSamplerTrial(
    requestClass: json['requestClass'] as String? ?? '',
    temperature: _double(json['temperature']),
    passed: json['passed'] as bool? ?? false,
    jsonRepairEventCount: _int(json['jsonRepairEventCount']),
    malformedToolCallCount: _int(json['malformedToolCallCount']),
    editApplyFailureCount: _int(json['editApplyFailureCount']),
    repetitionDetected: json['repetitionDetected'] as bool? ?? false,
  );
}

LiveLlmDiagnosticStreamingMetrics _streamingMetricsFromJson(
  Map<String, dynamic> json,
) {
  return LiveLlmDiagnosticStreamingMetrics(
    timeToFirstToken: Duration(milliseconds: _int(json['timeToFirstTokenMs'])),
    totalElapsed: Duration(milliseconds: _int(json['totalElapsedMs'])),
    completionTokens: _int(json['completionTokens']),
    chunkCount: _int(json['chunkCount']),
    finishReason: json['finishReason'] as String? ?? '',
  );
}

LiveLlmDiagnosticMultiRoundToolLoopMetrics _multiRoundMetricsFromJson(
  Map<String, dynamic> json,
) {
  return LiveLlmDiagnosticMultiRoundToolLoopMetrics(
    modelTurnCount: _int(json['modelTurnCount']),
    toolCallCount: _int(json['toolCallCount']),
    successfulToolExecutionCount: _int(json['successfulToolExecutionCount']),
    promptTokens: _int(json['promptTokens']),
    completionTokens: _int(json['completionTokens']),
    totalElapsed: Duration(milliseconds: _int(json['totalElapsedMs'])),
    taskCompleted: json['taskCompleted'] as bool? ?? false,
  );
}

LiveLlmDiagnosticEmbeddingMetrics _embeddingMetricsFromJson(
  Map<String, dynamic> json,
) {
  return LiveLlmDiagnosticEmbeddingMetrics(
    model: json['model'] as String? ?? '',
    inputCount: _int(json['inputCount']),
    returnedVectorCount: _int(json['returnedVectorCount']),
    dimension: _int(json['dimension']),
    similarCosine: _double(json['similarCosine']),
    unrelatedCosine: _double(json['unrelatedCosine']),
    totalElapsed: Duration(milliseconds: _int(json['totalElapsedMs'])),
  );
}

LiveLlmDiagnosticEffectiveContextMetrics _effectiveContextMetricsFromJson(
  Map<String, dynamic> json,
) {
  return LiveLlmDiagnosticEffectiveContextMetrics(
    configuredMaximumTokens: _int(json['configuredMaximumTokens']),
    trials: _list(
      json['trials'],
    ).map((item) => _contextTrialFromJson(_map(item))).toList(growable: false),
  );
}

LiveLlmDiagnosticContextTrial _contextTrialFromJson(Map<String, dynamic> json) {
  return LiveLlmDiagnosticContextTrial(
    requestedApproximateTokens: _int(json['requestedApproximateTokens']),
    promptTokens: _int(json['promptTokens']),
    passed: json['passed'] as bool? ?? false,
    elapsed: Duration(milliseconds: _int(json['elapsedMs'])),
    failure: json['failure'] as String? ?? '',
    failureKind: json['failureKind'] as String? ?? '',
    finishReason: json['finishReason'] as String? ?? '',
    responsePreview: json['responsePreview'] as String? ?? '',
  );
}

LiveLlmDiagnosticStatus _status(Object? value) {
  final label = value?.toString().toLowerCase();
  return LiveLlmDiagnosticStatus.values.firstWhere(
    (status) => status.label.toLowerCase() == label,
    orElse: () => LiveLlmDiagnosticStatus.failed,
  );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<dynamic> _list(Object? value) => value is List ? value : const [];

Map<String, String> _stringMap(Object? value) => {
  for (final entry in _map(value).entries)
    if (entry.value != null) entry.key: entry.value.toString(),
};

DateTime? _dateTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

double _double(Object? value) => value is num ? value.toDouble() : 0;
