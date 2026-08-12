import '../entities/live_llm_diagnostic.dart';

/// LL39 benchmark scoring for the Live LLM diagnostic.
///
/// The percentage this replaces divided passes by *scored* probes, so a run
/// that skipped six probes reported 3/3 as 100%: the denominator moved with
/// the environment and two runs could not be compared. Points come from a
/// fixed table instead. Every model on every machine is measured against the
/// same [maxPoints], and what a run could not attempt shows up as coverage
/// rather than as a better score.
class LiveLlmDiagnosticSuite {
  const LiveLlmDiagnosticSuite._();

  static const id = 'cavernobench';

  /// Bump whenever the probe set, a weight, or a pass rule changes. Scores
  /// from two versions are not comparable, and consumers must refuse to diff
  /// them rather than silently showing a delta.
  ///
  /// v2 adds the vision block and rebalances the existing weights so the
  /// maximum stays at [maxPoints]: a growing total would make every historical
  /// score look worse for free. v3 adds streaming; v4 adds the sequential
  /// multi-round tool-loop probe, each time rebalancing to the same maximum.
  static const version = 4;

  /// Points per probe. Weighted by how much of Caverno's agent loop the probe
  /// actually stands for: the tool-result round trip and the first tool call
  /// carry a turn, while remote MCP exposure only reports what the environment
  /// loaded.
  static const probePoints = <String, int>{
    'instruction_echo': 60,
    'streaming_response': 65,
    'exact_preservation': 75,
    'foundation_models_language_matrix': 30,
    'vision_attachment': 65,
    'vision_tool_observation': 45,
    'narrow_tool_call': 80,
    'update_goal_fidelity': 70,
    'tool_result_integration': 90,
    'multi_round_tool_loop': 80,
    'initial_harness_selection': 60,
    'tool_search_catalog': 40,
    'subagent_recognition': 25,
    'remote_mcp_exposure': 15,
  };

  /// The LL16 sampler trials are the largest sample a run takes (32 of ~43
  /// requests) and used to contribute nothing. They score as one stability
  /// block rather than per trial, because a single trial is noise.
  static const samplerStabilityPoints = 200;

  static const probePointsTotal = 800;

  static const maxPoints = probePointsTotal + samplerStabilityPoints;

  /// Credit for a probe that partially held. Used only when the probe did not
  /// report sub-check counts; a probe that knows it passed 2 of 3 checks
  /// scores that ratio instead.
  static const warningCreditRatio = 0.5;

  static int pointsFor(String probeId) => probePoints[probeId] ?? 0;
}

/// One probe's contribution, kept so the UI and the exported report can show
/// where the points went instead of only the total.
class LiveLlmDiagnosticProbeScore {
  const LiveLlmDiagnosticProbeScore({
    required this.id,
    required this.earnedPoints,
    required this.maxPoints,
    required this.attempted,
  });

  final String id;
  final double earnedPoints;
  final int maxPoints;

  /// False when the probe never ran (skipped by the environment, the provider,
  /// or a bounded run). Unattempted points stay out of [
  /// LiveLlmDiagnosticScore.attemptedPoints] so "could not measure" never reads
  /// as "measured and failed".
  final bool attempted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'earnedPoints': _round(earnedPoints),
    'maxPoints': maxPoints,
    'attempted': attempted,
  };
}

/// Absolute benchmark result for one diagnostic run.
class LiveLlmDiagnosticScore {
  const LiveLlmDiagnosticScore({
    required this.probeScores,
    required this.probeEarnedPoints,
    required this.samplerEarnedPoints,
    required this.samplerAttempted,
    required this.samplerTrialCount,
    required this.samplerPassedCount,
  });

  factory LiveLlmDiagnosticScore.fromReport(LiveLlmDiagnosticReport report) {
    final probeScores = <LiveLlmDiagnosticProbeScore>[];
    var probeEarned = 0.0;
    for (final entry in LiveLlmDiagnosticSuite.probePoints.entries) {
      final result = _resultFor(report, entry.key);
      final earned = _earnedFor(result, entry.value);
      probeEarned += earned;
      probeScores.add(
        LiveLlmDiagnosticProbeScore(
          id: entry.key,
          earnedPoints: earned,
          maxPoints: entry.value,
          attempted: _isAttempted(result),
        ),
      );
    }

    final trials = report.samplerCalibrationTrials;
    final passedTrials = trials.where((trial) => trial.passed).length;
    final samplerEarned = trials.isEmpty
        ? 0.0
        : LiveLlmDiagnosticSuite.samplerStabilityPoints *
              (passedTrials / trials.length);

    return LiveLlmDiagnosticScore(
      probeScores: List.unmodifiable(probeScores),
      probeEarnedPoints: probeEarned,
      samplerEarnedPoints: samplerEarned,
      samplerAttempted: trials.isNotEmpty,
      samplerTrialCount: trials.length,
      samplerPassedCount: passedTrials,
    );
  }

  final List<LiveLlmDiagnosticProbeScore> probeScores;
  final double probeEarnedPoints;
  final double samplerEarnedPoints;
  final bool samplerAttempted;
  final int samplerTrialCount;
  final int samplerPassedCount;

  /// The headline figure: comparable across models because [maxPoints] never
  /// moves.
  int get earnedPoints => _round(probeEarnedPoints + samplerEarnedPoints);

  int get maxPoints => LiveLlmDiagnosticSuite.maxPoints;

  /// Points the run was actually able to measure. Compare two runs directly
  /// only when this matches; otherwise the environments differed.
  int get attemptedPoints {
    var attempted = 0;
    for (final score in probeScores) {
      if (score.attempted) {
        attempted += score.maxPoints;
      }
    }
    if (samplerAttempted) {
      attempted += LiveLlmDiagnosticSuite.samplerStabilityPoints;
    }
    return attempted;
  }

  double get coverage => attemptedPoints / maxPoints;

  /// Share of the points the run could attempt. Kept separate from
  /// [earnedPoints] so a narrow environment cannot inflate the headline.
  double get attemptedRatio =>
      attemptedPoints == 0 ? 0 : earnedPoints / attemptedPoints;

  Map<String, dynamic> toJson() => {
    'suiteId': LiveLlmDiagnosticSuite.id,
    'suiteVersion': LiveLlmDiagnosticSuite.version,
    'earnedPoints': earnedPoints,
    'maxPoints': maxPoints,
    'attemptedPoints': attemptedPoints,
    'coverage': coverage,
    'samplerTrialCount': samplerTrialCount,
    'samplerPassedCount': samplerPassedCount,
    'probes': probeScores.map((score) => score.toJson()).toList(),
  };

  static LiveLlmDiagnosticProbeResult? _resultFor(
    LiveLlmDiagnosticReport report,
    String id,
  ) {
    for (final result in report.results) {
      if (result.id == id) {
        return result;
      }
    }
    return null;
  }

  static bool _isAttempted(LiveLlmDiagnosticProbeResult? result) {
    if (result == null) {
      return false;
    }
    return switch (result.status) {
      LiveLlmDiagnosticStatus.passed ||
      LiveLlmDiagnosticStatus.warning ||
      LiveLlmDiagnosticStatus.failed => true,
      LiveLlmDiagnosticStatus.pending ||
      LiveLlmDiagnosticStatus.running ||
      LiveLlmDiagnosticStatus.skipped => false,
    };
  }

  static double _earnedFor(LiveLlmDiagnosticProbeResult? result, int weight) {
    if (result == null) {
      return 0;
    }
    return switch (result.status) {
      LiveLlmDiagnosticStatus.passed => weight.toDouble(),
      LiveLlmDiagnosticStatus.warning => weight * _warningRatio(result),
      _ => 0,
    };
  }

  /// A probe that counted its own sub-checks scores that ratio; one that only
  /// knows "not clean" falls back to half credit.
  static double _warningRatio(LiveLlmDiagnosticProbeResult result) {
    if (result.totalChecks <= 0) {
      return LiveLlmDiagnosticSuite.warningCreditRatio;
    }
    final passed = result.passedChecks.clamp(0, result.totalChecks);
    return passed / result.totalChecks;
  }
}

/// Full export shape for a diagnostic run: the report plus its benchmark
/// block. One place owns it so the copied JSON and any stored artifact agree.
Map<String, dynamic> buildLiveLlmDiagnosticExport(
  LiveLlmDiagnosticReport report,
) {
  return {
    ...report.toJson(),
    'benchmark': LiveLlmDiagnosticScore.fromReport(report).toJson(),
  };
}

int _round(double value) => value.round();
