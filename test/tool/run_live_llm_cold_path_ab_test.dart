import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String script;

  setUpAll(() {
    script = File('tool/run_live_llm_cold_path_ab.sh').readAsStringSync();
  });

  test('resets the model before every arm and restores it on exit', () {
    expect(script, contains('trap restore_model EXIT'));
    expect(script, contains('lifecycle_action unload'));
    expect(script, contains('lifecycle_action load'));
    expect(script, contains(r'run_arm "${block}" "${arm}"'));
    expect(script, contains('must start loaded'));
    expect(
      script.indexOf('trap restore_model EXIT'),
      greaterThan(script.indexOf('must start loaded')),
    );
  });

  test('rotates all three controlled warm-up arms', () {
    expect(script, contains('arms=(none unrelated diagnostic)'));
    expect(script, contains('arms=(unrelated diagnostic none)'));
    expect(script, contains('arms=(diagnostic none unrelated)'));
    expect(script, contains('CAVERNO_BENCHMARK_CANARY_REPEAT_COUNT=1'));
    expect(
      script,
      contains('CAVERNO_BENCHMARK_CANARY_PROBE_IDS=initial_harness_selection'),
    );
  });

  test('uses the managed loopback wrapper and explicit MCP config', () {
    expect(script, contains('tool/with_live_llm_loopback.sh'));
    expect(script, contains('CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH='));
    expect(script, contains('CAVERNO_BENCHMARK_CANARY_APP_TOOL_PROFILE=1'));
  });

  test('runner script is executable', () {
    final mode = File('tool/run_live_llm_cold_path_ab.sh').statSync().mode;
    expect(mode & 0x49, isNot(0));
  });
}
