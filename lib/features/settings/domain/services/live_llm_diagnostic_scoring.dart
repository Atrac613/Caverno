import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_difficulty_ladder.dart';

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
  /// v5 adds edit-format fidelity, v6 adds embeddings capability, v7 adds
  /// structured output, and v8 adds the opt-in effective-context capability.
  /// The context probe is physical measurement only, so it carries zero
  /// conformance points and does not distort the fixed denominator. v9 fixes
  /// the scored unified-diff prompt after live A/B evidence showed that its
  /// ambiguous context-line wording induced an invalid hunk count.
  static const version = 9;

  /// Points per probe. Weighted by how much of Caverno's agent loop the probe
  /// actually stands for: the tool-result round trip and the first tool call
  /// carry a turn, while remote MCP exposure only reports what the environment
  /// loaded.
  static const probePoints = <String, int>{
    'instruction_echo': 40,
    'structured_output': 50,
    'streaming_response': 50,
    'exact_preservation': 60,
    'edit_format_fidelity': 55,
    'embeddings_capability': 55,
    'effective_context': 0,
    'foundation_models_language_matrix': 20,
    'vision_attachment': 50,
    'vision_tool_observation': 35,
    // Zero for the same reason as effective_context: this reports what the
    // endpoint accepts, not what the model can do, so it must not move a
    // model's score. Keeping it weightless also leaves probePointsTotal and
    // the suite version alone, so existing score history stays comparable.
    'video_input_modality': 0,
    'narrow_tool_call': 65,
    'update_goal_fidelity': 60,
    'tool_result_integration': 75,
    'multi_round_tool_loop': 65,
    'initial_harness_selection': 45,
    'tool_search_catalog': 35,
    'subagent_recognition': 25,
    'remote_mcp_exposure': 15,
  };

  /// The LL16 sampler trials are the largest sample a run takes (32 of ~43
  /// requests) and used to contribute nothing. They score as one stability
  /// block rather than per trial, because a single trial is noise.
  static const samplerStabilityPoints = 200;

  static const probePointsTotal = 800;

  static const maxPoints = probePointsTotal + samplerStabilityPoints;

  /// A model at or above this share of the points its run could attempt
  /// contributes a high-water sample to the cross-model saturation watchdog.
  ///
  /// Measured against attempted points, not the fixed denominator: a probe the
  /// environment cannot run (no embeddings model, an endpoint that rejects
  /// `temperature` so the 200-point sampler block is unmeasurable) would
  /// otherwise put the mark out of reach forever and silently disable
  /// saturation detection for that endpoint. Cross-model comparability is
  /// preserved by the watchdog's denominator check instead, which refuses to
  /// declare saturation across runs that attempted different amounts.
  static const saturationHighWaterPercent = 95;

  /// Saturation is a cross-model claim. One strong model only proves that the
  /// model is conformant, not that the suite stopped discriminating.
  static const saturationMinimumModels = 2;

  static int saturationHighWaterPoints(int maximum) =>
      (maximum * saturationHighWaterPercent + 99) ~/ 100;

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

  int get saturationHighWaterPoints =>
      LiveLlmDiagnosticSuite.saturationHighWaterPoints(attemptedPoints);

  bool get saturationHighWaterReached =>
      earnedPoints >= saturationHighWaterPoints;

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
    'saturationHighWaterPercent':
        LiveLlmDiagnosticSuite.saturationHighWaterPercent,
    'saturationHighWaterPoints': saturationHighWaterPoints,
    'saturationHighWaterReached': saturationHighWaterReached,
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
    'difficultyLadder': LiveLlmDiagnosticDifficultyLadder.fromReport(
      report,
    ).toJson(),
  };
}

int _round(double value) => value.round();
