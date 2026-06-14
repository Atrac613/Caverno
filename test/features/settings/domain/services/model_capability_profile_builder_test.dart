import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_calibration_service.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';
import 'package:caverno/features/settings/domain/services/model_capability_profile_builder.dart';

void main() {
  test('builds a profile from a successful OpenAI-compatible diagnostic', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 6, 12),
      finishedAt: DateTime.utc(2026, 6, 12, 0, 0, 3),
      baseUrl: 'HTTP://LOCALHOST:1234/v1',
      model: 'qwen-test',
      demoMode: false,
      mcpEnabled: true,
      toolCatalog: const LiveLlmDiagnosticToolCatalog(
        totalToolCount: 42,
        toolSearchEnabled: true,
      ),
      results: const [
        LiveLlmDiagnosticProbeResult(
          id: 'instruction_echo',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'JSON ok.',
        ),
        LiveLlmDiagnosticProbeResult(
          id: 'narrow_tool_call',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'Tool call ok.',
          toolCalls: ['get_current_datetime'],
        ),
      ],
    );

    final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
      report: report,
      provider: LlmProvider.openAiCompatible,
    );

    expect(profile.id, contains('openAiCompatible|http://localhost:1234/v1'));
    expect(profile.toolCallStyle, ModelToolCallStyle.nativeToolCalls);
    expect(
      profile.structuredOutputSupport,
      ModelStructuredOutputSupport.jsonObject,
    );
    expect(profile.editFormatPreference, ModelEditFormatPreference.unknown);
    expect(profile.probedAt, DateTime.utc(2026, 6, 12, 0, 0, 3));
    expect(profile.probeMetadata['probe.instruction_echo.status'], 'passed');
    expect(profile.probeMetadata['toolSearchEnabled'], 'true');
  });

  test('uses embedded tool style for Foundation Models diagnostics', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 6, 12),
      baseUrl: 'apple-foundation-models://local',
      model: AppSettings.appleFoundationModelsModelId,
      demoMode: false,
      mcpEnabled: true,
      results: const [
        LiveLlmDiagnosticProbeResult(
          id: 'instruction_echo',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'JSON ok.',
        ),
        LiveLlmDiagnosticProbeResult(
          id: 'narrow_tool_call',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'Tool bridge ok.',
          toolCalls: ['get_current_datetime'],
        ),
      ],
    );

    final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
      report: report,
      provider: LlmProvider.appleFoundationModels,
    );

    expect(profile.toolCallStyle, ModelToolCallStyle.embeddedToolTags);
    expect(
      profile.structuredOutputSupport,
      ModelStructuredOutputSupport.jsonObject,
    );
  });

  test('keeps unknown capabilities for skipped probes', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 6, 12),
      baseUrl: 'http://localhost:1234/v1',
      model: 'weak-model',
      demoMode: false,
      mcpEnabled: false,
      results: const [
        LiveLlmDiagnosticProbeResult(
          id: 'instruction_echo',
          status: LiveLlmDiagnosticStatus.warning,
          summary: 'Marker present but not exact.',
        ),
        LiveLlmDiagnosticProbeResult(
          id: 'narrow_tool_call',
          status: LiveLlmDiagnosticStatus.skipped,
          summary: 'Tools disabled.',
        ),
      ],
    );

    final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
      report: report,
      provider: LlmProvider.openAiCompatible,
    );

    expect(profile.toolCallStyle, ModelToolCallStyle.unknown);
    expect(
      profile.structuredOutputSupport,
      ModelStructuredOutputSupport.unknown,
    );
  });

  test('stores sampler calibration selections in profile metadata', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 6, 12),
      finishedAt: DateTime.utc(2026, 6, 12, 0, 0, 3),
      baseUrl: 'http://localhost:1234/v1',
      model: 'sampler-model',
      demoMode: false,
      mcpEnabled: true,
      results: const [
        LiveLlmDiagnosticProbeResult(
          id: 'instruction_echo',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'JSON ok.',
        ),
      ],
    );

    final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
      report: report,
      provider: LlmProvider.openAiCompatible,
      samplerTrials: const [
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.toolLoop,
          temperature: 0.0,
          passed: true,
          repetitionDetected: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.toolLoop,
          temperature: 0.2,
          passed: true,
        ),
        LlmSamplerCalibrationTrial(
          requestClass: LlmSamplerRequestClass.routine,
          temperature: 0.4,
          passed: true,
        ),
      ],
    );

    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.2',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.scoreKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '1.000',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.trialCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '1',
    );
    expect(
      profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.routine,
      )],
      '0.4',
    );
    expect(profile.probeMetadata['probe.instruction_echo.status'], 'passed');
  });
}
