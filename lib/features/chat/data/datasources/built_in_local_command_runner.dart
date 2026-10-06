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
      String? observationRoot,
      String? containmentRoot,
    });

BuiltInLocalCommandResultRunner resolveBuiltInLocalCommandResultRunner({
  BuiltInLocalCommandRunner? legacyRunner,
  BuiltInLocalCommandResultRunner? resultRunner,
}) =>
    resultRunner ??
    (legacyRunner == null
        ? LocalShellTools.executeResult
        : ({
            required command,
            required workingDirectory,
            observationRoot,
            containmentRoot,
          }) async {
            if (containmentRoot != null) {
              const error = 'Legacy command runners cannot contain commands';
              return const FirstPartyToolExecutionResult(
                result:
                    '{"ok":false,"error":"Legacy command runners cannot contain commands"}',
                errorMessage: error,
              );
            }
            return FirstPartyToolExecutionResult.payloadOnly(
              await legacyRunner(
                command: command,
                workingDirectory: workingDirectory,
              ),
            );
          });
