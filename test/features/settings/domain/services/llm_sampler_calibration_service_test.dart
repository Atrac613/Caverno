import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_calibration_service.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';

void main() {
  const service = LlmSamplerCalibrationService();

  test('selects the best adjusted sampler temperature', () {
    final selection = service.selectTemperature(
      requestClass: LlmSamplerRequestClass.toolLoop,
      trials: const [
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.toolLoop,
          temperature: 0.7,
          passed: true,
          jsonRepairEventCount: 2,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.toolLoop,
          temperature: 0.7,
          passed: false,
          malformedToolCallCount: 1,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.toolLoop,
          temperature: 0.2,
          passed: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.toolLoop,
          temperature: 0.2,
          passed: true,
        ),
      ],
    );

    expect(selection, isNotNull);
    expect(selection!.temperature, 0.2);
    expect(selection.trialCount, 2);
    expect(selection.successCount, 2);
    expect(selection.score, 1.0);
  });

  test('avoids greedy temperatures when probes detect repetition', () {
    final selection = service.selectTemperature(
      requestClass: LlmSamplerRequestClass.agentic,
      trials: const [
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.agentic,
          temperature: 0.0,
          passed: true,
          repetitionDetected: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.agentic,
          temperature: 0.0,
          passed: true,
          repetitionDetected: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.agentic,
          temperature: 0.2,
          passed: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.agentic,
          temperature: 0.2,
          passed: false,
        ),
      ],
    );

    expect(selection, isNotNull);
    expect(selection!.temperature, 0.2);
    expect(selection.repetitionCount, 0);
  });

  test('prefers the managed nonzero default when scores tie', () {
    final selection = service.selectTemperature(
      requestClass: LlmSamplerRequestClass.coding,
      trials: const [
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.coding,
          temperature: 0.0,
          passed: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.coding,
          temperature: 0.2,
          passed: true,
        ),
      ],
    );

    expect(selection, isNotNull);
    expect(selection!.temperature, 0.2);
  });

  test('ignores invalid and unrelated trials', () {
    final selection = service.selectTemperature(
      requestClass: LlmSamplerRequestClass.routine,
      trials: const [
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.routine,
          temperature: -0.1,
          passed: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.routine,
          temperature: 2.1,
          passed: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.subagent,
          temperature: 0.2,
          passed: true,
        ),
      ],
    );

    expect(selection, isNull);
  });

  test('applies selected sampler metadata to a model profile', () {
    final profile = ModelCapabilityProfile(
      id: '',
      baseUrl: 'HTTP://LOCALHOST:1234/v1',
      model: ' qwen-test ',
      probeMetadata: const {'probe.instruction_echo.status': 'passed'},
    );
    final selection = const LlmSamplerCalibrationSelection(
      requestClass: LlmSamplerRequestClass.toolLoop,
      temperature: 0.2,
      score: 0.96,
      trialCount: 4,
      successCount: 4,
      repetitionCount: 0,
    );

    final updated = service.applySelectionToProfile(
      profile: profile,
      selection: selection,
    );

    expect(updated.baseUrl, 'HTTP://LOCALHOST:1234/v1');
    expect(updated.model, 'qwen-test');
    expect(updated.probeMetadata['probe.instruction_echo.status'], 'passed');
    expect(
      updated.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.2',
    );
    expect(
      updated.probeMetadata[LlmSamplerPresetProfile.scoreKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.960',
    );
    expect(
      updated.probeMetadata[LlmSamplerPresetProfile.trialCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '4',
    );
    expect(
      updated.probeMetadata[LlmSamplerPresetProfile.sourceKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      'probe',
    );
  });
}
