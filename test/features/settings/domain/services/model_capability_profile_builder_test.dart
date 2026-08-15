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
          id: 'structured_output',
          status: LiveLlmDiagnosticStatus.warning,
          summary: 'JSON object mode worked.',
          metadata: {'structuredOutputSupport': 'jsonObject'},
        ),
        LiveLlmDiagnosticProbeResult(
          id: 'narrow_tool_call',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'Tool call ok.',
          toolCalls: ['get_current_datetime'],
        ),
        LiveLlmDiagnosticProbeResult(
          id: 'update_goal_fidelity',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'Goal update ok.',
          toolCalls: ['update_goal'],
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
    expect(profile.goalUpdateFidelity, ModelGoalUpdateFidelity.reliable);
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
      ModelStructuredOutputSupport.unknown,
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
    expect(profile.goalUpdateFidelity, ModelGoalUpdateFidelity.unknown);
  });

  for (final preference in ModelEditFormatPreference.values) {
    test('maps ${preference.name} edit-format probe evidence', () {
      final measured = preference != ModelEditFormatPreference.unknown;
      final report = LiveLlmDiagnosticReport(
        startedAt: DateTime.utc(2026, 8, 13),
        baseUrl: 'http://localhost:1234/v1',
        model: 'edit-model',
        demoMode: false,
        mcpEnabled: false,
        results: [
          LiveLlmDiagnosticProbeResult(
            id: 'edit_format_fidelity',
            status: measured
                ? LiveLlmDiagnosticStatus.warning
                : LiveLlmDiagnosticStatus.failed,
            summary: 'Edit format result.',
            metadata: {'editFormatPreference': preference.name},
          ),
        ],
      );

      final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
      );

      expect(profile.editFormatPreference, preference);
    });
  }

  for (final support in ModelStructuredOutputSupport.values) {
    test('maps ${support.name} structured-output probe evidence', () {
      final report = LiveLlmDiagnosticReport(
        startedAt: DateTime.utc(2026, 8, 13),
        baseUrl: 'http://localhost:1234/v1',
        model: 'structured-model',
        demoMode: false,
        mcpEnabled: false,
        results: [
          LiveLlmDiagnosticProbeResult(
            id: 'structured_output',
            status: support == ModelStructuredOutputSupport.unknown
                ? LiveLlmDiagnosticStatus.skipped
                : LiveLlmDiagnosticStatus.warning,
            summary: 'Structured output result.',
            metadata: {'structuredOutputSupport': support.name},
          ),
        ],
      );

      final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
      );

      expect(profile.structuredOutputSupport, support);
    });
  }

  test('rejects unknown edit-format metadata values', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 13),
      baseUrl: 'http://localhost:1234/v1',
      model: 'edit-model',
      demoMode: false,
      mcpEnabled: false,
      results: const [
        LiveLlmDiagnosticProbeResult(
          id: 'edit_format_fidelity',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'Edit format result.',
          metadata: {'editFormatPreference': 'futureFormat'},
        ),
      ],
    );

    expect(
      ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
      ).editFormatPreference,
      ModelEditFormatPreference.unknown,
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

  test('stores report sampler trials in profile metadata', () {
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
      samplerCalibrationTrials: const [
        LiveLlmDiagnosticSamplerTrial(
          requestClass: 'toolLoop',
          temperature: 0.0,
          passed: true,
          repetitionDetected: true,
        ),
        LiveLlmDiagnosticSamplerTrial(
          requestClass: 'toolLoop',
          temperature: 0.2,
          passed: true,
        ),
        LiveLlmDiagnosticSamplerTrial(
          requestClass: 'unknown',
          temperature: 0.1,
          passed: true,
        ),
      ],
    );

    final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
      report: report,
      provider: LlmProvider.openAiCompatible,
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
        LlmSamplerRequestClass.agentic,
      )],
      isNull,
    );
    expect(profile.probeMetadata['probe.instruction_echo.status'], 'passed');
  });

  test('persists the endpoint-reported context window', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 7, 25),
      finishedAt: DateTime.utc(2026, 7, 25, 0, 0, 2),
      baseUrl: 'http://localhost:1234/v1',
      model: 'qwen-test',
      demoMode: false,
      mcpEnabled: false,
      toolCatalog: const LiveLlmDiagnosticToolCatalog(),
      results: const [],
    );

    expect(
      ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
        usableContextTokens: 32768,
      ).usableContextTokens,
      32768,
    );
    expect(
      ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
        report: report,
        provider: LlmProvider.openAiCompatible,
      ).usableContextTokens,
      0,
      reason: 'an endpoint that advertises no context window stays unmeasured',
    );
  });

  test('prefers measured effective context over the advertised window', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 14),
      baseUrl: 'http://localhost:1234/v1',
      model: 'context-model',
      demoMode: false,
      mcpEnabled: false,
      effectiveContextMetrics: const LiveLlmDiagnosticEffectiveContextMetrics(
        configuredMaximumTokens: 16384,
        trials: [
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: 8192,
            elapsed: Duration(milliseconds: 50),
            passed: true,
            promptTokens: 8320,
          ),
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: 16384,
            elapsed: Duration(milliseconds: 90),
            passed: false,
            failure: 'context overflow',
          ),
        ],
      ),
    );

    final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
      report: report,
      provider: LlmProvider.openAiCompatible,
      usableContextTokens: 32768,
    );

    expect(profile.usableContextTokens, 8320);
    expect(
      profile.probeMetadata['effectiveContext.maxSuccessfulPromptTokens'],
      '8320',
    );
    expect(
      profile.probeMetadata['effectiveContext.reachedConfiguredMaximum'],
      'false',
    );
    expect(profile.probeMetadata['difficultyLadder'], 'ladder-v2');
    expect(
      profile.probeMetadata['difficultyLadderAxis'],
      'effective_context_recall',
    );
    expect(
      profile.probeMetadata['difficultyLadderMeasuredPromptTokens'],
      '8320',
    );
    expect(
      profile.probeMetadata['difficultyLadderHighestStagePromptTokens'],
      '8192',
    );
    expect(
      profile.probeMetadata['difficultyLadderNextStagePromptTokens'],
      '16384',
    );
    expect(
      profile.probeMetadata['capability.effectiveContext.promptTokens'],
      '8320',
    );
  });

  test('an unclimbed ladder records no measurement', () {
    // The ladder is opt-in, so most runs never climb a stage. Writing its zero
    // made "not measured" look like "recalls nothing", and every model then
    // compared equal at 0 tok.
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 15),
      baseUrl: 'http://localhost:1234/v1',
      model: 'context-model',
      demoMode: false,
      mcpEnabled: false,
      results: const [
        LiveLlmDiagnosticProbeResult(
          id: 'effective_context',
          status: LiveLlmDiagnosticStatus.skipped,
          summary: 'skipped',
        ),
      ],
    );

    final profile = ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
      report: report,
      provider: LlmProvider.openAiCompatible,
      usableContextTokens: 32768,
    );

    expect(profile.probeMetadata['difficultyLadder'], 'ladder-v2');
    expect(
      profile.probeMetadata.containsKey('difficultyLadderMeasuredPromptTokens'),
      isFalse,
    );
    expect(
      profile.probeMetadata.containsKey(
        'difficultyLadderHighestStagePromptTokens',
      ),
      isFalse,
    );
    expect(
      profile.probeMetadata.containsKey(
        'capability.effectiveContext.promptTokens',
      ),
      isFalse,
    );
  });
}
