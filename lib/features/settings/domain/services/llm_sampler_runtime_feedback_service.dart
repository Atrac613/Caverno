import '../entities/app_settings.dart';
import 'llm_request_temperature_policy.dart';
import 'llm_sampler_preset_profile.dart';

class LlmSamplerRuntimeFeedbackSignal {
  const LlmSamplerRuntimeFeedbackSignal({
    required this.requestClass,
    this.jsonRepairEventCount = 0,
    this.malformedToolCallCount = 0,
    this.editApplyFailureCount = 0,
    this.repetitionDetected = false,
  });

  final LlmSamplerRequestClass requestClass;
  final int jsonRepairEventCount;
  final int malformedToolCallCount;
  final int editApplyFailureCount;
  final bool repetitionDetected;

  bool get hasSignal =>
      jsonRepairEventCount > 0 ||
      malformedToolCallCount > 0 ||
      editApplyFailureCount > 0 ||
      repetitionDetected;
}

class LlmSamplerRuntimeFeedbackResult {
  const LlmSamplerRuntimeFeedbackResult({
    required this.profile,
    required this.temperatureAdjusted,
    this.previousTemperature,
    this.adjustedTemperature,
  });

  final ModelCapabilityProfile profile;
  final bool temperatureAdjusted;
  final double? previousTemperature;
  final double? adjustedTemperature;
}

class LlmSamplerRuntimeFeedbackService {
  const LlmSamplerRuntimeFeedbackService();

  static const int jsonRepairAdjustmentThreshold = 2;
  static const int malformedToolCallAdjustmentThreshold = 2;
  static const int editApplyFailureAdjustmentThreshold = 2;
  static const int repetitionAdjustmentThreshold = 1;
  static const String runtimeSource = 'runtimeFeedback';
  static const _temperatureCandidates = <double>[0.7, 0.4, 0.2, 0.1];

  static String jsonRepairCountKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'jsonRepairCount');
  }

  static String malformedToolCallCountKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'malformedToolCallCount');
  }

  static String editApplyFailureCountKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'editApplyFailureCount');
  }

  static String repetitionCountKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'repetitionCount');
  }

  static String adjustmentCountKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'adjustmentCount');
  }

  static String previousTemperatureKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'previousTemperature');
  }

  static String lastAdjustmentReasonKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'lastAdjustmentReason');
  }

  static String lastObservedAtKey(LlmSamplerRequestClass requestClass) {
    return _runtimeKey(requestClass, 'lastObservedAt');
  }

  static bool looksLikeMalformedToolCallFailure(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('no matching tool') ||
        normalized.contains('unknown tool') ||
        normalized.contains('malformed') ||
        normalized.contains('invalid') ||
        (normalized.contains('required') &&
            (normalized.contains('argument') ||
                normalized.contains('parameter') ||
                normalized.contains('field') ||
                normalized.contains('path') ||
                normalized.contains('pattern')));
  }

  LlmSamplerRuntimeFeedbackResult? recordSignal({
    required ModelCapabilityProfile profile,
    required LlmSamplerRuntimeFeedbackSignal signal,
    DateTime? observedAt,
  }) {
    if (!signal.hasSignal) {
      return null;
    }

    final metadata = Map<String, String>.from(profile.probeMetadata);
    final requestClass = signal.requestClass;
    _increment(
      metadata,
      jsonRepairCountKey(requestClass),
      signal.jsonRepairEventCount,
    );
    _increment(
      metadata,
      malformedToolCallCountKey(requestClass),
      signal.malformedToolCallCount,
    );
    _increment(
      metadata,
      editApplyFailureCountKey(requestClass),
      signal.editApplyFailureCount,
    );
    if (signal.repetitionDetected) {
      _increment(metadata, repetitionCountKey(requestClass), 1);
    }
    metadata[lastObservedAtKey(requestClass)] = (observedAt ?? DateTime.now())
        .toUtc()
        .toIso8601String();

    final currentTemperature = _currentTemperature(profile, requestClass);
    final adjustedTemperature = _shouldAdjust(metadata, requestClass)
        ? _nextLowerTemperature(currentTemperature)
        : currentTemperature;
    final temperatureAdjusted = adjustedTemperature < currentTemperature;
    if (temperatureAdjusted) {
      metadata[LlmSamplerPresetProfile.temperatureKey(requestClass)] =
          adjustedTemperature.toString();
      metadata[LlmSamplerPresetProfile.sourceKey(requestClass)] = runtimeSource;
      metadata[previousTemperatureKey(requestClass)] = currentTemperature
          .toString();
      metadata[lastAdjustmentReasonKey(requestClass)] = _adjustmentReason(
        metadata,
        requestClass,
      );
      _increment(metadata, adjustmentCountKey(requestClass), 1);
    }

    return LlmSamplerRuntimeFeedbackResult(
      profile: profile
          .copyWith(probeMetadata: metadata)
          .normalizedForPersistence(),
      temperatureAdjusted: temperatureAdjusted,
      previousTemperature: temperatureAdjusted ? currentTemperature : null,
      adjustedTemperature: temperatureAdjusted ? adjustedTemperature : null,
    );
  }

  static String _runtimeKey(
    LlmSamplerRequestClass requestClass,
    String metric,
  ) {
    return '${LlmSamplerPresetProfile.metadataPrefix}.'
        '${requestClass.metadataName}.runtime.$metric';
  }

  static void _increment(
    Map<String, String> metadata,
    String key,
    int incrementBy,
  ) {
    if (incrementBy <= 0) {
      return;
    }
    metadata[key] = (_readInt(metadata[key]) + incrementBy).toString();
  }

  static bool _shouldAdjust(
    Map<String, String> metadata,
    LlmSamplerRequestClass requestClass,
  ) {
    return _readInt(metadata[jsonRepairCountKey(requestClass)]) >=
            jsonRepairAdjustmentThreshold ||
        _readInt(metadata[malformedToolCallCountKey(requestClass)]) >=
            malformedToolCallAdjustmentThreshold ||
        _readInt(metadata[editApplyFailureCountKey(requestClass)]) >=
            editApplyFailureAdjustmentThreshold ||
        _readInt(metadata[repetitionCountKey(requestClass)]) >=
            repetitionAdjustmentThreshold;
  }

  static String _adjustmentReason(
    Map<String, String> metadata,
    LlmSamplerRequestClass requestClass,
  ) {
    final reasons = <String>[
      if (_readInt(metadata[repetitionCountKey(requestClass)]) >=
          repetitionAdjustmentThreshold)
        'repetition',
      if (_readInt(metadata[malformedToolCallCountKey(requestClass)]) >=
          malformedToolCallAdjustmentThreshold)
        'malformedToolCall',
      if (_readInt(metadata[editApplyFailureCountKey(requestClass)]) >=
          editApplyFailureAdjustmentThreshold)
        'editApplyFailure',
      if (_readInt(metadata[jsonRepairCountKey(requestClass)]) >=
          jsonRepairAdjustmentThreshold)
        'jsonRepair',
    ];
    return reasons.join(',');
  }

  static double _currentTemperature(
    ModelCapabilityProfile profile,
    LlmSamplerRequestClass requestClass,
  ) {
    return LlmSamplerPresetProfile.fromModelProfile(
          profile,
        ).temperatureFor(requestClass) ??
        LlmRequestTemperaturePolicy.managedAgenticTemperature;
  }

  static double _nextLowerTemperature(double currentTemperature) {
    for (final candidate in _temperatureCandidates) {
      if (candidate < currentTemperature - 0.0001) {
        return candidate;
      }
    }
    return currentTemperature;
  }

  static int _readInt(String? value) {
    if (value == null) {
      return 0;
    }
    return int.tryParse(value) ?? 0;
  }
}
