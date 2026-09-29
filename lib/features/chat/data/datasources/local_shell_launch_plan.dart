import 'local_command_workspace_containment.dart';
import 'shell_write_observation.dart';

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
