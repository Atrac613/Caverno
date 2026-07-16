import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';

void main() {
  group('CavernoCliInvocation', () {
    test('parses a positional chat prompt and JSON output', () {
      final invocation = CavernoCliInvocation.parse(const [
        'chat',
        '--json',
        'Explain',
        'this',
      ]);

      expect(invocation.action, CavernoCliInvocationAction.run);
      expect(invocation.command, CavernoCliCommand.chat);
      expect(invocation.prompt, 'Explain this');
      expect(invocation.outputMode, CavernoCliOutputMode.json);
    });

    test('parses coding configuration and inline option values', () {
      final invocation = CavernoCliInvocation.parse(const [
        'coding',
        '--project=/tmp/project',
        '--base-url',
        'http://localhost:1234/v1',
        '--model=qwen',
        '--api-key',
        'secret',
        '--prompt',
        'Fix the test',
      ]);

      expect(invocation.command, CavernoCliCommand.coding);
      expect(invocation.projectPath, '/tmp/project');
      expect(invocation.baseUrl, 'http://localhost:1234/v1');
      expect(invocation.model, 'qwen');
      expect(invocation.apiKey, 'secret');
      expect(invocation.prompt, 'Fix the test');
    });

    test('requires a project for coding and plan', () {
      for (final command in ['coding', 'plan']) {
        expect(
          () => CavernoCliInvocation.parse([command, 'Build it']),
          throwsA(
            isA<CavernoCliFailure>()
                .having((error) => error.code, 'code', 'project_required')
                .having(
                  (error) => error.exitCode,
                  'exitCode',
                  CavernoCliExitCode.usage,
                ),
          ),
        );
      }
    });

    test('parses a bounded conversation list query', () {
      final invocation = CavernoCliInvocation.parse(const [
        'conversations',
        'list',
        '--limit=12',
        '--json',
        '--data-dir',
        '/tmp/caverno',
      ]);

      expect(invocation.action, CavernoCliInvocationAction.conversationList);
      expect(
        invocation.conversationCommand,
        CavernoCliConversationCommand.list,
      );
      expect(invocation.conversationLimit, 12);
      expect(invocation.outputMode, CavernoCliOutputMode.json);
      expect(invocation.dataDirectory, '/tmp/caverno');
    });

    test('parses an exact conversation show query', () {
      final invocation = CavernoCliInvocation.parse(const [
        'conversations',
        'show',
        'conversation-1',
      ]);

      expect(invocation.action, CavernoCliInvocationAction.conversationShow);
      expect(
        invocation.conversationCommand,
        CavernoCliConversationCommand.show,
      );
      expect(invocation.conversationId, 'conversation-1');
    });

    test('parses an exact conversation resume with runtime options', () {
      final invocation = CavernoCliInvocation.parse(const [
        'conversations',
        'resume',
        'conversation-1',
        '--json',
        '--data-dir',
        '/tmp/caverno',
        '--base-url=http://localhost:1234/v1',
        '--model',
        'qwen',
        '--api-key',
        'secret',
        'Continue',
        'the task',
      ]);

      expect(invocation.action, CavernoCliInvocationAction.conversationResume);
      expect(
        invocation.conversationCommand,
        CavernoCliConversationCommand.resume,
      );
      expect(invocation.conversationId, 'conversation-1');
      expect(invocation.prompt, 'Continue the task');
      expect(invocation.outputMode, CavernoCliOutputMode.json);
      expect(invocation.dataDirectory, '/tmp/caverno');
      expect(invocation.baseUrl, 'http://localhost:1234/v1');
      expect(invocation.model, 'qwen');
      expect(invocation.apiKey, 'secret');
    });

    test('parses a conversation resume prompt file', () {
      final invocation = CavernoCliInvocation.parse(const [
        'conversations',
        'resume',
        'conversation-1',
        '--prompt-file',
        'next.md',
      ]);

      expect(invocation.promptFile, 'next.md');
      expect(invocation.prompt, isNull);
    });

    test('rejects invalid conversation query arguments', () {
      final cases = <(List<String>, String)>[
        (const ['conversations'], 'conversation_command_required'),
        (const ['conversations', 'find'], 'unknown_conversation_command'),
        (
          const ['conversations', 'list', 'extra'],
          'unexpected_conversation_argument',
        ),
        (const ['conversations', 'list', '--limit', '0'], 'invalid_limit'),
        (const ['conversations', 'list', '--limit', '201'], 'invalid_limit'),
        (const ['conversations', 'show'], 'conversation_id_required'),
        (const ['conversations', 'resume'], 'conversation_id_required'),
        (
          const ['conversations', 'show', 'one', 'two'],
          'conversation_id_required',
        ),
        (
          const ['conversations', 'show', 'one', '--limit', '20'],
          'limit_not_supported',
        ),
        (const ['conversations', 'list', '--model', 'qwen'], 'unknown_flag'),
        (
          const ['conversations', 'resume', 'one', '--limit', '20'],
          'limit_not_supported',
        ),
        (
          const ['conversations', 'resume', 'one', '--project', '/tmp/p'],
          'unknown_flag',
        ),
        (
          const [
            'conversations',
            'resume',
            'one',
            '--prompt',
            'first',
            'second',
          ],
          'conflicting_input_sources',
        ),
      ];

      for (final (arguments, code) in cases) {
        expect(
          () => CavernoCliInvocation.parse(arguments),
          throwsA(
            isA<CavernoCliFailure>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
          reason: arguments.join(' '),
        );
      }
    });

    test('parses conversation command help without running a query', () {
      final invocation = CavernoCliInvocation.parse(const [
        'conversations',
        'show',
        '--help',
      ]);

      expect(invocation.action, CavernoCliInvocationAction.help);
      expect(
        invocation.conversationCommand,
        CavernoCliConversationCommand.show,
      );

      final resumeInvocation = CavernoCliInvocation.parse(const [
        'conversations',
        'resume',
        '--help',
      ]);
      expect(resumeInvocation.action, CavernoCliInvocationAction.help);
      expect(
        resumeInvocation.conversationCommand,
        CavernoCliConversationCommand.resume,
      );
    });

    test('rejects conflicting explicit input sources', () {
      expect(
        () => CavernoCliInvocation.parse(const [
          'chat',
          '--prompt',
          'one',
          'two',
        ]),
        throwsA(
          isA<CavernoCliFailure>().having(
            (error) => error.code,
            'code',
            'conflicting_input_sources',
          ),
        ),
      );
    });

    test('does not route a macOS process serial argument to the CLI', () {
      expect(
        CavernoCliInvocation.looksLikeCliInvocation(const ['-psn_0_123']),
        isFalse,
      );
      expect(
        CavernoCliInvocation.looksLikeCliInvocation(const ['chat', 'hello']),
        isTrue,
      );
    });
  });
}
