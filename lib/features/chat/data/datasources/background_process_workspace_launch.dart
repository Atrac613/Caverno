import 'dart:io';

import 'background_process_types.dart';
import 'local_shell_launch_plan.dart';

/// Starts the frozen route; never retries a failed sandbox on the host.
abstract final class BackgroundProcessWorkspaceLaunch {
  static Future<({Process process, LocalShellLaunchPlan? launch})> start({
    required String command,
    required String workingDirectory,
    required String? containmentRoot,
    required BackgroundProcessStarter hostStarter,
  }) async {
    final executable = Platform.isWindows ? 'cmd' : 'bash';
    final arguments = Platform.isWindows
        ? ['/C', command]
        : ['-o', 'pipefail', '-c', command];
    if (containmentRoot == null) {
      return (
        process: await hostStarter(executable, arguments, workingDirectory),
        launch: null,
      );
    }
    final launch = await LocalShellLaunchPlan.prepare(
      command: command,
      shellExecutable: executable,
      shellArgs: arguments,
      observationRoot: null,
      containmentRoot: containmentRoot,
    );
    if (launch == null) {
      throw StateError('Command workspace containment could not be started');
    }
    try {
      return (process: await launch.start(workingDirectory), launch: launch);
    } catch (_) {
      await launch.dispose();
      rethrow;
    }
  }
}
