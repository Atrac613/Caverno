import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/model_capability_comparison.dart';

void main() {
  test('orders higher-is-better and lower-is-better axes independently', () {
    final results = ModelCapabilityComparison.evaluate([
      _profile(
        'model-a',
        contextTokens: '16384',
        decodeRate: '30',
        ttftMs: '800',
        turns: '3',
        totalTokens: '3000',
      ),
      _profile(
        'model-b',
        contextTokens: '32768',
        decodeRate: '20',
        ttftMs: '500',
        turns: '2',
        totalTokens: '2500',
      ),
    ]);

    expect(_axis(results, 'effective-context').samples.first.model, 'model-b');
    expect(_axis(results, 'decode-rate').samples.first.model, 'model-a');
    expect(_axis(results, 'ttft').samples.first.model, 'model-b');
    expect(_axis(results, 'tool-loop-turns').samples.first.model, 'model-b');
    expect(_axis(results, 'tool-loop-tokens').samples.first.model, 'model-b');
  });

  test('keeps equal best measurements tied', () {
    final result = _axis(
      ModelCapabilityComparison.evaluate([
        _profile('model-a', decodeRate: '42.5'),
        _profile('model-b', decodeRate: '42.5'),
        _profile('model-c', decodeRate: '30'),
      ]),
      'decode-rate',
    );

    expect(result.bestProfileIds, hasLength(2));
    expect(
      result.samples
          .where((sample) => result.bestProfileIds.contains(sample.profileId))
          .map((sample) => sample.model),
      containsAll(['model-a', 'model-b']),
    );
  });

  test(
    'omits missing invalid and non-finite values instead of ranking zero',
    () {
      final result = _axis(
        ModelCapabilityComparison.evaluate([
          _profile('valid', ttftMs: '500'),
          _profile('missing'),
          _profile('negative', ttftMs: '-1'),
          _profile('nan', ttftMs: 'NaN'),
        ]),
        'ttft',
      );

      expect(result.samples.map((sample) => sample.model), ['valid']);
      expect(result.isComparable, isFalse);
    },
  );

  test('uses legacy ladder measurement for effective-context comparison', () {
    final result = _axis(
      ModelCapabilityComparison.evaluate([
        _profile('new', contextTokens: '32768'),
        _profile(
          'legacy',
          extra: const {
            'difficultyLadderAxis': 'effective_context_recall',
            'difficultyLadderMeasuredPromptTokens': '16498',
          },
        ),
      ]),
      'effective-context',
    );

    expect(result.samples.map((sample) => sample.model), ['new', 'legacy']);
  });

  test('uses the latest duplicate profile identity', () {
    final result = _axis(
      ModelCapabilityComparison.evaluate([
        _profile('same-model', ttftMs: '900'),
        _profile('same-model', ttftMs: '400'),
        _profile('other-model', ttftMs: '500'),
      ]),
      'ttft',
    );

    expect(result.samples, hasLength(2));
    expect(result.samples.first.model, 'same-model');
    expect(result.samples.first.value, 400);
  });
}

ModelCapabilityComparisonResult _axis(
  List<ModelCapabilityComparisonResult> results,
  String id,
) => results.singleWhere((result) => result.axis.id == id);

ModelCapabilityProfile _profile(
  String model, {
  String? contextTokens,
  String? decodeRate,
  String? ttftMs,
  String? turns,
  String? totalTokens,
  Map<String, String> extra = const {},
}) => ModelCapabilityProfile(
  id: '',
  baseUrl: 'http://localhost:1234/v1',
  model: model,
  probeMetadata: {
    'capability.effectiveContext.promptTokens': ?contextTokens,
    'capability.streaming.decodeTokensPerSecond': ?decodeRate,
    'capability.streaming.ttftMs': ?ttftMs,
    'capability.toolLoop.modelTurns': ?turns,
    'capability.toolLoop.totalTokens': ?totalTokens,
    ...extra,
  },
);
