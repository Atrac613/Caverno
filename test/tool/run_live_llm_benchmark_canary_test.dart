import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
      expect(canary, contains('CAVERNO_EFFECTIVE_CONTEXT_MAX_TOKENS'));
    });

    test('documents the loopback requirement for a LAN endpoint', () {
      // flutter_tester cannot reach a LAN address directly on macOS, and a
      // canary that silently cannot connect looks like a model failure.
      expect(script, contains('127.0.0.1'));
      expect(script, contains('Local Network Privacy'));
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
    });

    test('runner script is executable', () {
      final mode = File(
        'tool/run_live_llm_benchmark_canary.sh',
      ).statSync().mode;
      expect(mode & 0x40, isNot(0), reason: 'owner execute bit must be set');
    });
  });
}
