import '../entities/app_settings.dart';
import 'llm_request_temperature_policy.dart';
import 'llm_sampler_preset_profile.dart';

class LlmSamplerCalibrationTrial {
  const LlmSamplerCalibrationTrial({
    required this.requestClass,
    required this.temperature,
    required this.passed,
    this.jsonRepairEventCount = 0,
    this.malformedToolCallCount = 0,
    this.editApplyFailureCount = 0,
    this.repetitionDetected = false,
  });

  final LlmSamplerRequestClass requestClass;
  final double temperature;
  final bool passed;
  final int jsonRepairEventCount;
  final int malformedToolCallCount;
  final int editApplyFailureCount;
  final bool repetitionDetected;
}

class LlmSamplerCalibrationSelection {
  const LlmSamplerCalibrationSelection({
    required this.requestClass,
    required this.temperature,
    required this.score,
    required this.trialCount,
    required this.successCount,
    required this.repetitionCount,
  });

  final LlmSamplerRequestClass requestClass;
  final double temperature;
  final double score;
  final int trialCount;
  final int successCount;
  final int repetitionCount;

  Map<String, String> applyToMetadata(Map<String, String> metadata) {
    return LlmSamplerPresetProfile.withCalibration(
      metadata: metadata,
      requestClass: requestClass,
      temperature: temperature,
      score: score,
      trialCount: trialCount,
    );
  }
}

class LlmSamplerCalibrationService {
  const LlmSamplerCalibrationService();

  static const double jsonRepairPenalty = 0.04;
  static const double malformedToolCallPenalty = 0.12;
  static const double editApplyFailurePenalty = 0.1;
  static const double repetitionPenalty = 1.0;

  LlmSamplerCalibrationSelection? selectTemperature({
    required LlmSamplerRequestClass requestClass,
    required Iterable<LlmSamplerCalibrationTrial> trials,
  }) {
    final buckets = <double, _SamplerTemperatureBucket>{};
    for (final trial in trials) {
      if (trial.requestClass != requestClass || !_isValidTemperature(trial)) {
        continue;
      }
      buckets
          .putIfAbsent(
            trial.temperature,
            () => _SamplerTemperatureBucket(temperature: trial.temperature),
          )
          .add(trial);
    }
    if (buckets.isEmpty) {
      return null;
    }

    final candidates =
        buckets.values
            .map((bucket) => bucket.toSelection(requestClass))
            .toList(growable: false)
          ..sort(_compareSelections);
    return candidates.first;
  }

  ModelCapabilityProfile applySelectionToProfile({
    required ModelCapabilityProfile profile,
    required LlmSamplerCalibrationSelection selection,
  }) {
    if (LlmSamplerPresetProfile.fromModelProfile(
      profile,
    ).hasUserConfiguredTemperatureFor(selection.requestClass)) {
      return profile.normalizedForPersistence();
    }
    return profile
        .copyWith(
          probeMetadata: selection.applyToMetadata(profile.probeMetadata),
        )
        .normalizedForPersistence();
  }

  bool _isValidTemperature(LlmSamplerCalibrationTrial trial) {
    final temperature = trial.temperature;
    return !temperature.isNaN &&
        !temperature.isInfinite &&
        temperature >= 0.0 &&
        temperature <= LlmSamplerPresetProfile.maxSupportedTemperature;
  }

  int _compareSelections(
    LlmSamplerCalibrationSelection left,
    LlmSamplerCalibrationSelection right,
  ) {
    final scoreCompare = right.score.compareTo(left.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final leftDistance = _managedDefaultDistance(left.temperature);
    final rightDistance = _managedDefaultDistance(right.temperature);
    final distanceCompare = leftDistance.compareTo(rightDistance);
    if (distanceCompare != 0) {
      return distanceCompare;
    }
    return left.temperature.compareTo(right.temperature);
  }

  double _managedDefaultDistance(double temperature) {
    return (temperature - LlmRequestTemperaturePolicy.managedAgenticTemperature)
        .abs();
  }
}

class _SamplerTemperatureBucket {
  _SamplerTemperatureBucket({required this.temperature});

  final double temperature;
  int trialCount = 0;
  int successCount = 0;
  int jsonRepairEventCount = 0;
  int malformedToolCallCount = 0;
  int editApplyFailureCount = 0;
  int repetitionCount = 0;

  void add(LlmSamplerCalibrationTrial trial) {
    trialCount += 1;
    if (trial.passed) {
      successCount += 1;
    }
    jsonRepairEventCount += _positiveCount(trial.jsonRepairEventCount);
    malformedToolCallCount += _positiveCount(trial.malformedToolCallCount);
    editApplyFailureCount += _positiveCount(trial.editApplyFailureCount);
    if (trial.repetitionDetected) {
      repetitionCount += 1;
    }
  }

  LlmSamplerCalibrationSelection toSelection(
    LlmSamplerRequestClass requestClass,
  ) {
    final repairRate = jsonRepairEventCount / trialCount;
    final malformedRate = malformedToolCallCount / trialCount;
    final editFailureRate = editApplyFailureCount / trialCount;
    final repetitionRate = repetitionCount / trialCount;
    final score =
        successCount / trialCount -
        repairRate * LlmSamplerCalibrationService.jsonRepairPenalty -
        malformedRate * LlmSamplerCalibrationService.malformedToolCallPenalty -
        editFailureRate * LlmSamplerCalibrationService.editApplyFailurePenalty -
        repetitionRate * LlmSamplerCalibrationService.repetitionPenalty;
    return LlmSamplerCalibrationSelection(
      requestClass: requestClass,
      temperature: temperature,
      score: score,
      trialCount: trialCount,
      successCount: successCount,
      repetitionCount: repetitionCount,
    );
  }

  int _positiveCount(int value) => value < 0 ? 0 : value;
}
