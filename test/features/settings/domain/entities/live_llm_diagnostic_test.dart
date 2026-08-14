import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';

void main() {
  test('serializes effective-context trials in physical units', () {
    const metrics = LiveLlmDiagnosticEffectiveContextMetrics(
      configuredMaximumTokens: 8192,
      trials: [
        LiveLlmDiagnosticContextTrial(
          requestedApproximateTokens: 2048,
          elapsed: Duration(milliseconds: 20),
          passed: true,
          promptTokens: 2110,
        ),
        LiveLlmDiagnosticContextTrial(
          requestedApproximateTokens: 4096,
          elapsed: Duration(milliseconds: 45),
          passed: false,
          failure: 'context overflow',
          failureKind: 'request_error',
          finishReason: 'length',
          responsePreview: 'partial output',
        ),
      ],
    );
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 14),
      baseUrl: 'http://localhost:1234/v1',
      model: 'context-model',
      demoMode: false,
      mcpEnabled: false,
      effectiveContextMetrics: metrics,
    );

    expect(metrics.maxSuccessfulPromptTokens, 2110);
    expect(metrics.reachedConfiguredMaximum, isFalse);
    expect(metrics.firstFailedApproximateTokens, 4096);
    expect(report.toJson()['effectiveContext'], {
      'configuredMaximumTokens': 8192,
      'maxSuccessfulPromptTokens': 2110,
      'reachedConfiguredMaximum': false,
      'firstFailedApproximateTokens': 4096,
      'trials': [
        {
          'requestedApproximateTokens': 2048,
          'elapsedMs': 20,
          'passed': true,
          'promptTokens': 2110,
        },
        {
          'requestedApproximateTokens': 4096,
          'elapsedMs': 45,
          'passed': false,
          'failure': 'context overflow',
          'failureKind': 'request_error',
          'finishReason': 'length',
          'responsePreview': 'partial output',
        },
      ],
    });
  });

  test('serializes embeddings capability metrics in physical units', () {
    const metrics = LiveLlmDiagnosticEmbeddingMetrics(
      totalElapsed: Duration(milliseconds: 42),
      inputCount: 3,
      returnedVectorCount: 3,
      dimension: 2048,
      model: 'qwen-embedding',
      similarCosine: 0.91,
      unrelatedCosine: 0.22,
    );
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 13),
      baseUrl: 'http://localhost:1234/v1',
      model: 'chat-model',
      demoMode: false,
      mcpEnabled: false,
      embeddingMetrics: metrics,
    );

    expect(metrics.semanticMargin, closeTo(0.69, 1e-9));
    expect(report.toJson()['embeddings'], {
      'totalElapsedMs': 42,
      'inputCount': 3,
      'returnedVectorCount': 3,
      'dimension': 2048,
      'model': 'qwen-embedding',
      'similarCosine': 0.91,
      'unrelatedCosine': 0.22,
      'semanticMargin': 0.69,
    });
  });

  test('serializes machine-readable probe metadata', () {
    const result = LiveLlmDiagnosticProbeResult(
      id: 'edit_format_fidelity',
      status: LiveLlmDiagnosticStatus.warning,
      summary: 'One format passed.',
      passedChecks: 1,
      totalChecks: 3,
      metadata: {'editFormatPreference': 'wholeFile'},
    );

    expect(result.toJson()['metadata'], {'editFormatPreference': 'wholeFile'});
    expect(result.copyWith(status: LiveLlmDiagnosticStatus.passed).metadata, {
      'editFormatPreference': 'wholeFile',
    });
  });

  test('serializes completed multi-round tool-loop measurements', () {
    const metrics = LiveLlmDiagnosticMultiRoundToolLoopMetrics(
      totalElapsed: Duration(milliseconds: 1450),
      modelTurnCount: 3,
      toolCallCount: 2,
      successfulToolExecutionCount: 2,
      promptTokens: 420,
      completionTokens: 80,
      taskCompleted: true,
    );
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 11),
      baseUrl: 'http://localhost:1234/v1',
      model: 'tool-loop-model',
      demoMode: false,
      mcpEnabled: true,
      multiRoundToolLoopMetrics: metrics,
    );

    expect(metrics.totalTokens, 500);
    expect(report.toJson()['multiRoundToolLoop'], {
      'totalElapsedMs': 1450,
      'modelTurnCount': 3,
      'toolCallCount': 2,
      'successfulToolExecutionCount': 2,
      'promptTokens': 420,
      'completionTokens': 80,
      'totalTokens': 500,
      'taskCompleted': true,
    });
  });

  test('retains partial multi-round measurements after an early exit', () {
    const metrics = LiveLlmDiagnosticMultiRoundToolLoopMetrics(
      totalElapsed: Duration(milliseconds: 600),
      modelTurnCount: 2,
      toolCallCount: 1,
      successfulToolExecutionCount: 1,
      promptTokens: 220,
      completionTokens: 30,
      taskCompleted: false,
    );

    expect(metrics.toJson(), containsPair('taskCompleted', false));
    expect(metrics.toJson(), containsPair('modelTurnCount', 2));
    expect(metrics.toJson(), containsPair('totalTokens', 250));
  });

  test('omits unmeasured multi-round metrics from reports', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 11),
      baseUrl: 'http://localhost:1234/v1',
      model: 'unmeasured-model',
      demoMode: false,
      mcpEnabled: false,
    );

    expect(report.toJson(), isNot(contains('multiRoundToolLoop')));
  });

  test('serializes streaming capability metrics in physical units', () {
    final metrics = LiveLlmDiagnosticStreamingMetrics(
      timeToFirstToken: const Duration(milliseconds: 250),
      totalElapsed: const Duration(milliseconds: 2250),
      completionTokens: 100,
      chunkCount: 12,
      finishReason: 'stop',
    );
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 11),
      baseUrl: 'http://localhost:1234/v1',
      model: 'streaming-model',
      demoMode: false,
      mcpEnabled: false,
      streamingMetrics: metrics,
    );

    expect(metrics.decodeTokensPerSecond, 50);
    expect(report.toJson()['streaming'], {
      'timeToFirstTokenMs': 250,
      'totalElapsedMs': 2250,
      'completionTokens': 100,
      'chunkCount': 12,
      'likelyBuffered': false,
      'finishReason': 'stop',
      'decodeTokensPerSecond': 50.0,
    });
  });

  test('omits decode rate when the provider buffers the whole response', () {
    const metrics = LiveLlmDiagnosticStreamingMetrics(
      timeToFirstToken: Duration(seconds: 2),
      totalElapsed: Duration(seconds: 2),
      completionTokens: 100,
      chunkCount: 1,
    );

    expect(metrics.decodeTokensPerSecond, isNull);
    expect(metrics.isLikelyBuffered, isTrue);
    expect(metrics.toJson(), isNot(contains('decodeTokensPerSecond')));
  });

  test('rejects a many-chunk terminal burst as buffered delivery', () {
    const metrics = LiveLlmDiagnosticStreamingMetrics(
      timeToFirstToken: Duration(milliseconds: 1085),
      totalElapsed: Duration(milliseconds: 1109),
      completionTokens: 111,
      chunkCount: 110,
    );

    expect(metrics.isLikelyBuffered, isTrue);
    expect(metrics.decodeTokensPerSecond, isNull);
  });

  test('serializes sampler calibration trials in diagnostic reports', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 6, 12),
      baseUrl: 'http://localhost:1234/v1',
      model: 'sampler-model',
      demoMode: false,
      mcpEnabled: true,
      samplerCalibrationTrials: const [
        LiveLlmDiagnosticSamplerTrial(
          requestClass: 'toolLoop',
          temperature: 0.2,
          passed: true,
          jsonRepairEventCount: 1,
          malformedToolCallCount: 2,
          editApplyFailureCount: 3,
          repetitionDetected: true,
        ),
        LiveLlmDiagnosticSamplerTrial(
          requestClass: 'toolLoop',
          temperature: 0.4,
          passed: false,
          malformedToolCallCount: -5,
        ),
      ],
    );

    final updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: 'instruction_echo',
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'JSON ok.',
      ),
    );
    final json = updated.toJson();

    expect(updated.samplerCalibrationTrials, hasLength(2));
    expect(json['samplerCalibrationTrials'], [
      {
        'requestClass': 'toolLoop',
        'temperature': 0.2,
        'passed': true,
        'jsonRepairEventCount': 1,
        'malformedToolCallCount': 2,
        'editApplyFailureCount': 3,
        'repetitionDetected': true,
      },
      {'requestClass': 'toolLoop', 'temperature': 0.4, 'passed': false},
    ]);
    expect(json['samplerCalibrationSummary'], {
      'toolLoop': {
        'trialCount': 2,
        'passedCount': 1,
        'candidateTemperatures': [0.2, 0.4],
        'jsonRepairEventCount': 1,
        'malformedToolCallCount': 2,
        'editApplyFailureCount': 3,
        'repetitionCount': 1,
      },
    });
  });
}
