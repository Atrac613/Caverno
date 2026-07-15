import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/application/caverno_cli_input.dart';

void main() {
  const resolver = CavernoCliPromptResolver();

  test('uses an explicit prompt without consuming stdin', () async {
    final input = _FakeInput(isTerminal: false, stdinValue: 'ignored');
    final prompt = await resolver.resolve(
      invocation: CavernoCliInvocation.parse(const ['chat', 'hello']),
      input: input,
      diagnostics: _FakeDiagnostics(),
    );

    expect(prompt, 'hello');
    expect(input.readToEndCount, 0);
  });

  test('reads piped stdin when no explicit source is supplied', () async {
    final input = _FakeInput(isTerminal: false, stdinValue: 'piped prompt\n');
    final prompt = await resolver.resolve(
      invocation: CavernoCliInvocation.parse(const ['chat']),
      input: input,
      diagnostics: _FakeDiagnostics(),
    );

    expect(prompt, 'piped prompt\n');
    expect(input.readToEndCount, 1);
  });

  test('prompts for one line when stdin is a terminal', () async {
    final input = _FakeInput(isTerminal: true, lineValue: 'interactive');
    final diagnostics = _FakeDiagnostics();
    final prompt = await resolver.resolve(
      invocation: CavernoCliInvocation.parse(const ['chat']),
      input: input,
      diagnostics: diagnostics,
    );

    expect(prompt, 'interactive');
    expect(diagnostics.values, ['Prompt: ']);
  });

  test('reads an explicit prompt file', () async {
    final input = _FakeInput(
      isTerminal: false,
      files: const {'request.md': 'from file'},
    );
    final prompt = await resolver.resolve(
      invocation: CavernoCliInvocation.parse(const [
        'chat',
        '--prompt-file',
        'request.md',
      ]),
      input: input,
      diagnostics: _FakeDiagnostics(),
    );

    expect(prompt, 'from file');
  });

  test('rejects empty non-interactive input', () async {
    final input = _FakeInput(isTerminal: false, stdinValue: '  \n');

    await expectLater(
      resolver.resolve(
        invocation: CavernoCliInvocation.parse(const ['chat']),
        input: input,
        diagnostics: _FakeDiagnostics(),
      ),
      throwsA(
        isA<CavernoCliFailure>()
            .having((error) => error.code, 'code', 'empty_input')
            .having(
              (error) => error.exitCode,
              'exitCode',
              CavernoCliExitCode.input,
            ),
      ),
    );
  });
}

final class _FakeInput implements CavernoCliInputPort {
  _FakeInput({
    required this.isTerminal,
    this.lineValue,
    this.stdinValue = '',
    this.files = const {},
  });

  @override
  final bool isTerminal;
  final String? lineValue;
  final String stdinValue;
  final Map<String, String> files;
  int readToEndCount = 0;

  @override
  Future<String> readFile(String path) async => files[path]!;

  @override
  Future<String?> readLine() async => lineValue;

  @override
  Future<String> readToEnd() async {
    readToEndCount += 1;
    return stdinValue;
  }
}

final class _FakeDiagnostics implements CavernoCliDiagnosticPort {
  final values = <String>[];

  @override
  void writeDiagnostic(String value) {
    values.add(value);
  }
}
