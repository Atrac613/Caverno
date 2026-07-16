import 'dart:io';

Future<ProcessResult> runDartTool(String toolPath, List<String> arguments) {
  return Process.run(dartToolExecutable(), <String>[
    toolPath,
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

String dartToolExecutable() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final flutterRoots = [
    Directory.current.uri.resolve('.fvm/flutter_sdk/').toFilePath(),
    if ((Platform.environment['FLUTTER_ROOT'] ?? '').trim().isNotEmpty)
      Platform.environment['FLUTTER_ROOT']!.trim(),
  ];

  for (final flutterRoot in flutterRoots) {
    final candidate = File.fromUri(
      Directory(
        flutterRoot,
      ).uri.resolve('bin/cache/dart-sdk/bin/$executableName'),
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }

  return executableName;
}
