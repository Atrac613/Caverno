import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/llm_request_temperature_policy.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';

void main() {
  AppSettings settingsWithTemperature(double temperature) {
    return AppSettings.defaults().copyWith(temperature: temperature);
  }

  AppSettings settingsWithSamplerMetadata(Map<String, String> metadata) {
    final defaults = AppSettings.defaults();
    final profile = ModelCapabilityProfile(
      id: '',
      baseUrl: defaults.baseUrl,
      model: defaults.effectiveModel,
      probeMetadata: metadata,
    ).normalizedForPersistence();
    return defaults.copyWith(
      temperature: 1.7,
      modelCapabilityProfiles: [profile],
    );
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

  test('uses profile sampler presets without overriding chat prose', () {
    final policy = LlmRequestTemperaturePolicy.forSettings(
      settingsWithSamplerMetadata(
        LlmSamplerPresetProfile.withTemperature(
          metadata: const {},
          requestClass: LlmSamplerRequestClass.agentic,
          temperature: 0.4,
        ),
      ),
    );

    expect(policy.temperatureForAssistantMode(AssistantMode.general), 1.7);
    expect(policy.temperatureForAssistantMode(AssistantMode.coding), 0.4);
    expect(policy.temperatureForAssistantMode(AssistantMode.plan), 0.4);
    expect(policy.toolLoopTemperature, 0.4);
    expect(policy.routineTemperature, 0.4);
    expect(policy.subagentTemperature, 0.4);
  });

  test(
    'lets role-specific profile sampler presets override agentic fallback',
    () {
      final metadata = LlmSamplerPresetProfile.withTemperature(
        metadata: LlmSamplerPresetProfile.withTemperature(
          metadata: LlmSamplerPresetProfile.withTemperature(
            metadata: const {},
            requestClass: LlmSamplerRequestClass.agentic,
            temperature: 0.3,
          ),
          requestClass: LlmSamplerRequestClass.toolLoop,
          temperature: 0.2,
        ),
        requestClass: LlmSamplerRequestClass.routine,
        temperature: 0.5,
      );
      final policy = LlmRequestTemperaturePolicy.forSettings(
        settingsWithSamplerMetadata(metadata),
      );

      expect(policy.toolLoopTemperature, 0.2);
      expect(policy.routineTemperature, 0.5);
      expect(policy.subagentTemperature, 0.3);
      expect(policy.temperatureForAssistantMode(AssistantMode.coding), 0.3);
    },
  );

  test('ignores invalid sampler presets and keeps zero presets non-greedy', () {
    final policy = LlmRequestTemperaturePolicy.forSettings(
      settingsWithSamplerMetadata({
        LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.agentic):
            'invalid',
        LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.toolLoop):
            '0.0',
        LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.routine):
            '7.0',
      }),
    );

    expect(policy.agenticTemperature, 0.2);
    expect(policy.toolLoopTemperature, 0.1);
    expect(policy.routineTemperature, 0.2);
  });
}
