import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/narrated_transcript_claim_guard.dart';

void main() {
  const guard = NarratedTranscriptClaimGuard();

  ToolResultInfo executedCommand(String command, {int exitCode = 0}) {
    return ToolResultInfo(
      id: 'cmd-${command.hashCode}',
      name: 'local_execute_command',
      arguments: {'command': command},
      result: jsonEncode({
        'command': command,
        'exit_code': exitCode,
        'stdout': '',
        'stderr': '',
      }),
    );
  }

  group('transcript extraction', () {
    test(
      'flags commands narrated with output but never executed '
      '(session 87f29602 fabricated walk-through)',
      () {
        // Condensed from the real fabricated final answer: the compound
        // add/add/list command ran, done/delete and the unknown-id exit-code
        // check never did.
        final assessment = guard.assess(
          candidateResponse: '''
Verification (including cross-process persistence):

```bash
\$ dart run lib/main.dart add "buy milk"
#4 [ ] buy milk

\$ dart run lib/main.dart list
#4 [ ] buy milk

\$ dart run lib/main.dart done 4
Todo #4 marked as done.

\$ dart run lib/main.dart delete 5
Todo #5 deleted.

# unknown-id error handling (exit code 1)
\$ dart run lib/main.dart done 999; echo "exit=\$?"
Error: Todo with id 999 not found.
exit=1
```

The MVP is complete.
''',
          toolResults: [
            executedCommand(
              'dart run lib/main.dart add "buy milk" && '
              'dart run lib/main.dart list',
            ),
          ],
        );

        expect(assessment.hasUnexecutedCommands, isTrue);
        expect(assessment.unexecutedCommands, [
          'dart run lib/main.dart done 4',
          'dart run lib/main.dart delete 5',
          'dart run lib/main.dart done 999',
          'echo "exit=\$?"',
        ]);
        final notice = assessment.buildNotice();
        expect(notice, contains('Transcript claim check:'));
        expect(notice, contains('`dart run lib/main.dart done 4`'));
        expect(notice, isNot(contains('buy milk')));
      },
    );

    test('ignores a usage example without prompt markers', () {
      // Condensed from the same session: a "how to use it" block whose
      // commands carry no $ prompt is documentation, not claimed evidence.
      final assessment = guard.assess(
        candidateResponse: '''
Usage:

```bash
dart compile exe lib/main.dart -o todo
./todo add "task text"
./todo done 1
./todo list
```
''',
        toolResults: const [],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('ignores prompt-marked commands without interleaved output', () {
      final assessment = guard.assess(
        candidateResponse: '''
Run these to verify:

```bash
\$ dart analyze
\$ dart test
```
''',
        toolResults: const [],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('ignores prose and inline code outside fences', () {
      final assessment = guard.assess(
        candidateResponse:
            'I verified with `dart test` and \$ dart analyze; both passed.',
        toolResults: const [],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('comment and blank lines do not count as output', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
# add the first task
\$ dart run lib/main.dart add "first"

# then list
\$ dart run lib/main.dart list
```
''',
        toolResults: const [],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('assesses an unterminated trailing fence', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ dart test
All tests passed!
''',
        toolResults: const [],
      );

      expect(assessment.unexecutedCommands, ['dart test']);
    });

    test('supports the % prompt marker', () {
      final assessment = guard.assess(
        candidateResponse: '''
```
% dart test
00:01 +12: All tests passed!
```
''',
        toolResults: const [],
      );

      expect(assessment.unexecutedCommands, ['dart test']);
    });
  });

  group('execution matching', () {
    test('matches a narrated command against a compound executed segment', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ dart run lib/main.dart list
#1 [x] task
```
''',
        toolResults: [
          executedCommand(
            'cd /workspace/project && dart run lib/main.dart add "task" && '
            'dart run lib/main.dart list',
          ),
        ],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('splits a narrated compound line before matching', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ dart run lib/main.dart add "a" && dart run lib/main.dart done 1
#1 [ ] a
Todo #1 marked as done.
```
''',
        toolResults: [
          executedCommand('dart run lib/main.dart add "a"'),
        ],
      );

      expect(assessment.unexecutedCommands, ['dart run lib/main.dart done 1']);
    });

    test('does not split on separators inside quotes', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ dart run lib/main.dart add "milk; eggs && bread"
#1 [ ] milk; eggs && bread
```
''',
        toolResults: [
          executedCommand('dart run lib/main.dart add "milk; eggs && bread"'),
        ],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('normalizes whitespace and stderr redirects before matching', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ dart run   lib/main.dart
Usage: ...
```
''',
        toolResults: [executedCommand('dart run lib/main.dart 2>&1')],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('ignores narrated cd segments', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ cd /workspace/project && dart analyze
No issues found!
```
''',
        toolResults: [executedCommand('dart analyze')],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('counts denied and failed calls as issued commands', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ rm -rf build
removed
```
''',
        toolResults: [
          ToolResultInfo(
            id: 'denied',
            name: 'local_execute_command',
            arguments: const {'command': 'rm -rf build'},
            result: 'Error: Local command was denied by a saved permission rule',
          ),
        ],
      );

      // Issued-but-denied claims are covered by the failed-command success
      // claim guards; this guard only targets commands never issued at all.
      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('accepts additional executed commands from the turn ledger', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ dart test
All tests passed!
```
''',
        toolResults: const [],
        additionalExecutedCommands: const ['dart test'],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('reads commands from any command-execution tool result', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ git status
clean
```
''',
        toolResults: [
          ToolResultInfo(
            id: 'git',
            name: 'git_execute_command',
            arguments: const {'command': 'git status'},
            result: '{"exit_code":0}',
          ),
        ],
      );

      expect(assessment.hasUnexecutedCommands, isFalse);
    });

    test('deduplicates repeated narrated commands', () {
      final assessment = guard.assess(
        candidateResponse: '''
```bash
\$ dart run lib/main.dart list
#1 [ ] a
\$ dart run lib/main.dart list
#1 [x] a
```
''',
        toolResults: const [],
      );

      expect(assessment.unexecutedCommands, ['dart run lib/main.dart list']);
    });
  });

  group('notice', () {
    test('caps the listed commands and reports the overflow', () {
      final commands = List.generate(10, (index) => 'command-$index');
      final response = StringBuffer('```\n');
      for (final command in commands) {
        response.writeln('\$ $command');
        response.writeln('output of $command');
      }
      response.writeln('```');

      final assessment = guard.assess(
        candidateResponse: response.toString(),
        toolResults: const [],
      );

      expect(assessment.unexecutedCommands, hasLength(10));
      final notice = assessment.buildNotice();
      expect(notice, contains('`command-7`'));
      expect(notice, isNot(contains('`command-8`')));
      expect(notice, contains('(and 2 more)'));
    });

    test('builds an empty notice when nothing is flagged', () {
      const assessment = NarratedTranscriptClaimAssessment(
        unexecutedCommands: [],
      );
      expect(assessment.buildNotice(), isEmpty);
    });
  });
}
