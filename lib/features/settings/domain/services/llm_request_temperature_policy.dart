import '../../../../core/types/assistant_mode.dart';
import '../entities/app_settings.dart';

class LlmRequestTemperaturePolicy {
  const LlmRequestTemperaturePolicy({
    required this.chatTemperature,
    double agenticTemperature = managedAgenticTemperature,
  }) : agenticTemperature = agenticTemperature == 0.0
           ? minimumAgenticTemperature
           : agenticTemperature;

  factory LlmRequestTemperaturePolicy.forSettings(AppSettings settings) {
    return LlmRequestTemperaturePolicy(chatTemperature: settings.temperature);
  }

  static const double minimumAgenticTemperature = 0.1;
  static const double managedAgenticTemperature = 0.2;

  final double chatTemperature;
  final double agenticTemperature;

  double get toolLoopTemperature => agenticTemperature;
  double get routineTemperature => agenticTemperature;
  double get subagentTemperature => agenticTemperature;

  double temperatureForAssistantMode(AssistantMode mode) {
    return switch (mode) {
      AssistantMode.general => chatTemperature,
      AssistantMode.coding || AssistantMode.plan => agenticTemperature,
    };
  }
}
