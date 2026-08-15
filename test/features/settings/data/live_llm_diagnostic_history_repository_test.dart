import 'package:caverno/features/settings/data/live_llm_diagnostic_history_repository.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('round-trips complete reports and skips malformed entries', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = LiveLlmDiagnosticHistoryRepository(prefs);
    final report = _report(0).copyWith(
      streamingMetrics: const LiveLlmDiagnosticStreamingMetrics(
        timeToFirstToken: Duration(milliseconds: 120),
        totalElapsed: Duration(milliseconds: 620),
        completionTokens: 25,
        chunkCount: 8,
        finishReason: 'stop',
      ),
      multiRoundToolLoopMetrics:
          const LiveLlmDiagnosticMultiRoundToolLoopMetrics(
            totalElapsed: Duration(seconds: 2),
            modelTurnCount: 3,
            toolCallCount: 2,
            successfulToolExecutionCount: 2,
            promptTokens: 100,
            completionTokens: 40,
            taskCompleted: true,
          ),
      embeddingMetrics: const LiveLlmDiagnosticEmbeddingMetrics(
        totalElapsed: Duration(milliseconds: 80),
        inputCount: 3,
        returnedVectorCount: 3,
        dimension: 768,
        model: 'embedding-model',
        similarCosine: 0.9,
        unrelatedCosine: 0.2,
      ),
      effectiveContextMetrics: const LiveLlmDiagnosticEffectiveContextMetrics(
        configuredMaximumTokens: 4096,
        trials: [
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: 2048,
            elapsed: Duration(seconds: 1),
            passed: true,
            promptTokens: 2050,
            finishReason: 'stop',
            responsePreview: 'ok',
          ),
        ],
      ),
    );

    await repository.append(report);
    final restored = repository.load().single.report;

    expect(restored.startedAt, report.startedAt);
    expect(restored.results.single.modelContent, 'model output');
    expect(restored.streamingMetrics?.completionTokens, 25);
    expect(restored.multiRoundToolLoopMetrics?.totalTokens, 140);
    expect(restored.embeddingMetrics?.semanticMargin, closeTo(0.7, 0.000001));
    expect(restored.effectiveContextMetrics?.maxSuccessfulPromptTokens, 2050);
  });

  test('keeps only the newest ten reports for each model', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = LiveLlmDiagnosticHistoryRepository(prefs);

    for (var i = 0; i < 13; i++) {
      await repository.append(_report(i));
    }
    await repository.append(_report(100, model: 'other-model'));

    final history = repository.load();
    final target = history
        .where((entry) => entry.report.model == 'diagnostic-model')
        .toList();
    expect(target, hasLength(10));
    expect(target.first.report.startedAt, DateTime.utc(2026, 8, 15, 0, 12));
    expect(target.last.report.startedAt, DateTime.utc(2026, 8, 15, 0, 3));
    expect(
      history.where((entry) => entry.report.model == 'other-model'),
      hasLength(1),
    );
  });
}

LiveLlmDiagnosticReport _report(
  int minute, {
  String model = 'diagnostic-model',
}) {
  final startedAt = DateTime.utc(2026, 8, 15, 0, minute);
  return LiveLlmDiagnosticReport(
    startedAt: startedAt,
    finishedAt: startedAt.add(const Duration(seconds: 2)),
    baseUrl: 'http://localhost:1234/v1',
    model: model,
    demoMode: false,
    mcpEnabled: true,
    toolCatalog: const LiveLlmDiagnosticToolCatalog(
      totalToolCount: 2,
      initialToolCount: 1,
      toolNames: ['tool_a', 'tool_b'],
    ),
    results: const [
      LiveLlmDiagnosticProbeResult(
        id: 'instruction_echo',
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'Passed',
        details: 'Exact response',
        modelContent: 'model output',
        usage: LiveLlmDiagnosticTokenUsage(
          promptTokens: 10,
          completionTokens: 3,
          totalTokens: 13,
        ),
        metadata: {'format': 'exact'},
      ),
    ],
    samplerCalibrationTrials: const [
      LiveLlmDiagnosticSamplerTrial(
        requestClass: 'chat',
        temperature: 0.2,
        passed: true,
      ),
    ],
  );
}
