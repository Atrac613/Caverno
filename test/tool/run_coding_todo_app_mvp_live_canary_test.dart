import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Coding TODO app MVP live canary', () {
    test('pins Dart and preserves the fixture acceptance contract', () {
      final runner = File(
        'tool/run_coding_todo_app_mvp_live_canary.sh',
      ).readAsStringSync();
      final autoContinueRunner = File(
        'tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh',
      ).readAsStringSync();
      final canary = File(
        'tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart',
      ).readAsStringSync();

      expect(runner, contains('CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY=1'));
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
      expect(canary, contains('The verifier resets its own known state files'));
      expect(canary, contains('After the verifier exits with code 0'));
      expect(canary, contains('todo_post_success_mutation'));
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
