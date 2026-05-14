import 'dart:io';

import '../integration_test/test_support/macos_computer_use_release_packaging.dart';

Future<void> main(List<String> args) async {
  var projectRootPath = Directory.current.path;
  var reportRootPath = 'build/integration_test_reports';
  String? outputJsonPath;
  String? outputMarkdownPath;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
      case '--project-root':
        index += 1;
        if (index >= args.length) {
          return _usageError('--project-root requires a value.');
        }
        projectRootPath = args[index];
      case '--root':
        index += 1;
        if (index >= args.length) {
          return _usageError('--root requires a value.');
        }
        reportRootPath = args[index];
      case '--output-json':
        index += 1;
        if (index >= args.length) {
          return _usageError('--output-json requires a value.');
        }
        outputJsonPath = args[index];
      case '--output-md':
        index += 1;
        if (index >= args.length) {
          return _usageError('--output-md requires a value.');
        }
        outputMarkdownPath = args[index];
      case '--help':
        _printUsage();
        return;
      default:
        return _usageError('Unknown option: $arg');
    }
  }

  final reportRoot = Directory(reportRootPath)..createSync(recursive: true);
  final report = buildMacosComputerUseReleasePackaging(
    projectRoot: Directory(projectRootPath),
  );
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_release_packaging.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_release_packaging.md',
  );

  await outputJson.writeAsString(encodeReleasePackagingJson(report));
  await outputMarkdown.writeAsString(report.toMarkdown());

  stdout.writeln('M33 release packaging report written');
  stdout.writeln('- JSON: ${outputJson.path}');
  stdout.writeln('- Markdown: ${outputMarkdown.path}');
  stdout.writeln('- Status: ${report.status}');
  stdout.writeln('- Ready: ${report.ready}');
  if (report.failedChecks.isNotEmpty) {
    stdout.writeln(
      '- Failed checks: ${report.failedChecks.map((check) => check.id).join(', ')}',
    );
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_release_packaging.dart '
    '[--project-root path] [--root path] [--output-json path] '
    '[--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}
