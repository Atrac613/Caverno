import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_m56_rollout_decision_handoff_gate.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var exitPolicy = 'strict';
  var writeTemplateOnly = false;
  String? rolloutDecisionHandoffChecklistPath;
  String? m55PostExpansionMonitoringGatePath;
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
      case '--rollout-decision-handoff-checklist':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--rollout-decision-handoff-checklist requires a value.',
          );
        }
        rolloutDecisionHandoffChecklistPath = args[index];
      case '--m55-post-expansion-monitoring-gate':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--m55-post-expansion-monitoring-gate requires a value.',
          );
        }
        m55PostExpansionMonitoringGatePath = args[index];
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
          '${reportRoot.path}/macos_computer_use_m56_rollout_decision_handoff_checklist_template.json',
    );
    templateFile.parent.createSync(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(m56RolloutDecisionHandoffChecklistTemplate()),
    );
    stdout.writeln(
      'M56 rollout decision handoff checklist template written to ${templateFile.path}',
    );
    return;
  }

  final inputs = readMacosComputerUseM56RolloutDecisionHandoffInputs(
    reportRoot: reportRoot,
    rolloutDecisionHandoffChecklistPath: rolloutDecisionHandoffChecklistPath,
    m55PostExpansionMonitoringGatePath: m55PostExpansionMonitoringGatePath,
  );
  final summary = buildMacosComputerUseM56RolloutDecisionHandoffSummary(inputs);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_m56_rollout_decision_handoff_gate.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_m56_rollout_decision_handoff_gate.md',
  );

  outputJson.parent.createSync(recursive: true);
  outputMarkdown.parent.createSync(recursive: true);
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln(
    'M56 rollout decision handoff gate written to ${outputJson.path}',
  );
  stdout.writeln(summary.toMarkdown());

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_m56_rollout_decision_handoff_gate.dart '
    '[--root path] [--rollout-decision-handoff-checklist path] '
    '[--m55-post-expansion-monitoring-gate path] [--write-template [path]] '
    '[--exit-policy strict|report-only] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}

bool _shouldExitFailure(
  MacosComputerUseM56RolloutDecisionHandoffSummary summary,
  String exitPolicy,
) {
  if (exitPolicy == 'report-only') {
    return false;
  }
  return !summary.ready;
}
