import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/model_capability_physical_metrics.dart';

void main() {
  test('stores each measured capability with an explicit unit key', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 14),
      baseUrl: 'http://localhost:1234/v1',
      model: 'metric-model',
      demoMode: false,
      mcpEnabled: false,
      streamingMetrics: const LiveLlmDiagnosticStreamingMetrics(
        timeToFirstToken: Duration(milliseconds: 100),
        totalElapsed: Duration(milliseconds: 1100),
        completionTokens: 50,
        chunkCount: 50,
      ),
      multiRoundToolLoopMetrics:
          const LiveLlmDiagnosticMultiRoundToolLoopMetrics(
            totalElapsed: Duration(milliseconds: 2500),
            modelTurnCount: 3,
            toolCallCount: 2,
            successfulToolExecutionCount: 2,
            promptTokens: 3100,
            completionTokens: 100,
            taskCompleted: true,
          ),
      embeddingMetrics: const LiveLlmDiagnosticEmbeddingMetrics(
        totalElapsed: Duration(milliseconds: 80),
        inputCount: 3,
        returnedVectorCount: 3,
        dimension: 1024,
        model: 'embedding-model',
        similarCosine: 0.8,
        unrelatedCosine: 0.2,
      ),
      effectiveContextMetrics: const LiveLlmDiagnosticEffectiveContextMetrics(
        configuredMaximumTokens: 32768,
        trials: [
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: 16384,
            elapsed: Duration(milliseconds: 90),
            passed: true,
            promptTokens: 16498,
          ),
        ],
      ),
    );

    final metrics = ModelCapabilityPhysicalMetrics.fromReport(report);

    expect(metrics[ModelCapabilityPhysicalMetrics.streamingTtftMs], '100');
    expect(
      metrics[ModelCapabilityPhysicalMetrics.streamingDecodeTokensPerSecond],
      '50.00',
    );
    expect(metrics[ModelCapabilityPhysicalMetrics.toolLoopModelTurns], '3');
    expect(metrics[ModelCapabilityPhysicalMetrics.toolLoopTotalTokens], '3200');
    expect(metrics[ModelCapabilityPhysicalMetrics.embeddingDimension], '1024');
    expect(
      metrics[ModelCapabilityPhysicalMetrics.embeddingSemanticMargin],
      '0.600000',
    );
    expect(
      metrics[ModelCapabilityPhysicalMetrics.effectiveContextPromptTokens],
      '16498',
    );
  });

  test('does not persist a decode rate for buffered delivery', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 8, 14),
      baseUrl: 'http://localhost:1234/v1',
      model: 'buffered-model',
      demoMode: false,
      mcpEnabled: false,
      streamingMetrics: const LiveLlmDiagnosticStreamingMetrics(
        timeToFirstToken: Duration(milliseconds: 100),
        totalElapsed: Duration(milliseconds: 105),
        completionTokens: 50,
        chunkCount: 50,
      ),
    );

    final metrics = ModelCapabilityPhysicalMetrics.fromReport(report);

    expect(
      metrics[ModelCapabilityPhysicalMetrics.streamingLikelyBuffered],
      'true',
    );
    expect(
      metrics,
      isNot(
        contains(ModelCapabilityPhysicalMetrics.streamingDecodeTokensPerSecond),
      ),
    );
  });

  test('reads the same physical units from a benchmark run export', () {
    final metrics = ModelCapabilityPhysicalMetrics.fromBenchmarkRun({
      'streaming': {
        'timeToFirstTokenMs': 900,
        'totalElapsedMs': 1800,
        'completionTokens': 90,
        'chunkCount': 45,
        'likelyBuffered': false,
        'decodeTokensPerSecond': 100.0,
      },
      'multiRoundToolLoop': {
        'totalElapsedMs': 2400,
        'modelTurnCount': 3,
        'toolCallCount': 2,
        'successfulToolExecutionCount': 2,
        'promptTokens': 3000,
        'completionTokens': 120,
        'totalTokens': 3120,
        'taskCompleted': true,
      },
      'embeddings': {
        'totalElapsedMs': 75,
        'inputCount': 3,
        'returnedVectorCount': 3,
        'dimension': 768,
        'model': 'embedding-model',
        'similarCosine': 0.75,
        'unrelatedCosine': 0.25,
        'semanticMargin': 0.5,
      },
      'effectiveContext': {
        'configuredMaximumTokens': 32768,
        'maxSuccessfulPromptTokens': 16498,
        'reachedConfiguredMaximum': false,
      },
    });

    expect(metrics[ModelCapabilityPhysicalMetrics.streamingTtftMs], '900');
    expect(
      metrics[ModelCapabilityPhysicalMetrics.streamingDecodeTokensPerSecond],
      '100.0',
    );
    expect(metrics[ModelCapabilityPhysicalMetrics.toolLoopTotalTokens], '3120');
    expect(
      metrics[ModelCapabilityPhysicalMetrics.embeddingSemanticMargin],
      '0.5',
    );
    expect(
      metrics[ModelCapabilityPhysicalMetrics.effectiveContextPromptTokens],
      '16498',
    );
  });

  test('does not trust an artifact decode rate marked as buffered', () {
    final metrics = ModelCapabilityPhysicalMetrics.fromBenchmarkRun({
      'streaming': {
        'timeToFirstTokenMs': 900,
        'totalElapsedMs': 905,
        'completionTokens': 90,
        'chunkCount': 45,
        'likelyBuffered': true,
        'decodeTokensPerSecond': 18000.0,
      },
    });

    expect(
      metrics,
      isNot(
        contains(ModelCapabilityPhysicalMetrics.streamingDecodeTokensPerSecond),
      ),
    );
  });
}
