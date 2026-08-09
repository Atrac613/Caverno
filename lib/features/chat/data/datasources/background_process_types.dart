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
