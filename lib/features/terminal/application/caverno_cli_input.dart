import 'caverno_cli_arguments.dart';
import 'caverno_cli_contract.dart';

abstract interface class CavernoCliInputPort {
  bool get isTerminal;

  Future<String?> readLine();

  Future<String> readToEnd();

  Future<String> readFile(String path);
}

abstract interface class CavernoCliDiagnosticPort {
  void writeDiagnostic(String value);
}

final class CavernoCliPromptResolver {
  const CavernoCliPromptResolver();

  Future<String> resolve({
    required CavernoCliInvocation invocation,
    required CavernoCliInputPort input,
    required CavernoCliDiagnosticPort diagnostics,
  }) async {
    String value;
    final explicitPrompt = invocation.prompt;
    final promptFile = invocation.promptFile;
    if (explicitPrompt != null) {
      value = explicitPrompt;
    } else if (promptFile != null) {
      try {
        value = await input.readFile(promptFile);
      } on Object catch (error) {
        throw CavernoCliFailure(
          code: 'prompt_file_unreadable',
          message: 'Could not read prompt file "$promptFile": $error',
          exitCode: CavernoCliExitCode.input,
        );
      }
    } else if (input.isTerminal) {
      diagnostics.writeDiagnostic('Prompt: ');
      value = await input.readLine() ?? '';
    } else {
      value = await input.readToEnd();
    }

    if (value.trim().isEmpty) {
      throw const CavernoCliFailure(
        code: 'empty_input',
        message: 'The prompt is empty.',
        exitCode: CavernoCliExitCode.input,
      );
    }
    return value;
  }
}
