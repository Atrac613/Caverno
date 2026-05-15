import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_m54_rollout_expansion_gate.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var exitPolicy = 'strict';
  var writeTemplateOnly = false;
  String? rolloutExpansionChecklistPath;
  String? m53PostReleaseGuardrailsPath;
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
      case '--rollout-expansion-checklist':
        index += 1;
        if (index >= args.length) {
          return _usageError('--rollout-expansion-checklist requires a value.');
        }
        rolloutExpansionChecklistPath = args[index];
      case '--m53-post-release-guardrails':
        index += 1;
        if (index >= args.length) {
          return _usageError('--m53-post-release-guardrails requires a value.');
        }
        m53PostReleaseGuardrailsPath = args[index];
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
          '${reportRoot.path}/macos_computer_use_m54_rollout_expansion_checklist_template.json',
    );
    templateFile.parent.createSync(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(m54RolloutExpansionChecklistTemplate()),
    );
    stdout.writeln(
      'M54 rollout expansion checklist template written to ${templateFile.path}',
    );
    return;
  }

  final inputs = readMacosComputerUseM54RolloutExpansionInputs(
    reportRoot: reportRoot,
    rolloutExpansionChecklistPath: rolloutExpansionChecklistPath,
    m53PostReleaseGuardrailsPath: m53PostReleaseGuardrailsPath,
  );
  final summary = buildMacosComputerUseM54RolloutExpansionSummary(inputs);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_m54_rollout_expansion_gate.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_m54_rollout_expansion_gate.md',
  );

  outputJson.parent.createSync(recursive: true);
  outputMarkdown.parent.createSync(recursive: true);
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('M54 rollout expansion gate written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_m54_rollout_expansion_gate.dart '
    '[--root path] [--rollout-expansion-checklist path] '
    '[--m53-post-release-guardrails path] [--write-template [path]] '
    '[--exit-policy strict|report-only] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}

bool _shouldExitFailure(
  MacosComputerUseM54RolloutExpansionSummary summary,
  String exitPolicy,
) {
  if (exitPolicy == 'report-only') {
    return false;
  }
  return !summary.ready;
}
