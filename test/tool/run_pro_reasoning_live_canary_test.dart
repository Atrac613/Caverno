import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final runner = File(
    'tool/run_pro_reasoning_live_canary.sh',
  ).readAsStringSync();
  final canary = File(
    'tool/canaries/pro_reasoning_live_canary_test.dart',
  ).readAsStringSync();

  test('runner requires explicit data-export consent and loaded endpoints', () {
    expect(runner, contains('CAVERNO_LIVE_LLM_DATA_EXPORT_ACK'));
    expect(runner, contains('CAVERNO_LLM_BASE_URL'));
    expect(runner, contains('CAVERNO_LLM_MODEL'));
    expect(runner, contains('CAVERNO_PRO_REASONING_SECONDARY_BASE_URL'));
    expect(runner, contains('CAVERNO_PRO_REASONING_SECONDARY_MODEL'));
    expect(runner, isNot(contains('192.168.')));
  });

  test('canary covers LL40 execution and logging closure scenarios', () {
    expect(canary, contains("'multi_host'"));
    expect(canary, contains("'single_host'"));
    expect(canary, contains("'cancel'"));
    expect(canary, contains("'logging_disabled'"));
    expect(canary, contains('pro_reasoning_summary'));
    expect(canary, contains('ModelUsageRole.proReasoning'));
    expect(canary, contains('CAVERNO_PRO_REASONING_LIVE_CANARY_DIR'));
  });
}
