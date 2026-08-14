import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/live_llm_benchmark_artifact_importer.dart';

void main() {
  test('imports a focused ladder run without manufacturing a zero score', () {
    final existing = ModelCapabilityProfile(
      id: '',
      baseUrl: 'http://localhost:1234/v1',
      model: 'local-model',
      toolCallStyle: ModelToolCallStyle.nativeToolCalls,
      structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
      probedAt: DateTime.parse('2026-08-14T08:00:00Z'),
      probeMetadata: const {
        'benchmarkSuite': 'cavernobench-v8',
        'benchmarkPoints': '970',
        'benchmarkAttemptedPoints': '970',
        'benchmarkMaxPoints': '1000',
      },
    );

    final profile = LiveLlmBenchmarkArtifactImporter.importProfile(
      _artifact(attemptedPoints: 0, earnedPoints: 0),
      existingProfiles: [existing],
    );

    expect(profile.toolCallStyle, ModelToolCallStyle.nativeToolCalls);
    expect(
      profile.structuredOutputSupport,
      ModelStructuredOutputSupport.jsonSchema,
    );
    expect(profile.probeMetadata['benchmarkPoints'], '970');
    expect(profile.probeMetadata['difficultyLadder'], 'ladder-v2');
    expect(
      profile.probeMetadata['difficultyLadderMeasuredPromptTokens'],
      '16498',
    );
    expect(profile.usableContextTokens, 16498);
    expect(
      profile.probeMetadata['capability.effectiveContext.promptTokens'],
      '16498',
    );
  });

  test(
    'imports bounded evidence when the run attempted conformance points',
    () {
      final profile = LiveLlmBenchmarkArtifactImporter.importProfile(
        _artifact(attemptedPoints: 955, earnedPoints: 950),
      );

      expect(profile.provider, LlmProvider.openAiCompatible);
      expect(profile.probeMetadata['benchmarkSuite'], 'cavernobench-v9');
      expect(profile.probeMetadata['benchmarkPoints'], '950');
      expect(profile.probeMetadata['benchmarkAttemptedPoints'], '955');
      expect(profile.probeMetadata['benchmarkMaxPoints'], '1000');
    },
  );

  test('accepts a legacy artifact without an explicit provider', () {
    final artifact = _artifact(attemptedPoints: 0, earnedPoints: 0)
      ..remove('provider');

    final profile = LiveLlmBenchmarkArtifactImporter.importProfile(artifact);

    expect(profile.provider, LlmProvider.openAiCompatible);
  });

  test('accepts legacy ladder-v1 evidence after the prompt contract bump', () {
    final profile = LiveLlmBenchmarkArtifactImporter.importProfile(
      _artifact(attemptedPoints: 0, earnedPoints: 0, ladderVersion: 1),
    );

    expect(profile.probeMetadata['difficultyLadder'], 'ladder-v1');
    expect(profile.usableContextTokens, 16498);
  });

  test('rejects an artifact older than the stored profile', () {
    final existing = ModelCapabilityProfile(
      id: '',
      baseUrl: 'http://localhost:1234/v1',
      model: 'local-model',
      probedAt: DateTime.parse('2026-08-15T00:00:00Z'),
    );

    expect(
      () => LiveLlmBenchmarkArtifactImporter.importProfile(
        _artifact(attemptedPoints: 0, earnedPoints: 0),
        existingProfiles: [existing],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('older'),
        ),
      ),
    );
  });

  test('rejects a focused run without measured capability evidence', () {
    final artifact = _artifact(attemptedPoints: 0, earnedPoints: 0);
    final run = (artifact['runs'] as List).single as Map<String, dynamic>;
    run['difficultyLadder'] = {
      ...(run['difficultyLadder'] as Map<String, dynamic>),
      'measured': false,
      'measuredPromptTokens': 0,
    };
    run.remove('effectiveContext');

    expect(
      () => LiveLlmBenchmarkArtifactImporter.importProfile(artifact),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('no measured score or ladder evidence'),
        ),
      ),
    );
  });

  test('rejects internally inconsistent ladder stages', () {
    final artifact = _artifact(attemptedPoints: 0, earnedPoints: 0);
    final run = (artifact['runs'] as List).single as Map<String, dynamic>;
    run['difficultyLadder'] = {
      ...(run['difficultyLadder'] as Map<String, dynamic>),
      'highestPassedStagePromptTokens': 32768,
    };

    expect(
      () => LiveLlmBenchmarkArtifactImporter.importProfile(artifact),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, dynamic> _artifact({
  required int attemptedPoints,
  required int earnedPoints,
  int ladderVersion = 2,
}) => {
  'schema': LiveLlmBenchmarkArtifactImporter.schema,
  'generatedAt': '2026-08-14T09:00:00Z',
  'suiteId': 'cavernobench',
  'suiteVersion': 9,
  'provider': 'openAiCompatible',
  'baseUrl': 'http://localhost:1234/v1',
  'model': 'local-model',
  'runs': [
    {
      'finishedAt': '2026-08-14T08:54:00Z',
      'baseUrl': 'http://localhost:1234/v1',
      'model': 'local-model',
      'benchmark': {
        'suiteId': 'cavernobench',
        'suiteVersion': 9,
        'earnedPoints': earnedPoints,
        'attemptedPoints': attemptedPoints,
        'maxPoints': 1000,
      },
      'difficultyLadder': {
        'suiteId': 'ladder',
        'suiteVersion': ladderVersion,
        'suite': 'ladder-v$ladderVersion',
        'axis': 'effective_context_recall',
        'unit': 'prompt_tokens',
        'measured': true,
        'measuredPromptTokens': 16498,
        'highestPassedStagePromptTokens': 16384,
        'nextStagePromptTokens': 32768,
        'passedStageCount': 3,
        'stageCount': 6,
      },
      'effectiveContext': {
        'configuredMaximumTokens': 65536,
        'maxSuccessfulPromptTokens': 16498,
        'reachedConfiguredMaximum': false,
      },
    },
  ],
};
