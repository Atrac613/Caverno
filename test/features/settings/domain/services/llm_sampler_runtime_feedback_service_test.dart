import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_runtime_feedback_service.dart';

void main() {
  ModelCapabilityProfile profileWithMetadata(Map<String, String> metadata) {
    final defaults = AppSettings.defaults();
    return ModelCapabilityProfile(
      id: '',
      baseUrl: defaults.baseUrl,
      model: defaults.effectiveModel,
      probeMetadata: metadata,
    ).normalizedForPersistence();
  }

  test('records runtime counters before the adjustment threshold', () {
    const service = LlmSamplerRuntimeFeedbackService();
    final profile = profileWithMetadata(
      LlmSamplerPresetProfile.withTemperature(
        metadata: const {},
        requestClass: LlmSamplerRequestClass.toolLoop,
        temperature: 0.4,
      ),
    );

    final result = service.recordSignal(
      profile: profile,
      signal: const LlmSamplerRuntimeFeedbackSignal(
        requestClass: LlmSamplerRequestClass.toolLoop,
        malformedToolCallCount: 1,
      ),
      observedAt: DateTime.utc(2026, 6, 14, 1, 2, 3),
    );

    expect(result, isNotNull);
    expect(result!.temperatureAdjusted, isFalse);
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '1',
    );
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.lastObservedAtKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '2026-06-14T01:02:03.000Z',
    );
    expect(
      result.profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.4',
    );
  });

  test('steps down request-class temperature after runtime failures', () {
    const service = LlmSamplerRuntimeFeedbackService();
    final profile = profileWithMetadata(
      LlmSamplerPresetProfile.withTemperature(
        metadata: {
          LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
            LlmSamplerRequestClass.toolLoop,
          ): '1',
        },
        requestClass: LlmSamplerRequestClass.toolLoop,
        temperature: 0.4,
      ),
    );

    final result = service.recordSignal(
      profile: profile,
      signal: const LlmSamplerRuntimeFeedbackSignal(
        requestClass: LlmSamplerRequestClass.toolLoop,
        malformedToolCallCount: 1,
      ),
      observedAt: DateTime.utc(2026, 6, 14, 1, 2, 3),
    );

    expect(result, isNotNull);
    expect(result!.temperatureAdjusted, isTrue);
    expect(result.previousTemperature, 0.4);
    expect(result.adjustedTemperature, 0.2);
    expect(
      result.profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.2',
    );
    expect(
      result.profile.probeMetadata[LlmSamplerPresetProfile.sourceKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      LlmSamplerRuntimeFeedbackService.runtimeSource,
    );
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.previousTemperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.4',
    );
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.lastAdjustmentReasonKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      'malformedToolCall',
    );
  });

  test('lowers immediately on repetition but never below the floor', () {
    const service = LlmSamplerRuntimeFeedbackService();
    final profile = profileWithMetadata(
      LlmSamplerPresetProfile.withTemperature(
        metadata: const {},
        requestClass: LlmSamplerRequestClass.toolLoop,
        temperature: 0.1,
      ),
    );

    final result = service.recordSignal(
      profile: profile,
      signal: const LlmSamplerRuntimeFeedbackSignal(
        requestClass: LlmSamplerRequestClass.toolLoop,
        repetitionDetected: true,
      ),
    );

    expect(result, isNotNull);
    expect(result!.temperatureAdjusted, isFalse);
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.repetitionCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '1',
    );
    expect(
      result.profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.1',
    );
  });

  test('classifies malformed tool-call style failures', () {
    expect(
      LlmSamplerRuntimeFeedbackService.looksLikeMalformedToolCallFailure(
        'No matching tool available: write_fil',
      ),
      isTrue,
    );
    expect(
      LlmSamplerRuntimeFeedbackService.looksLikeMalformedToolCallFailure(
        'path and pattern are required',
      ),
      isTrue,
    );
    expect(
      LlmSamplerRuntimeFeedbackService.looksLikeMalformedToolCallFailure(
        'Process exited with code 1',
      ),
      isFalse,
    );
    expect(
      LlmSamplerRuntimeFeedbackService.looksLikeMalformedToolCallFailure(
        '{"code":"git_tag_format_inspection_required","required_action":"Run tag --list first"}',
      ),
      isFalse,
    );
  });
}
