import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/llm_request_temperature_policy.dart';

void main() {
  AppSettings settingsWithTemperature(double temperature) {
    return AppSettings.defaults().copyWith(temperature: temperature);
  }

  test('preserves the chat temperature for general prose', () {
    final policy = LlmRequestTemperaturePolicy.forSettings(
      settingsWithTemperature(0.9),
    );

    expect(policy.temperatureForAssistantMode(AssistantMode.general), 0.9);
  });

  test('uses the managed agentic temperature for tool-heavy surfaces', () {
    final policy = LlmRequestTemperaturePolicy.forSettings(
      settingsWithTemperature(1.7),
    );

    expect(policy.temperatureForAssistantMode(AssistantMode.coding), 0.2);
    expect(policy.temperatureForAssistantMode(AssistantMode.plan), 0.2);
    expect(policy.toolLoopTemperature, 0.2);
    expect(policy.routineTemperature, 0.2);
    expect(policy.subagentTemperature, 0.2);
  });

  test('keeps agentic requests non-greedy when chat temperature is zero', () {
    final policy = LlmRequestTemperaturePolicy.forSettings(
      settingsWithTemperature(0.0),
    );

    expect(policy.chatTemperature, 0.0);
    expect(policy.toolLoopTemperature, greaterThan(0.0));
  });
}
