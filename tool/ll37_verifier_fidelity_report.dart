part of 'll37_verifier_fidelity_probe.dart';

final class Ll37VerifierFidelityMetrics {
  const Ll37VerifierFidelityMetrics({
    required this.totalCount,
    required this.correctCaseCount,
    required this.brokenCaseCount,
    required this.correctAcceptedCount,
    required this.falseRefuteCount,
    required this.brokenDetectedCount,
    required this.brokenMissedCount,
    required this.unverifiableCount,
    required this.invalidCount,
  });

  factory Ll37VerifierFidelityMetrics.fromResults(
    Iterable<Ll37VerifierCaseResult> results,
  ) {
    final entries = results.toList(growable: false);
    int count(bool Function(Ll37VerifierCaseResult result) predicate) =>
        entries.where(predicate).length;

    return Ll37VerifierFidelityMetrics(
      totalCount: entries.length,
      correctCaseCount: count(
        (result) =>
            result.evalCase.expectedVerdict == Ll37ExpectedVerdict.notRefuted,
      ),
      brokenCaseCount: count(
        (result) =>
            result.evalCase.expectedVerdict == Ll37ExpectedVerdict.refuted,
      ),
      correctAcceptedCount: count(
        (result) =>
            result.evalCase.expectedVerdict == Ll37ExpectedVerdict.notRefuted &&
            result.verdict == Ll37VerifierVerdict.notRefuted,
      ),
      falseRefuteCount: count(
        (result) =>
            result.evalCase.expectedVerdict == Ll37ExpectedVerdict.notRefuted &&
            result.verdict == Ll37VerifierVerdict.refuted,
      ),
      brokenDetectedCount: count(
        (result) =>
            result.evalCase.expectedVerdict == Ll37ExpectedVerdict.refuted &&
            result.verdict == Ll37VerifierVerdict.refuted,
      ),
      brokenMissedCount: count(
        (result) =>
            result.evalCase.expectedVerdict == Ll37ExpectedVerdict.refuted &&
            result.verdict == Ll37VerifierVerdict.notRefuted,
      ),
      unverifiableCount: count(
        (result) => result.verdict == Ll37VerifierVerdict.unverifiable,
      ),
      invalidCount: count((result) => !result.isValid),
    );
  }

  final int totalCount;
  final int correctCaseCount;
  final int brokenCaseCount;
  final int correctAcceptedCount;
  final int falseRefuteCount;
  final int brokenDetectedCount;
  final int brokenMissedCount;
  final int unverifiableCount;
  final int invalidCount;

  double? get falseRefuteRate =>
      correctCaseCount == 0 ? null : falseRefuteCount / correctCaseCount;

  double? get brokenRecall =>
      brokenCaseCount == 0 ? null : brokenDetectedCount / brokenCaseCount;

  Map<String, dynamic> toJson() => {
    'totalCount': totalCount,
    'correctCaseCount': correctCaseCount,
    'brokenCaseCount': brokenCaseCount,
    'correctAcceptedCount': correctAcceptedCount,
    'falseRefuteCount': falseRefuteCount,
    'brokenDetectedCount': brokenDetectedCount,
    'brokenMissedCount': brokenMissedCount,
    'unverifiableCount': unverifiableCount,
    'invalidCount': invalidCount,
    'falseRefuteRate': falseRefuteRate,
    'brokenRecall': brokenRecall,
  };
}

final class Ll37VerifierFidelityReport {
  const Ll37VerifierFidelityReport({
    required this.generatedAt,
    required this.mode,
    required this.model,
    required this.baseUrl,
    required this.gate,
    required this.allCases,
    required this.eligibleCases,
    required this.eligiblePairCount,
    required this.eligibleObjectiveCount,
    required this.eligibleSourceSurfaces,
    required this.results,
  });

  static const minimumCorrectCases = 5;
  static const minimumBrokenCases = 5;
  static const minimumEligiblePairs = 5;
  static const minimumDistinctObjectives = 5;
  static const minimumSourceSurfaces = 2;
  static const maximumFalseRefuteRate = 0.1;
  static const minimumBrokenRecall = 0.8;

  factory Ll37VerifierFidelityReport.build({
    required DateTime generatedAt,
    required String mode,
    required String model,
    required String baseUrl,
    required List<Ll37VerifierCaseResult> results,
  }) {
    validateLl37VerifierFidelityPairs(
      results.map((result) => result.evalCase).toList(growable: false),
    );
    final eligible = results
        .where((result) => result.evalCase.isEligible)
        .toList(growable: false);
    final allMetrics = Ll37VerifierFidelityMetrics.fromResults(results);
    final eligibleMetrics = Ll37VerifierFidelityMetrics.fromResults(eligible);
    final surfaces = eligible
        .map((result) => result.evalCase.sourceSurface.jsonValue)
        .toSet();
    final pairIds = eligible.map((result) => result.evalCase.pairId).toSet();
    final objectiveFingerprints = eligible
        .map((result) => _ll37ObjectiveFingerprint(result.evalCase))
        .toSet();
    final gate = _gateFor(
      eligibleMetrics,
      pairIds.length,
      objectiveFingerprints.length,
      surfaces.length,
    );
    return Ll37VerifierFidelityReport(
      generatedAt: generatedAt,
      mode: mode,
      model: model,
      baseUrl: baseUrl,
      gate: gate,
      allCases: allMetrics,
      eligibleCases: eligibleMetrics,
      eligiblePairCount: pairIds.length,
      eligibleObjectiveCount: objectiveFingerprints.length,
      eligibleSourceSurfaces: surfaces.length,
      results: List.unmodifiable(results),
    );
  }

  final DateTime generatedAt;
  final String mode;
  final String model;
  final String baseUrl;
  final String gate;
  final Ll37VerifierFidelityMetrics allCases;
  final Ll37VerifierFidelityMetrics eligibleCases;
  final int eligiblePairCount;
  final int eligibleObjectiveCount;
  final int eligibleSourceSurfaces;
  final List<Ll37VerifierCaseResult> results;

  bool get isGo => gate == 'go';

  static String _gateFor(
    Ll37VerifierFidelityMetrics metrics,
    int pairCount,
    int objectiveCount,
    int sourceSurfaceCount,
  ) {
    if (metrics.correctCaseCount < minimumCorrectCases ||
        metrics.brokenCaseCount < minimumBrokenCases ||
        pairCount < minimumEligiblePairs ||
        objectiveCount < minimumDistinctObjectives ||
        sourceSurfaceCount < minimumSourceSurfaces) {
      return 'no_go_insufficient_eligible_sample';
    }
    if (metrics.invalidCount > 0 || metrics.unverifiableCount > 0) {
      return 'no_go_unreliable_output';
    }
    if ((metrics.falseRefuteRate ?? 1) > maximumFalseRefuteRate) {
      return 'no_go_false_refute_rate';
    }
    if ((metrics.brokenRecall ?? 0) < minimumBrokenRecall) {
      return 'no_go_broken_recall';
    }
    return 'go';
  }

  Map<String, dynamic> toJson() => {
    'schemaName': _reportSchemaName,
    'schemaVersion': _reportSchemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'mode': mode,
    'model': model,
    'baseUrl': baseUrl,
    'gate': gate,
    'isGo': isGo,
    'thresholds': {
      'minimumCorrectCases': minimumCorrectCases,
      'minimumBrokenCases': minimumBrokenCases,
      'minimumEligiblePairs': minimumEligiblePairs,
      'minimumDistinctObjectives': minimumDistinctObjectives,
      'minimumSourceSurfaces': minimumSourceSurfaces,
      'maximumFalseRefuteRate': maximumFalseRefuteRate,
      'minimumBrokenRecall': minimumBrokenRecall,
    },
    'allCases': allCases.toJson(),
    'eligibleCases': eligibleCases.toJson(),
    'eligiblePairCount': eligiblePairCount,
    'eligibleObjectiveCount': eligibleObjectiveCount,
    'eligibleSourceSurfaces': eligibleSourceSurfaces,
    'results': results.map((item) => item.toJson()).toList(growable: false),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL37 Verifier Fidelity Probe')
      ..writeln()
      ..writeln('- Gate: `$gate`')
      ..writeln('- Mode: `$mode`')
      ..writeln('- Model: `${model.isEmpty ? 'fixture' : model}`')
      ..writeln('- Base URL: `${baseUrl.isEmpty ? 'none' : baseUrl}`')
      ..writeln('- Eligible pairs: `$eligiblePairCount`')
      ..writeln('- Eligible objectives: `$eligibleObjectiveCount`')
      ..writeln('- Eligible source surfaces: `$eligibleSourceSurfaces`')
      ..writeln()
      ..writeln('## Metrics')
      ..writeln()
      ..writeln(
        '| Population | Cases | Correct | Broken | False refutes | Broken recall | Unverifiable | Invalid |',
      )
      ..writeln(
        '|------------|------:|--------:|-------:|--------------:|--------------:|-------------:|--------:|',
      )
      ..writeln(_metricsRow('All', allCases))
      ..writeln(_metricsRow('Eligible', eligibleCases))
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln('| Case | Surface | Expected | Verdict | Confidence | Result |')
      ..writeln(
        '|------|---------|----------|---------|-----------:|--------|',
      );
    for (final result in results) {
      buffer.writeln(
        '| ${_cell(result.evalCase.caseId)} '
        '| ${result.evalCase.sourceSurface.jsonValue} '
        '| ${result.evalCase.expectedVerdict.jsonValue} '
        '| ${result.verdict?.jsonValue ?? 'invalid'} '
        '| ${result.confidence?.toStringAsFixed(2) ?? '-'} '
        '| ${result.matchesExpected ? 'match' : 'mismatch'} |',
      );
    }
    return buffer.toString();
  }

  String _metricsRow(String label, Ll37VerifierFidelityMetrics metrics) {
    return '| $label '
        '| ${metrics.totalCount} '
        '| ${metrics.correctCaseCount} '
        '| ${metrics.brokenCaseCount} '
        '| ${_percent(metrics.falseRefuteRate)} '
        '| ${_percent(metrics.brokenRecall)} '
        '| ${metrics.unverifiableCount} '
        '| ${metrics.invalidCount} |';
  }
}
