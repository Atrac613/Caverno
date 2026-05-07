import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_release_readiness.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var historyLimit = 10;
  var refreshSafeInputs = false;
  var exitPolicy = 'strict';
  String? releaseReportPath;
  String? computerUseHistoryPath;
  String? desktopActionCanarySummaryPath;
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
      case '--desktop-action-canary-summary':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--desktop-action-canary-summary requires a value.',
          );
        }
        desktopActionCanarySummaryPath = args[index];
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
      case '--refresh-safe-inputs':
        refreshSafeInputs = true;
      case '--exit-policy':
        index += 1;
        if (index >= args.length) {
          return _usageError('--exit-policy requires a value.');
        }
        exitPolicy = args[index];
        if (exitPolicy != 'strict' && exitPolicy != 'ci') {
          return _usageError('--exit-policy must be strict or ci.');
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

  if (refreshSafeInputs) {
    final refreshExitCode = await _refreshSafeInputs(reportRoot);
    if (refreshExitCode != 0) {
      exitCode = refreshExitCode;
      return;
    }
  }

  final inputs = readReleaseReadinessInputs(
    reportRoot: reportRoot,
    releaseReportPath: releaseReportPath,
    computerUseHistoryPath: computerUseHistoryPath,
    desktopActionCanarySummaryPath: desktopActionCanarySummaryPath,
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

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_release_readiness.dart '
    '[--root path] [--release-report path] [--computer-use-history path] '
    '[--desktop-action-canary-summary path] [--manual-tcc-report path] '
    '[--llm-canary-summary path] '
    '[--history-limit count] [--refresh-safe-inputs] [--exit-policy strict|ci] '
    '[--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}

Future<int> _refreshSafeInputs(Directory reportRoot) async {
  reportRoot.createSync(recursive: true);
  final releaseReportPath =
      '${reportRoot.path}/macos_computer_use_release_artifact_signoff.json';
  stdout.writeln('Refreshing safe release readiness inputs');
  stdout.writeln('  M7 release artifact report: $releaseReportPath');
  final m7Result = await Process.run(
    'bash',
    <String>['tool/run_macos_computer_use_smoke_test.sh', '--m7-signoff'],
    environment: <String, String>{
      'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH': releaseReportPath,
    },
  );
  stdout.write(m7Result.stdout);
  stderr.write(m7Result.stderr);
  if (m7Result.exitCode != 0) {
    stderr.writeln('Safe refresh failed while generating the M7 report.');
    return m7Result.exitCode;
  }

  final historyResult = await Process.run('dart', <String>[
    'run',
    'tool/macos_computer_use_canary_history.dart',
    '--root',
    reportRoot.path,
  ]);
  stdout.write(historyResult.stdout);
  stderr.write(historyResult.stderr);
  if (historyResult.exitCode != 0) {
    stderr.writeln(
      'Safe refresh failed while generating Computer Use history.',
    );
    return historyResult.exitCode;
  }

  stdout.writeln(
    'Safe refresh complete. Manual TCC evidence remains user-operated.',
  );
  return 0;
}

bool _shouldExitFailure(ReleaseReadinessSummary summary, String exitPolicy) {
  if (summary.ready) {
    return false;
  }
  if (exitPolicy == 'ci') {
    return summary.blockedGates.any((gate) {
      return gate.id != 'manual_tcc' || gate.status != 'manual_required';
    });
  }
  return true;
}
