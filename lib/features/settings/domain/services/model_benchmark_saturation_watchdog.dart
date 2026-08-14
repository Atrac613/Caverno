import '../entities/app_settings.dart';
import 'live_llm_diagnostic_scoring.dart';

class ModelBenchmarkSaturationSample {
  const ModelBenchmarkSaturationSample({
    required this.profileId,
    required this.model,
    required this.points,
    required this.maxPoints,
  });

  final String profileId;
  final String model;
  final int points;
  final int maxPoints;

  int get highWaterPoints =>
      LiveLlmDiagnosticSuite.saturationHighWaterPoints(maxPoints);

  bool get reachedHighWater => points >= highWaterPoints;

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'model': model,
    'points': points,
    'maxPoints': maxPoints,
    'highWaterPoints': highWaterPoints,
    'reachedHighWater': reachedHighWater,
  };
}

/// Declares when the bounded LL39 conformance suite no longer separates the
/// user's registered models.
///
/// The result fails closed: every unique registered profile must carry a score
/// from the requested suite, all denominators must match, and at least two
/// models must reach the high-water mark. Missing or stale evidence can never
/// announce saturation.
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
      if (points == null ||
          maximum == null ||
          maximum <= 0 ||
          points < 0 ||
          points > maximum) {
        continue;
      }
      samples.add(
        ModelBenchmarkSaturationSample(
          profileId: entry.key,
          model: profile.normalizedModel,
          points: points,
          maxPoints: maximum,
        ),
      );
    }
    samples.sort((a, b) => a.profileId.compareTo(b.profileId));
    final denominators = samples.map((sample) => sample.maxPoints).toSet();
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
