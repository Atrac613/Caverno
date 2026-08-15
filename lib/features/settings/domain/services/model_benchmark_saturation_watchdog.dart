import '../entities/app_settings.dart';
import 'live_llm_diagnostic_scoring.dart';

class ModelBenchmarkSaturationSample {
  const ModelBenchmarkSaturationSample({
    required this.profileId,
    required this.model,
    required this.points,
    required this.maxPoints,
    required this.attemptedPoints,
  });

  final String profileId;
  final String model;
  final int points;
  final int maxPoints;

  /// Points this run could actually measure. Older profiles predate the field
  /// and record the full denominator, which is what they effectively used.
  final int attemptedPoints;

  int get highWaterPoints =>
      LiveLlmDiagnosticSuite.saturationHighWaterPoints(attemptedPoints);

  bool get reachedHighWater => points >= highWaterPoints;

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'model': model,
    'points': points,
    'maxPoints': maxPoints,
    'attemptedPoints': attemptedPoints,
    'highWaterPoints': highWaterPoints,
    'reachedHighWater': reachedHighWater,
  };
}

/// Declares when the bounded LL39 conformance suite no longer separates the
/// user's registered models.
///
/// The result fails closed: every unique registered profile must carry a score
/// from the requested suite, all runs must have attempted the same points, and
/// at least two models must reach the high-water mark. Missing, stale, or
/// unlike evidence can never announce saturation.
class ModelBenchmarkSaturationWatchdog {
  const ModelBenchmarkSaturationWatchdog({
    required this.suite,
    required this.registeredModelCount,
    required this.samples,
    required this.denominatorConsistent,
  });

  factory ModelBenchmarkSaturationWatchdog.evaluate({
    required Iterable<ModelCapabilityProfile> profiles,
    required String suite,
  }) {
    final uniqueProfiles = <String, ModelCapabilityProfile>{};
    for (final profile in profiles) {
      final normalized = profile.normalizedForPersistence();
      if (normalized.normalizedModel.isNotEmpty) {
        uniqueProfiles[normalized.computedId] = normalized;
      }
    }

    final samples = <ModelBenchmarkSaturationSample>[];
    for (final entry in uniqueProfiles.entries) {
      final profile = entry.value;
      if (profile.probeMetadata['benchmarkSuite'] != suite) {
        continue;
      }
      final points = int.tryParse(
        profile.probeMetadata['benchmarkPoints']?.trim() ?? '',
      );
      final maximum = int.tryParse(
        profile.probeMetadata['benchmarkMaxPoints']?.trim() ?? '',
      );
      final attempted =
          int.tryParse(
            profile.probeMetadata['benchmarkAttemptedPoints']?.trim() ?? '',
          ) ??
          maximum;
      if (points == null ||
          maximum == null ||
          maximum <= 0 ||
          attempted == null ||
          attempted <= 0 ||
          attempted > maximum ||
          points < 0 ||
          points > attempted) {
        continue;
      }
      samples.add(
        ModelBenchmarkSaturationSample(
          profileId: entry.key,
          model: profile.normalizedModel,
          points: points,
          maxPoints: maximum,
          attemptedPoints: attempted,
        ),
      );
    }
    samples.sort((a, b) => a.profileId.compareTo(b.profileId));
    // Compared on attempted points: two models are only comparable when their
    // runs measured the same things, which the fixed maximum cannot express.
    final denominators = samples
        .map((sample) => sample.attemptedPoints)
        .toSet();
    return ModelBenchmarkSaturationWatchdog(
      suite: suite,
      registeredModelCount: uniqueProfiles.length,
      samples: List.unmodifiable(samples),
      denominatorConsistent: denominators.length <= 1,
    );
  }

  final String suite;
  final int registeredModelCount;
  final List<ModelBenchmarkSaturationSample> samples;
  final bool denominatorConsistent;

  int get scoredModelCount => samples.length;

  int get highWaterModelCount =>
      samples.where((sample) => sample.reachedHighWater).length;

  bool get hasCompleteCoverage =>
      registeredModelCount > 0 && scoredModelCount == registeredModelCount;

  bool get isSaturated =>
      registeredModelCount >= LiveLlmDiagnosticSuite.saturationMinimumModels &&
      hasCompleteCoverage &&
      denominatorConsistent &&
      highWaterModelCount == registeredModelCount;

  Map<String, dynamic> toJson() => {
    'suite': suite,
    'highWaterPercent': LiveLlmDiagnosticSuite.saturationHighWaterPercent,
    'minimumModels': LiveLlmDiagnosticSuite.saturationMinimumModels,
    'registeredModelCount': registeredModelCount,
    'scoredModelCount': scoredModelCount,
    'highWaterModelCount': highWaterModelCount,
    'hasCompleteCoverage': hasCompleteCoverage,
    'denominatorConsistent': denominatorConsistent,
    'isSaturated': isSaturated,
    'samples': samples.map((sample) => sample.toJson()).toList(),
  };
}
