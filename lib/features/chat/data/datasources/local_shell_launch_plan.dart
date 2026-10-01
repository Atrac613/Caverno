import 'dart:io';

import '../../../../core/services/login_shell_environment.dart';
import 'local_command_workspace_containment.dart';
import 'shell_write_observation.dart';
import 'workspace_command_environment.dart';

String? commandContainmentRoot(Map<String, dynamic> arguments) =>
    arguments['workspace_command_containment'] == true
    ? arguments['allowed_read_root'] as String? ?? ''
    : null;

/// Selects either enforced command containment or optional shell observation.
final class LocalShellLaunchPlan {
  const LocalShellLaunchPlan({
    required this.executable,
    required this.args,
    this.observationTag,
    this.sandbox,
  });

  final String executable;
  final List<String> args;
  final String? observationTag;
  final LocalCommandWorkspaceSandbox? sandbox;

  String? get scratchDirectory => sandbox?.scratch.path;

  Future<void> dispose() async => sandbox?.dispose();

  Future<Process> start(String workingDirectory) async {
    return startLocalShellProcess(
      executable: executable,
      arguments: args,
      workingDirectory: workingDirectory,
      scratchDirectory: scratchDirectory,
    );
  }

  static Future<LocalShellLaunchPlan?> prepare({
    required String command,
    required String shellExecutable,
    required List<String> shellArgs,
    required String? observationRoot,
    required String? containmentRoot,
  }) async {
    if (containmentRoot != null) {
      final sandbox = await LocalCommandWorkspaceContainment.prepare(
        command: command,
        root: containmentRoot,
      );
      if (sandbox == null) return null;
      return LocalShellLaunchPlan(
        executable: LocalCommandWorkspaceContainment.executable,
        args: ['-p', sandbox.profile, shellExecutable, ...shellArgs],
        sandbox: sandbox,
      );
    }
    final observed = ShellWriteObservation.wrap(
      command: command,
      shellExecutable: shellExecutable,
      shellArgs: shellArgs,
      root: observationRoot,
    );
    return LocalShellLaunchPlan(
      executable: observed?.executable ?? shellExecutable,
      args: observed?.args ?? shellArgs,
      observationTag: observed?.tag,
    );
  }
}

Future<Process> startLocalShellProcess({
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
  String? scratchDirectory,
}) async {
  final source = await LoginShellEnvironment.instance.environment();
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: scratchDirectory == null
        ? source
        : WorkspaceCommandEnvironment.isolated(
            source: source,
            scratch: scratchDirectory,
          ),
    includeParentEnvironment: scratchDirectory == null,
  );
}
