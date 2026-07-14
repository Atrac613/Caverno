import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Coding TODO app MVP live canary', () {
    test('pins Dart and preserves the fixture acceptance contract', () {
      final runner = File(
        'tool/run_coding_todo_app_mvp_live_canary.sh',
      ).readAsStringSync();
      final minimalPromptRunner = File(
        'tool/run_coding_todo_app_minimal_prompt_live_canary.sh',
      ).readAsStringSync();
      final markdownTocExactShortRunner = File(
        'tool/run_coding_markdown_toc_exact_short_live_canary.sh',
      ).readAsStringSync();
      final pendingActionLengthRecoveryRunner = File(
        'tool/run_coding_pending_action_length_recovery_live_canary.sh',
      ).readAsStringSync();
      final autoContinueRunner = File(
        'tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh',
      ).readAsStringSync();
      final canary = File(
        'tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart',
      ).readAsStringSync();

      expect(runner, contains('CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY=1'));
      expect(
        minimalPromptRunner,
        contains('CAVERNO_CODING_TODO_APP_MINIMAL_PROMPT_LIVE_CANARY=1'),
      );
      expect(
        minimalPromptRunner,
        contains(
          '--plain-name "live LLM assembles the todo_app.md MVP from the minimal Japanese prompt"',
        ),
      );
      expect(
        minimalPromptRunner,
        contains('--canary-name coding_todo_app_minimal_prompt_live_canary'),
      );
      expect(
        markdownTocExactShortRunner,
        contains('CAVERNO_CODING_MARKDOWN_TOC_EXACT_SHORT_LIVE_CANARY=1'),
      );
      expect(
        markdownTocExactShortRunner,
        contains(
          '--plain-name "live LLM assembles the markdown_toc_generator.md MVP from the exact short prompt"',
        ),
      );
      expect(
        markdownTocExactShortRunner,
        contains('--canary-name coding_markdown_toc_exact_short_live_canary'),
      );
      expect(
        pendingActionLengthRecoveryRunner,
        contains('CAVERNO_CODING_PENDING_ACTION_LENGTH_RECOVERY_LIVE_CANARY=1'),
      );
      expect(
        pendingActionLengthRecoveryRunner,
        contains(
          '--plain-name "live LLM recovers one length-truncated pending coding action"',
        ),
      );
      expect(
        pendingActionLengthRecoveryRunner,
        contains(
          '--canary-name coding_pending_action_length_recovery_live_canary',
        ),
      );
      expect(
        pendingActionLengthRecoveryRunner,
        isNot(contains('CAVERNO_CODING_GOAL_TODO_MAX_TOKENS')),
      );
      expect(runner, contains('Language: Dart'));
      expect(runner, contains('docs/coding_mvp_fixtures/todo_app.md'));
      expect(runner, contains('--canary-name coding_todo_app_mvp_live_canary'));
      expect(runner, contains('--surface coding_mvp'));
      expect(
        runner,
        contains(
          '--plain-name "live LLM assembles the todo_app.md MVP as a Dart CLI"',
        ),
      );
      expect(
        autoContinueRunner,
        contains(
          '--plain-name "live LLM auto-continues the todo_app.md MVP fixture from diagnostic evidence"',
        ),
      );
      expect(
        canary,
        contains('Implement a Dart command-line program at bin/todo_cli.dart.'),
      );
      expect(canary, contains('Use only the Dart SDK'));
      expect(
        canary,
        contains('The verifier runs every check in a fresh isolated copy'),
      );
      expect(canary, contains('After the verifier exits with code 0'));
      expect(canary, contains('todo_post_success_mutation'));
      expect(canary, contains('autoContinue: true'));
      expect(canary, contains('ConversationContractSourceKind.userMessage'));
      final finalAnswerRecovery = File(
        'lib/features/chat/presentation/providers/chat_notifier_final_answer_recovery.dart',
      ).readAsStringSync();
      expect(
        finalAnswerRecovery,
        contains('Tool-result final stream timed out'),
      );
      expect(
        finalAnswerRecovery,
        contains('returning incomplete evidence to goal continuation'),
      );
      expect(canary, contains('を参考にしてMVPを実装。言語はdartとする。'));
      expect(canary, contains(r'_exactShortMvpPrompt(String documentName)'));
      expect(canary, contains("_exactShortMvpPrompt('todo_app.md')"));
      expect(
        canary,
        contains('CAVERNO_CODING_MARKDOWN_TOC_EXACT_SHORT_LIVE_CANARY'),
      );
      expect(
        canary,
        contains('CAVERNO_CODING_TODO_APP_MINIMAL_PROMPT_LIVE_CANARY'),
      );
      expect(canary, contains(r"'${root.path}/todo_app.md'"));
      expect(canary, contains("name: 'read_file'"));
      expect(canary, contains("name: 'edit_file'"));
      expect(canary, contains("name: 'list_directory'"));
      expect(canary, isNot(contains("name: 'run_tests'")));
      expect(canary, contains('todo_cli_no_arguments_usage_failed'));
      expect(canary, contains('todo_cli_help_failed'));
      expect(canary, contains('todo_cli_unknown_delete_failed'));
      expect(canary, contains('toolService.hasSuccessfulVerifierCall'));
    });

    test('requires an explicit environment gate for the live scenario', () {
      final canary = File(
        'tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart',
      ).readAsStringSync();

      expect(
        canary,
        contains("CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY'] == '1'"),
      );
      expect(
        canary,
        contains(
          'Set CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
        ),
      );
    });
  });
}
