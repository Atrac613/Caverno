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

  test('preserves user-configured request-class temperatures', () {
    const service = LlmSamplerRuntimeFeedbackService();
    final profile = profileWithMetadata({
      LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.toolLoop):
          '0.7',
      LlmSamplerPresetProfile.sourceKey(LlmSamplerRequestClass.toolLoop):
          LlmSamplerPresetProfile.userSource,
      LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
        LlmSamplerRequestClass.toolLoop,
      ): '1',
    });

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
      result.profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '0.7',
    );
    expect(
      result.profile.probeMetadata[LlmSamplerPresetProfile.sourceKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      LlmSamplerPresetProfile.userSource,
    );
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '2',
    );
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.previousTemperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      isNull,
    );
  });

  test('preserves user-configured agentic fallback temperatures', () {
    const service = LlmSamplerRuntimeFeedbackService();
    final profile = profileWithMetadata({
      LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.agentic):
          '0.7',
      LlmSamplerPresetProfile.sourceKey(LlmSamplerRequestClass.agentic):
          LlmSamplerPresetProfile.userSource,
      LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
        LlmSamplerRequestClass.toolLoop,
      ): '1',
    });

    final result = service.recordSignal(
      profile: profile,
      signal: const LlmSamplerRuntimeFeedbackSignal(
        requestClass: LlmSamplerRequestClass.toolLoop,
        malformedToolCallCount: 1,
      ),
    );

    expect(result, isNotNull);
    expect(result!.temperatureAdjusted, isFalse);
    expect(
      result.profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.agentic,
      )],
      '0.7',
    );
    expect(
      result.profile.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      isNull,
    );
    expect(
      result
          .profile
          .probeMetadata[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '2',
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

  group('recoverAfterReprobe', () {
    Map<String, String> steppedDownMetadata({
      double probedTemp = 0.4,
      double steppedTemp = 0.2,
      LlmSamplerRequestClass requestClass = LlmSamplerRequestClass.toolLoop,
    }) {
      return {
        LlmSamplerPresetProfile.temperatureKey(requestClass):
            steppedTemp.toString(),
        LlmSamplerPresetProfile.sourceKey(requestClass):
            LlmSamplerRuntimeFeedbackService.runtimeSource,
        LlmSamplerRuntimeFeedbackService.previousTemperatureKey(requestClass):
            probedTemp.toString(),
        LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
          requestClass,
        ): '2',
        LlmSamplerRuntimeFeedbackService.adjustmentCountKey(requestClass): '1',
        LlmSamplerRuntimeFeedbackService.lastAdjustmentReasonKey(
          requestClass,
        ): 'malformedToolCall',
      };
    }

    test('idle_re_probe restores stepped-down temperature and clears counters',
        () {
      const service = LlmSamplerRuntimeFeedbackService();
      final profile = profileWithMetadata(steppedDownMetadata());
      final recovered = service.recoverAfterReprobe(
        profile: profile,
        probeSource: 'idle_re_probe',
      );

      final meta = recovered.probeMetadata;
      expect(
        meta[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        '0.4',
      );
      expect(
        meta[LlmSamplerPresetProfile.sourceKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        LlmSamplerPresetProfile.probeSource,
      );
      expect(
        meta[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        isNull,
      );
      expect(
        meta[LlmSamplerRuntimeFeedbackService.previousTemperatureKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        isNull,
      );
      expect(
        meta[LlmSamplerRuntimeFeedbackService.adjustmentCountKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        isNull,
      );
    });

    test('idle_re_probe is no-op when source is not runtimeFeedback', () {
      const service = LlmSamplerRuntimeFeedbackService();
      final meta = {
        LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.toolLoop):
            '0.4',
        LlmSamplerPresetProfile.sourceKey(LlmSamplerRequestClass.toolLoop):
            LlmSamplerPresetProfile.probeSource,
      };
      final profile = profileWithMetadata(meta);
      final recovered = service.recoverAfterReprobe(
        profile: profile,
        probeSource: 'idle_re_probe',
      );

      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        '0.4',
      );
      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.sourceKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        LlmSamplerPresetProfile.probeSource,
      );
    });

    test('calibrate clears counters without restoring previous temperature', () {
      const service = LlmSamplerRuntimeFeedbackService();
      // After calibration, the new temperature (0.35) is already written.
      final meta = {
        ...steppedDownMetadata(steppedTemp: 0.35),
      };
      final profile = profileWithMetadata(meta);
      final recovered = service.recoverAfterReprobe(
        profile: profile,
        probeSource: 'calibrate',
      );

      // Temperature must stay at 0.35 (calibration result); not restored to 0.4.
      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        '0.35',
      );
      // Runtime counters cleared.
      expect(
        recovered.probeMetadata[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        isNull,
      );
      expect(
        recovered.probeMetadata[LlmSamplerRuntimeFeedbackService.previousTemperatureKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        isNull,
      );
    });

    test('user-configured temperature is never restored or touched', () {
      const service = LlmSamplerRuntimeFeedbackService();
      final meta = {
        LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.toolLoop):
            '0.9',
        LlmSamplerPresetProfile.sourceKey(LlmSamplerRequestClass.toolLoop):
            LlmSamplerPresetProfile.userSource,
        LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
          LlmSamplerRequestClass.toolLoop,
        ): '3',
      };
      final profile = profileWithMetadata(meta);
      final recovered = service.recoverAfterReprobe(
        profile: profile,
        probeSource: 'idle_re_probe',
      );

      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        '0.9',
      );
      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.sourceKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        LlmSamplerPresetProfile.userSource,
      );
      // Counters are still cleared even for user-configured classes.
      expect(
        recovered.probeMetadata[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        isNull,
      );
    });

    test('handles multiple request classes independently', () {
      const service = LlmSamplerRuntimeFeedbackService();
      final meta = {
        // toolLoop: stepped down by runtime feedback
        ...steppedDownMetadata(
          requestClass: LlmSamplerRequestClass.toolLoop,
          probedTemp: 0.4,
          steppedTemp: 0.2,
        ),
        // coding: user-configured, should not be touched
        LlmSamplerPresetProfile.temperatureKey(LlmSamplerRequestClass.coding):
            '0.6',
        LlmSamplerPresetProfile.sourceKey(LlmSamplerRequestClass.coding):
            LlmSamplerPresetProfile.userSource,
      };
      final profile = profileWithMetadata(meta);
      final recovered = service.recoverAfterReprobe(
        profile: profile,
        probeSource: 'idle_re_probe',
      );

      // toolLoop restored
      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        '0.4',
      );
      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.sourceKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        LlmSamplerPresetProfile.probeSource,
      );
      // coding unchanged in temperature and source
      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.temperatureKey(
          LlmSamplerRequestClass.coding,
        )],
        '0.6',
      );
      expect(
        recovered.probeMetadata[LlmSamplerPresetProfile.sourceKey(
          LlmSamplerRequestClass.coding,
        )],
        LlmSamplerPresetProfile.userSource,
      );
    });
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
