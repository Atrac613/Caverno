import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_xpc_timing_report.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    _printUsage();
    return;
  }

  final inputPath = args.first;
  String? outputJsonPath;
  String? outputMarkdownPath;

  for (var index = 1; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
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
      default:
        return _usageError('Unknown option: $arg');
    }
  }

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Diagnostics file not found: ${inputFile.path}');
    exitCode = 66;
    return;
  }

  XpcTimingReportSummary summary;
  try {
    summary = readXpcTimingReport(inputFile);
  } on FormatException catch (error) {
    stderr.writeln('Invalid diagnostics file: ${error.message}');
    exitCode = 65;
    return;
  }

  final outputJson = File(
    outputJsonPath ?? '${inputFile.parent.path}/xpc_timing_report_summary.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${inputFile.parent.path}/xpc_timing_report_summary.md',
  );

  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('XPC timing report summary written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (!summary.ready) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_xpc_timing_report.dart '
    '<diagnostics.json> [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}
