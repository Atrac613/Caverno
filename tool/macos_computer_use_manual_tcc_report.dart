import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_manual_tcc_report.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/macos_computer_use_manual_tcc_report.dart '
      '<user-produced-m8-report-or-summary.json> [--output-json path] [--output-md path]',
    );
    return;
  }

  final reportPath = args.first;
  String? outputJsonPath;
  String? outputMarkdownPath;

  for (var index = 1; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
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
      default:
        stderr.writeln('Unknown option: $arg');
        exitCode = 64;
        return;
    }
  }

  final reportFile = File(reportPath);
  if (!reportFile.existsSync()) {
    stderr.writeln('Report not found: ${reportFile.path}');
    exitCode = 66;
    return;
  }

  ManualTccReportSummary summary;
  try {
    summary = readManualTccReport(reportFile);
  } on FormatException catch (error) {
    stderr.writeln('Invalid manual TCC report: ${error.message}');
    exitCode = 65;
    return;
  }

  final outputJson = File(
    outputJsonPath ??
        '${reportFile.parent.path}/manual_tcc_report_summary.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportFile.parent.path}/manual_tcc_report_summary.md',
  );

  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('Manual TCC report summary written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (!summary.ready) {
    exitCode = 1;
  }
}
