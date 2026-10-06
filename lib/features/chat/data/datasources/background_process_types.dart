import 'dart:io';

typedef BackgroundProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

typedef BackgroundProcessRuntimeIdentity = ({
  String jobId,
  int processId,
  bool isRunning,
});

Future<Process> startBackgroundProcess(
  String executable,
  List<String> arguments,
  String workingDirectory,
) => Process.start(executable, arguments, workingDirectory: workingDirectory);

/// Reports a background job that has exited, for per-conversation work time.
///
/// Fires once per job, for every exit: a clean finish, a failure, or a kill
/// from `process_cancel`, the sidebar, or owner retirement.
typedef BackgroundProcessFinishedCallback =
    void Function({
      required String conversationId,
      required int elapsedMs,
      int? exitCode,
    });
