import 'dart:io';

import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_benchmark_repeat_summary.dart';

void main() {
  group('LL39 benchmark canary runner', () {
    late String script;
    late String canary;

    setUpAll(() {
      script = File('tool/run_live_llm_benchmark_canary.sh').readAsStringSync();
      canary = File(
        'tool/canaries/live_llm_benchmark_canary_test.dart',
      ).readAsStringSync();
    });

    test('wires the canary target and its report directory', () {
      expect(
        script,
        contains('tool/canaries/live_llm_benchmark_canary_test.dart'),
      );
      expect(script, contains('CAVERNO_BENCHMARK_CANARY=1'));
      expect(script, contains('CAVERNO_BENCHMARK_CANARY_REPORT_DIR='));
      expect(script, contains('CAVERNO_BENCHMARK_CANARY_REPEAT_COUNT='));
      expect(script, contains('CAVERNO_BENCHMARK_CANARY_WARMUP_REPEAT_COUNT='));
      expect(script, contains('CAVERNO_BENCHMARK_CANARY_WARMUP_MODE='));
      expect(script, contains('benchmark_run.json'));
      // The artifact is the deliverable; the script must say where it landed
      // even when the run itself failed.
      expect(script, contains('No benchmark artifact was written'));
    });

    test('requires endpoint configuration before running', () {
      expect(script, contains('CAVERNO_LLM_BASE_URL:?'));
      expect(script, contains('CAVERNO_LLM_API_KEY:?'));
      expect(script, contains('CAVERNO_LLM_MODEL:?'));
      expect(script, contains('CAVERNO_EMBEDDINGS_MODEL'));
      expect(script, contains('CAVERNO_EFFECTIVE_CONTEXT_MAX_TOKENS'));
      expect(script, contains('CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH'));
      expect(script, contains('CAVERNO_BENCHMARK_CANARY_APP_TOOL_PROFILE'));
      expect(canary, contains('CAVERNO_EFFECTIVE_CONTEXT_MAX_TOKENS'));
      expect(canary, contains('loadLiveLlmBenchmarkMcpServers'));
      expect(canary, contains('LiveLlmBenchmarkToolProfile.create'));
      expect(canary, contains('addTearDown(toolProfile.dispose)'));
      expect(canary, contains('Host-app catalog parity failed'));
      expect(canary, contains('definitions.length != 170'));
      expect(canary, contains('initialDefinitions.length != 48'));
      expect(canary, contains('remoteToolCount != 52'));
      expect(canary, contains('Configured MCP discovery incomplete'));
    });

    test('documents the loopback requirement for a LAN endpoint', () {
      // flutter_tester cannot reach a LAN address directly on macOS, and a
      // canary that silently cannot connect looks like a model failure.
      expect(script, contains('tool/with_live_llm_loopback.sh'));
      expect(script, contains('CAVERNO_LLM_ORIGIN_BASE_URL'));
      expect(script, contains('CAVERNO_LLM_EFFECTIVE_BASE_URL'));
      expect(script, contains('CAVERNO_LLM_RELAY_MODE'));
    });

    test(
      'routes Apple Foundation Models to the host app, not flutter_tester',
      () {
        expect(script, contains('appleFoundationModels'));
        expect(script, contains('FLUTTER_DEVICE_ARGS=(-d macos)'));
      },
    );

    test('stays skipped unless explicitly enabled', () {
      expect(
        canary,
        contains("Platform.environment['CAVERNO_BENCHMARK_CANARY'] == '1'"),
      );
      expect(canary, contains('Set CAVERNO_BENCHMARK_CANARY=1'));
    });

    test('measures rather than gates by default', () {
      // A benchmark that fails on a weak model is a gate. The floor exists but
      // must be opt-in.
      expect(canary, contains('CAVERNO_BENCHMARK_CANARY_MIN_POINTS'));
      expect(canary, contains('if (floor != null)'));
    });

    test('refuses to pass a run that attempted no diagnostic probe', () {
      // The blindness this guards against: every probe skipped, harness green.
      expect(canary, contains('attempted no diagnostic probe'));
      expect(canary, contains('probe.attempted'));
      expect(canary, contains('run.score.samplerAttempted'));
      expect(canary, contains('left probes unfinished'));
      expect(canary, contains('CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS'));
    });

    test('writes the spread across repeats into the artifact', () {
      expect(canary, contains("'schema': 'caverno_live_llm_benchmark_canary'"));
      expect(canary, contains("'spread': points.last - points.first"));
      expect(
        canary,
        contains("'suiteVersion': LiveLlmDiagnosticSuite.version"),
      );
      expect(canary, contains("'provider': env.settings.llmProvider.name"));
      expect(canary, contains("'wallClockMs'"));
      expect(canary, contains("'streamingSummary': streamingSummary"));
      expect(canary, contains("'probeSummaries': probeSummaries"));
      expect(canary, contains("'warmupRepeatCount': warmupRuns.length"));
      expect(canary, contains("'warmupMode': env.warmupMode.name"));
      expect(canary, contains("'warmupRuns': ["));
      expect(canary, contains("'warmupProbeSummaries': warmupProbeSummaries"));
      expect(canary, contains('requireRequiredProbePass: true'));
      expect(canary, contains('did not pass every required probe'));
      expect(canary, contains('buildUnrelatedLiveLlmBenchmarkWarmupMessages'));
      expect(canary, contains('did not return the exact unrelated completion'));
    });

    test('runner script is executable', () {
      final mode = File(
        'tool/run_live_llm_benchmark_canary.sh',
      ).statSync().mode;
      expect(mode & 0x40, isNot(0), reason: 'owner execute bit must be set');
    });
  });

  group('streaming repeat summary', () {
    test('aggregates latency ranges and buffered runs', () {
      final summary = buildLiveLlmStreamingRepeatSummary([
        _streamingMetrics(ttftMs: 38680, totalMs: 38708),
        _streamingMetrics(ttftMs: 3769, totalMs: 3790),
        _streamingMetrics(ttftMs: 3781, totalMs: 3803),
      ]);

      expect(summary, {
        'measuredRunCount': 3,
        'bufferedRunCount': 3,
        'timeToFirstTokenMs': {'min': 3769, 'max': 38680, 'spread': 34911},
        'totalElapsedMs': {'min': 3790, 'max': 38708, 'spread': 34918},
      });
    });

    test('omits a summary when streaming was not measured', () {
      expect(buildLiveLlmStreamingRepeatSummary(const [null, null]), isEmpty);
    });

    test('reports zero spread for a single measured run', () {
      final summary = buildLiveLlmStreamingRepeatSummary([
        _streamingMetrics(
          ttftMs: 900,
          totalMs: 1200,
          chunkCount: 20,
          completionTokens: 10,
        ),
      ]);

      expect(summary['measuredRunCount'], 1);
      expect(summary['bufferedRunCount'], 0);
      expect(summary['timeToFirstTokenMs'], {
        'min': 900,
        'max': 900,
        'spread': 0,
      });
      expect(summary['totalElapsedMs'], {
        'min': 1200,
        'max': 1200,
        'spread': 0,
      });
    });
  });

  group('probe repeat summary', () {
    test('aggregates statuses, latency, and token distributions', () {
      final summary = buildLiveLlmProbeRepeatSummaries([
        [
          _probeResult(
            id: 'initial_harness_selection',
            elapsedMs: 11035,
            promptTokens: 8974,
            completionTokens: 15,
          ),
        ],
        [
          _probeResult(
            id: 'initial_harness_selection',
            status: LiveLlmDiagnosticStatus.warning,
            elapsedMs: 9000,
            promptTokens: 8974,
            completionTokens: 17,
          ),
        ],
        [
          _probeResult(
            id: 'initial_harness_selection',
            status: LiveLlmDiagnosticStatus.failed,
            elapsedMs: 12000,
            promptTokens: 8974,
            completionTokens: 13,
          ),
        ],
      ]);

      expect(summary['initial_harness_selection'], {
        'measuredRunCount': 3,
        'passedRunCount': 1,
        'warningRunCount': 1,
        'failedRunCount': 1,
        'elapsedMs': {
          'min': 9000,
          'median': 11035,
          'max': 12000,
          'spread': 3000,
        },
        'promptTokens': {'min': 8974, 'median': 8974, 'max': 8974, 'spread': 0},
        'completionTokens': {'min': 13, 'median': 15, 'max': 17, 'spread': 4},
      });
    });

    test('omits skipped probes and preserves half-step medians', () {
      final summary = buildLiveLlmProbeRepeatSummaries([
        [
          _probeResult(
            id: 'selected',
            elapsedMs: 10,
            promptTokens: 100,
            completionTokens: 3,
          ),
          _probeResult(id: 'skipped', status: LiveLlmDiagnosticStatus.skipped),
        ],
        [
          _probeResult(
            id: 'selected',
            elapsedMs: 11,
            promptTokens: 101,
            completionTokens: 4,
          ),
        ],
      ]);

      expect(summary, isNot(contains('skipped')));
      final selected = summary['selected']! as Map<String, Object>;
      expect((selected['elapsedMs']! as Map)['median'], 10.5);
      expect((selected['promptTokens']! as Map)['median'], 100.5);
      expect((selected['completionTokens']! as Map)['median'], 3.5);
    });
  });
}

LiveLlmDiagnosticStreamingMetrics _streamingMetrics({
  required int ttftMs,
  required int totalMs,
  int completionTokens = 111,
  int chunkCount = 110,
}) => LiveLlmDiagnosticStreamingMetrics(
  timeToFirstToken: Duration(milliseconds: ttftMs),
  totalElapsed: Duration(milliseconds: totalMs),
  completionTokens: completionTokens,
  chunkCount: chunkCount,
  finishReason: 'stop',
);

LiveLlmDiagnosticProbeResult _probeResult({
  required String id,
  LiveLlmDiagnosticStatus status = LiveLlmDiagnosticStatus.passed,
  int elapsedMs = 0,
  int promptTokens = 0,
  int completionTokens = 0,
}) => LiveLlmDiagnosticProbeResult(
  id: id,
  status: status,
  summary: 'benchmark fixture',
  elapsed: Duration(milliseconds: elapsedMs),
  usage: LiveLlmDiagnosticTokenUsage(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: promptTokens + completionTokens,
  ),
);
