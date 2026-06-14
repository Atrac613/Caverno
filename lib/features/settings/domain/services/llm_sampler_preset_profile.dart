import '../entities/app_settings.dart';

enum LlmSamplerRequestClass {
  agentic('agentic'),
  toolLoop('toolLoop'),
  coding('coding'),
  plan('plan'),
  routine('routine'),
  subagent('subagent');

  const LlmSamplerRequestClass(this.metadataName);

  final String metadataName;
}

class LlmSamplerPresetProfile {
  const LlmSamplerPresetProfile._(this._metadata);

  factory LlmSamplerPresetProfile.fromModelProfile(
    ModelCapabilityProfile? profile,
  ) {
    return LlmSamplerPresetProfile.fromMetadata(
      profile == null
          ? const <String, String>{}
          : Map<String, String>.from(profile.probeMetadata),
    );
  }

  factory LlmSamplerPresetProfile.fromMetadata(Map<String, String> metadata) {
    return LlmSamplerPresetProfile._(Map<String, String>.from(metadata));
  }

  static const String metadataPrefix = 'll16.sampler';
  static const double maxSupportedTemperature = 2.0;
  static const String probeSource = 'probe';
  static const String runtimeFeedbackSource = 'runtimeFeedback';
  static const String userSource = 'user';

  final Map<String, String> _metadata;

  double? temperatureFor(LlmSamplerRequestClass requestClass) {
    return _temperatureFor(requestClass) ??
        _temperatureFor(LlmSamplerRequestClass.agentic);
  }

  static String temperatureKey(LlmSamplerRequestClass requestClass) {
    return '$metadataPrefix.${requestClass.metadataName}.temperature';
  }

  static String scoreKey(LlmSamplerRequestClass requestClass) {
    return '$metadataPrefix.${requestClass.metadataName}.score';
  }

  static String trialCountKey(LlmSamplerRequestClass requestClass) {
    return '$metadataPrefix.${requestClass.metadataName}.trialCount';
  }

  static String sourceKey(LlmSamplerRequestClass requestClass) {
    return '$metadataPrefix.${requestClass.metadataName}.source';
  }

  String? sourceFor(LlmSamplerRequestClass requestClass) {
    final source = _metadata[sourceKey(requestClass)]?.trim();
    return source == null || source.isEmpty ? null : source;
  }

  bool hasUserConfiguredTemperatureFor(LlmSamplerRequestClass requestClass) {
    if (isUserConfiguredSource(sourceFor(requestClass))) {
      return true;
    }
    if (_temperatureFor(requestClass) != null) {
      return false;
    }
    return isUserConfiguredSource(sourceFor(LlmSamplerRequestClass.agentic));
  }

  static bool isUserConfiguredSource(String? source) {
    final normalized = source?.trim().toLowerCase();
    return normalized == userSource ||
        normalized == 'manual' ||
        normalized == 'explicit';
  }

  static Map<String, String> withTemperature({
    required Map<String, String> metadata,
    required LlmSamplerRequestClass requestClass,
    required double temperature,
  }) {
    return <String, String>{
      ...metadata,
      temperatureKey(requestClass): temperature.toString(),
    };
  }

  static Map<String, String> withCalibration({
    required Map<String, String> metadata,
    required LlmSamplerRequestClass requestClass,
    required double temperature,
    required double score,
    required int trialCount,
    String source = probeSource,
  }) {
    return <String, String>{
      ...metadata,
      temperatureKey(requestClass): temperature.toString(),
      scoreKey(requestClass): score.toStringAsFixed(3),
      trialCountKey(requestClass): trialCount.toString(),
      sourceKey(requestClass): source,
    };
  }

  double? _temperatureFor(LlmSamplerRequestClass requestClass) {
    return _readTemperature(_metadata[temperatureKey(requestClass)]);
  }

  static double? _readTemperature(String? value) {
    if (value == null) {
      return null;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null ||
        parsed.isNaN ||
        parsed.isInfinite ||
        parsed < 0.0 ||
        parsed > maxSupportedTemperature) {
      return null;
    }
    return parsed;
  }
}
