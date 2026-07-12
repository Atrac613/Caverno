import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('word-frequency runner selects the short-prompt live scenario', () {
    final runner = File(
      'tool/run_coding_word_frequency_live_canary.sh',
    ).readAsStringSync();
    final canary = File(
      'tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart',
    ).readAsStringSync();

    expect(runner, contains('CAVERNO_CODING_WORD_FREQUENCY_LIVE_CANARY=1'));
    expect(runner, contains('word_frequency_cli.md'));
    expect(runner, contains('--canary-name coding_word_frequency_live_canary'));
    expect(runner, contains('--surface coding_mvp'));
    expect(
      runner,
      contains(
        '--plain-name "live LLM assembles the word_frequency_cli.md MVP from a short prompt"',
      ),
    );
    expect(canary, contains('dart run tool/verify_word_frequency_cli.dart'));
    expect(canary, contains('word_frequency_normalization_or_order_failed'));
    expect(canary, contains('word_frequency_top_n_failed'));
    expect(canary, contains('word_frequency_oversized_n_failed'));
    expect(canary, contains('word_frequency_missing_file_failed'));
  });
}
