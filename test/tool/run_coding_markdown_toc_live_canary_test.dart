import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Markdown TOC runner selects the short-prompt live scenario', () {
    final runner = File(
      'tool/run_coding_markdown_toc_live_canary.sh',
    ).readAsStringSync();
    final canary = File(
      'tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart',
    ).readAsStringSync();

    expect(runner, contains('CAVERNO_CODING_MARKDOWN_TOC_LIVE_CANARY=1'));
    expect(runner, contains('markdown_toc_generator.md'));
    expect(runner, contains('--canary-name coding_markdown_toc_live_canary'));
    expect(runner, contains('--surface coding_mvp'));
    expect(
      runner,
      contains(
        '--plain-name "live LLM assembles the markdown_toc_generator.md MVP from a short prompt"',
      ),
    );
    expect(canary, contains('dart run tool/verify_markdown_toc.dart'));
    expect(canary, contains('markdown_toc_fence_close_failed'));
    expect(canary, contains('markdown_toc_duplicate_slug_failed'));
    expect(canary, contains('markdown_toc_nesting_failed'));
    expect(canary, contains('markdown_toc_sequence_failed'));
    expect(canary, contains('markdown_toc_seven_hash_heading_failed'));
    expect(canary, contains('markdown_toc_empty_document_failed'));
    expect(canary, contains('markdown_toc_unexpected_entrypoint'));
  });
}
