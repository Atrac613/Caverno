import '../entities/app_settings.dart';

/// LL39 score history for one model.
///
/// A single benchmark number cannot tell an improvement from noise. The repeat
/// sample needed to answer that already exists: `_buildUpdatedRevisions`
/// appends a revision on *every* probe, not only on change, and keeps up to
/// [ModelCapabilityProfileRevision.maxPerProfile] per model — so consecutive
/// unattended calibrations on an unchanged model are independent runs of the
/// same suite. Deriving the spread from them costs nothing, where re-running
/// the scored probes three times per run would roughly triple a ~55-request
/// suite.
class ModelBenchmarkHistory {
  const ModelBenchmarkHistory._(this.samples);

  /// Builds the history for [profileId], oldest first.
  ///
  /// Only revisions carrying a score from [suite] are kept: a revision from
  /// another suite version measured a different thing, and a revision with no
  /// score measured nothing. Mixing either in would manufacture a delta.
  factory ModelBenchmarkHistory.forProfile({
    required Iterable<ModelCapabilityProfileRevision> revisions,
    required String profileId,
    required String suite,
  }) {
    final samples = revisions
        .where((revision) => revision.profileId == profileId)
        .where((revision) => revision.hasBenchmarkScore)
        .where((revision) => revision.benchmarkSuite == suite)
        .toList(growable: false);
    return ModelBenchmarkHistory._(List.unmodifiable(samples));
  }

  final List<ModelCapabilityProfileRevision> samples;

  bool get isEmpty => samples.isEmpty;

  int? get latestPoints =>
      samples.isEmpty ? null : samples.last.benchmarkPoints;

  int? get previousPoints =>
      samples.length < 2 ? null : samples[samples.length - 2].benchmarkPoints;

  /// Latest minus previous. Null until there are two comparable runs.
  int? get delta {
    final latest = latestPoints;
    final previous = previousPoints;
    if (latest == null || previous == null) {
      return null;
    }
    return latest - previous;
  }

  /// Observed run-to-run range across the runs *before* the latest one, used as
  /// the noise floor. Range rather than a standard deviation because the sample
  /// is small (at most ten) and a range is what the user can check by eye
  /// against the history list.
  ///
  /// Null until at least two prior runs exist: with one prior run there is no
  /// observed variation, and treating that as a zero floor would report every
  /// downward wobble as a regression.
  int? get priorSpread {
    if (samples.length < 3) {
      return null;
    }
    final prior = samples
        .take(samples.length - 1)
        .map((revision) => revision.benchmarkPoints!)
        .toList(growable: false);
    var min = prior.first;
    var max = prior.first;
    for (final value in prior) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    return max - min;
  }

  /// True when the latest run dropped by more than the measured noise floor.
  ///
  /// Deliberately conservative: with no measured floor this stays false, so a
  /// new model never announces a regression on its second run.
  bool get regressionDetected {
    final currentDelta = delta;
    final spread = priorSpread;
    if (currentDelta == null || spread == null) {
      return false;
    }
    return currentDelta < 0 && currentDelta.abs() > spread;
  }

  /// Would [candidatePoints] be a regression against this history? Used before
  /// the new revision is appended, when the candidate is not a sample yet.
  bool regressionFor(int? candidatePoints) {
    if (candidatePoints == null || samples.isEmpty) {
      return false;
    }
    final projected = ModelBenchmarkHistory._([
      ...samples,
      samples.last.copyWith(benchmarkPoints: candidatePoints),
    ]);
    return projected.regressionDetected;
  }

  /// One line for the unattended morning report, e.g.
  /// `benchmark 812/1000 (-34 vs previous, spread 12 over 4 runs)`.
  /// Returns null when there is nothing measured to say.
  String? summaryLine() {
    final latest = latestPoints;
    if (latest == null) {
      return null;
    }
    final max = samples.last.benchmarkMaxPoints;
    final buffer = StringBuffer('benchmark $latest');
    if (max != null && max > 0) {
      buffer.write('/$max');
    }
    final currentDelta = delta;
    if (currentDelta == null) {
      buffer.write(' (first scored run)');
      return buffer.toString();
    }
    final sign = currentDelta >= 0 ? '+' : '';
    buffer.write(' ($sign$currentDelta vs previous');
    final spread = priorSpread;
    if (spread != null) {
      buffer.write(', spread $spread over ${samples.length - 1} runs');
    }
    buffer.write(')');
    if (regressionDetected) {
      buffer.write(' REGRESSION');
    }
    return buffer.toString();
  }
}
