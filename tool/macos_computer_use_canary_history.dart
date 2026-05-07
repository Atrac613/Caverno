import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_canary_history.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var limit = 10;
  String? outputJsonPath;
  String? outputMarkdownPath;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
      case '--root':
        index += 1;
        if (index >= args.length) {
          stderr.writeln('--root requires a value.');
          exitCode = 64;
          return;
        }
        reportRootPath = args[index];
      case '--limit':
        index += 1;
        if (index >= args.length) {
          stderr.writeln('--limit requires a value.');
          exitCode = 64;
          return;
        }
        limit = int.tryParse(args[index]) ?? 0;
        if (limit < 1) {
          stderr.writeln('--limit must be a positive integer.');
          exitCode = 64;
          return;
        }
      case '--output-json':
        index += 1;
        if (index >= args.length) {
          stderr.writeln('--output-json requires a value.');
          exitCode = 64;
          return;
        }
        outputJsonPath = args[index];
      case '--output-md':
        index += 1;
        if (index >= args.length) {
          stderr.writeln('--output-md requires a value.');
          exitCode = 64;
          return;
        }
        outputMarkdownPath = args[index];
      case '--help':
        stdout.writeln(
          'Usage: dart run tool/macos_computer_use_canary_history.dart '
          '[--root path] [--limit count] [--output-json path] [--output-md path]',
        );
        return;
      default:
        stderr.writeln('Unknown option: $arg');
        exitCode = 64;
        return;
    }
  }

  final reportRoot = Directory(reportRootPath);
  if (!reportRoot.existsSync()) {
    stderr.writeln('Report root not found: ${reportRoot.path}');
    exitCode = 66;
    return;
  }

  final history = buildComputerUseCanaryHistory(reportRoot, limit: limit);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_canary_history.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_canary_history.md',
  );

  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(history.toJson()),
  );
  await outputMarkdown.writeAsString(history.toMarkdown());

  stdout.writeln('Computer Use canary history written to ${outputJson.path}');
  stdout.writeln(history.toMarkdown());

  if (history.latest != null && history.latest!.stable == false) {
    exitCode = 1;
  }
}
