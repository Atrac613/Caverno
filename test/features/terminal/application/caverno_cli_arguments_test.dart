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
