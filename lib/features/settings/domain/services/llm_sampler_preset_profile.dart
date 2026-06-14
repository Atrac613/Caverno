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
    return LlmSamplerPresetProfile._(
      profile == null
          ? const <String, String>{}
          : Map<String, String>.from(profile.probeMetadata),
    );
  }

  static const String metadataPrefix = 'll16.sampler';
  static const double maxSupportedTemperature = 2.0;

  final Map<String, String> _metadata;

  double? temperatureFor(LlmSamplerRequestClass requestClass) {
    return _temperatureFor(requestClass) ??
        _temperatureFor(LlmSamplerRequestClass.agentic);
  }

  static String temperatureKey(LlmSamplerRequestClass requestClass) {
    return '$metadataPrefix.${requestClass.metadataName}.temperature';
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
