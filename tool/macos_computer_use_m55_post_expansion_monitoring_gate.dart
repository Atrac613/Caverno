import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_m55_post_expansion_monitoring_gate.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var exitPolicy = 'strict';
  var writeTemplateOnly = false;
  String? postExpansionMonitoringChecklistPath;
  String? m54RolloutExpansionGatePath;
  String? outputJsonPath;
  String? outputMarkdownPath;
  String? templatePath;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
      case '--root':
        index += 1;
        if (index >= args.length) {
          return _usageError('--root requires a value.');
        }
        reportRootPath = args[index];
      case '--post-expansion-monitoring-checklist':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--post-expansion-monitoring-checklist requires a value.',
          );
        }
        postExpansionMonitoringChecklistPath = args[index];
      case '--m54-rollout-expansion-gate':
        index += 1;
        if (index >= args.length) {
          return _usageError('--m54-rollout-expansion-gate requires a value.');
        }
        m54RolloutExpansionGatePath = args[index];
      case '--write-template':
        writeTemplateOnly = true;
        if (index + 1 < args.length && !args[index + 1].startsWith('--')) {
          index += 1;
          templatePath = args[index];
        }
      case '--exit-policy':
        index += 1;
        if (index >= args.length) {
          return _usageError('--exit-policy requires a value.');
        }
        exitPolicy = args[index];
        if (exitPolicy != 'strict' && exitPolicy != 'report-only') {
          return _usageError('--exit-policy must be strict or report-only.');
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

  final reportRoot = Directory(reportRootPath)..createSync(recursive: true);

  if (writeTemplateOnly) {
    final templateFile = File(
      templatePath ??
          '${reportRoot.path}/macos_computer_use_m55_post_expansion_monitoring_checklist_template.json',
    );
    templateFile.parent.createSync(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(m55PostExpansionMonitoringChecklistTemplate()),
    );
    stdout.writeln(
      'M55 post-expansion monitoring checklist template written to ${templateFile.path}',
    );
    return;
  }

  final inputs = readMacosComputerUseM55PostExpansionMonitoringInputs(
    reportRoot: reportRoot,
    postExpansionMonitoringChecklistPath: postExpansionMonitoringChecklistPath,
    m54RolloutExpansionGatePath: m54RolloutExpansionGatePath,
  );
  final summary = buildMacosComputerUseM55PostExpansionMonitoringSummary(
    inputs,
  );
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_m55_post_expansion_monitoring_gate.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_m55_post_expansion_monitoring_gate.md',
  );

  outputJson.parent.createSync(recursive: true);
  outputMarkdown.parent.createSync(recursive: true);
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln(
    'M55 post-expansion monitoring gate written to ${outputJson.path}',
  );
  stdout.writeln(summary.toMarkdown());

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_m55_post_expansion_monitoring_gate.dart '
    '[--root path] [--post-expansion-monitoring-checklist path] '
    '[--m54-rollout-expansion-gate path] [--write-template [path]] '
    '[--exit-policy strict|report-only] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}

bool _shouldExitFailure(
  MacosComputerUseM55PostExpansionMonitoringSummary summary,
  String exitPolicy,
) {
  if (exitPolicy == 'report-only') {
    return false;
  }
  return !summary.ready;
}
