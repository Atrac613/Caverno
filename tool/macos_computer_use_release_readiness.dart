import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_release_readiness.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var historyLimit = 10;
  String? releaseReportPath;
  String? computerUseHistoryPath;
  String? manualTccReportPath;
  String? llmCanarySummaryPath;
  String? outputJsonPath;
  String? outputMarkdownPath;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
      case '--root':
        index += 1;
        if (index >= args.length) {
          return _usageError('--root requires a value.');
        }
        reportRootPath = args[index];
      case '--release-report':
        index += 1;
        if (index >= args.length) {
          return _usageError('--release-report requires a value.');
        }
        releaseReportPath = args[index];
      case '--computer-use-history':
        index += 1;
        if (index >= args.length) {
          return _usageError('--computer-use-history requires a value.');
        }
        computerUseHistoryPath = args[index];
      case '--manual-tcc-report':
        index += 1;
        if (index >= args.length) {
          return _usageError('--manual-tcc-report requires a value.');
        }
        manualTccReportPath = args[index];
      case '--llm-canary-summary':
        index += 1;
        if (index >= args.length) {
          return _usageError('--llm-canary-summary requires a value.');
        }
        llmCanarySummaryPath = args[index];
      case '--history-limit':
        index += 1;
        if (index >= args.length) {
          return _usageError('--history-limit requires a value.');
        }
        historyLimit = int.tryParse(args[index]) ?? 0;
        if (historyLimit < 1) {
          return _usageError('--history-limit must be a positive integer.');
        }
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

  final reportRoot = Directory(reportRootPath);
  if (!reportRoot.existsSync()) {
    stderr.writeln('Report root not found: ${reportRoot.path}');
    exitCode = 66;
    return;
  }

  final inputs = readReleaseReadinessInputs(
    reportRoot: reportRoot,
    releaseReportPath: releaseReportPath,
    computerUseHistoryPath: computerUseHistoryPath,
    manualTccReportPath: manualTccReportPath,
    llmCanarySummaryPath: llmCanarySummaryPath,
    computerUseHistoryLimit: historyLimit,
  );
  final summary = buildReleaseReadinessSummary(inputs);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_release_readiness.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_release_readiness.md',
  );

  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('Release readiness written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (!summary.ready) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_release_readiness.dart '
    '[--root path] [--release-report path] [--computer-use-history path] '
    '[--manual-tcc-report path] [--llm-canary-summary path] '
    '[--history-limit count] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}
