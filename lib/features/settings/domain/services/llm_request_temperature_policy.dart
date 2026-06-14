import '../../../../core/types/assistant_mode.dart';
import '../entities/app_settings.dart';
import 'llm_sampler_preset_profile.dart';

class LlmRequestTemperaturePolicy {
  const LlmRequestTemperaturePolicy({
    required this.chatTemperature,
    double agenticTemperature = managedAgenticTemperature,
    double? toolLoopTemperature,
    double? codingTemperature,
    double? planTemperature,
    double? routineTemperature,
    double? subagentTemperature,
  }) : agenticTemperature = agenticTemperature == 0.0
           ? minimumAgenticTemperature
           : agenticTemperature,
       toolLoopTemperature = (toolLoopTemperature ?? agenticTemperature) == 0.0
           ? minimumAgenticTemperature
           : (toolLoopTemperature ?? agenticTemperature),
       codingTemperature = (codingTemperature ?? agenticTemperature) == 0.0
           ? minimumAgenticTemperature
           : (codingTemperature ?? agenticTemperature),
       planTemperature = (planTemperature ?? agenticTemperature) == 0.0
           ? minimumAgenticTemperature
           : (planTemperature ?? agenticTemperature),
       routineTemperature = (routineTemperature ?? agenticTemperature) == 0.0
           ? minimumAgenticTemperature
           : (routineTemperature ?? agenticTemperature),
       subagentTemperature = (subagentTemperature ?? agenticTemperature) == 0.0
           ? minimumAgenticTemperature
           : (subagentTemperature ?? agenticTemperature);

  factory LlmRequestTemperaturePolicy.forSettings(AppSettings settings) {
    final presets = LlmSamplerPresetProfile.fromModelProfile(
      settings.effectiveModelCapabilityProfile,
    );
    return LlmRequestTemperaturePolicy(
      chatTemperature: settings.temperature,
      agenticTemperature:
          presets.temperatureFor(LlmSamplerRequestClass.agentic) ??
          managedAgenticTemperature,
      toolLoopTemperature: presets.temperatureFor(
        LlmSamplerRequestClass.toolLoop,
      ),
      codingTemperature: presets.temperatureFor(LlmSamplerRequestClass.coding),
      planTemperature: presets.temperatureFor(LlmSamplerRequestClass.plan),
      routineTemperature: presets.temperatureFor(
        LlmSamplerRequestClass.routine,
      ),
      subagentTemperature: presets.temperatureFor(
        LlmSamplerRequestClass.subagent,
      ),
    );
  }

  static const double minimumAgenticTemperature = 0.1;
  static const double managedAgenticTemperature = 0.2;

  final double chatTemperature;
  final double agenticTemperature;
  final double toolLoopTemperature;
  final double codingTemperature;
  final double planTemperature;
  final double routineTemperature;
  final double subagentTemperature;

  double temperatureForAssistantMode(AssistantMode mode) {
    return switch (mode) {
      AssistantMode.general => chatTemperature,
      AssistantMode.coding => codingTemperature,
      AssistantMode.plan => planTemperature,
    };
  }
}
