import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LL22 production warm-up canary', () {
    late String runner;
    late String abRunner;
    late String canary;

    setUpAll(() {
      runner = File(
        'tool/run_ll22_production_warmup_canary.sh',
      ).readAsStringSync();
      abRunner = File(
        'tool/run_ll22_production_warmup_ab.sh',
      ).readAsStringSync();
      canary = File(
        'tool/canaries/chat_live_llm_canary_test.dart',
      ).readAsStringSync();
    });

    test('runs only the opt-in LL22 ChatNotifier path', () {
      expect(runner, contains('CAVERNO_LL22_PRODUCTION_WARMUP_CANARY=1'));
      expect(runner, contains('--plain-name'));
      expect(runner, contains('LL22 production warm-up primes'));
      expect(runner, contains('CAVERNO_LL22_REPORT_DIR='));
      expect(canary, contains('maintenanceStagesProvider'));
      expect(canary, contains("stage.name == 'warm_cache'"));
      expect(canary, contains('chatNotifierProvider.notifier'));
      expect(canary, contains("'ttftMs'"));
    });

    test('checks production prefix parity before recording warm evidence', () {
      expect(canary, contains('_waitForStableToolCatalog'));
      expect(canary, contains('McpConnectionStatus.connected'));
      expect(canary, contains('hasLength(48)'));
      expect(canary, contains('_wireToolDefinitions'));
      expect(canary, contains('stableSystemPrefixChars'));
      expect(canary, contains('greaterThanOrEqualTo(2000)'));
    });

    test('resets and restores the model around alternating A/B arms', () {
      expect(abRunner, contains('lifecycle_action unload'));
      expect(abRunner, contains('lifecycle_action load'));
      expect(abRunner, contains('trap restore_model EXIT'));
      expect(abRunner, contains('arms=(cold warm)'));
      expect(abRunner, contains('arms=(warm cold)'));
      expect(abRunner, contains('tool/with_live_llm_loopback.sh'));
    });

    test('runner scripts are executable', () {
      for (final path in [
        'tool/run_ll22_production_warmup_canary.sh',
        'tool/run_ll22_production_warmup_ab.sh',
      ]) {
        expect(
          File(path).statSync().mode & 0x40,
          isNot(0),
          reason: '$path owner execute bit must be set',
        );
      }
    });
  });
}
