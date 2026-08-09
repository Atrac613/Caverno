import 'first_party_tool_execution_result.dart';
import 'local_shell_tools.dart';

typedef BuiltInLocalCommandRunner =
    Future<String> Function({
      required String command,
      required String workingDirectory,
    });

typedef BuiltInLocalCommandResultRunner =
    Future<FirstPartyToolExecutionResult> Function({
      required String command,
      required String workingDirectory,
    });

BuiltInLocalCommandResultRunner resolveBuiltInLocalCommandResultRunner({
  BuiltInLocalCommandRunner? legacyRunner,
  BuiltInLocalCommandResultRunner? resultRunner,
}) =>
    resultRunner ??
    (legacyRunner == null
        ? LocalShellTools.executeResult
        : ({required command, required workingDirectory}) async =>
              FirstPartyToolExecutionResult.payloadOnly(
                await legacyRunner(
                  command: command,
                  workingDirectory: workingDirectory,
                ),
              ));
