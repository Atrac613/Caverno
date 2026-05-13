import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_beta_signoff.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var exitPolicy = 'strict';
  var writeTemplateOnly = false;
  String? manualChecklistPath;
  String? m36LiveLlmEvalSummaryPath;
  String? m23CycleOutcomeHandoffPath;
  String? installMigrationDiagnosticsPath;
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
      case '--manual-beta-checklist':
        index += 1;
        if (index >= args.length) {
          return _usageError('--manual-beta-checklist requires a value.');
        }
        manualChecklistPath = args[index];
      case '--m36-live-llm-eval':
        index += 1;
        if (index >= args.length) {
          return _usageError('--m36-live-llm-eval requires a value.');
        }
        m36LiveLlmEvalSummaryPath = args[index];
      case '--m23-cycle-outcome':
        index += 1;
        if (index >= args.length) {
          return _usageError('--m23-cycle-outcome requires a value.');
        }
        m23CycleOutcomeHandoffPath = args[index];
      case '--install-migration-diagnostics':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--install-migration-diagnostics requires a value.',
          );
        }
        installMigrationDiagnosticsPath = args[index];
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

  final reportRoot = Directory(reportRootPath);
  reportRoot.createSync(recursive: true);

  if (writeTemplateOnly) {
    final templateFile = File(
      templatePath ??
          '${reportRoot.path}/macos_computer_use_m39_manual_beta_checklist_template.json',
    );
    templateFile.parent.createSync(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manualChecklistTemplate()),
    );
    stdout.writeln(
      'M39 manual beta checklist template written to ${templateFile.path}',
    );
    return;
  }

  final inputs = readMacosComputerUseBetaSignoffInputs(
    reportRoot: reportRoot,
    manualChecklistPath: manualChecklistPath,
    m36LiveLlmEvalSummaryPath: m36LiveLlmEvalSummaryPath,
    m23CycleOutcomeHandoffPath: m23CycleOutcomeHandoffPath,
    installMigrationDiagnosticsPath: installMigrationDiagnosticsPath,
  );
  final summary = buildMacosComputerUseBetaSignoffSummary(inputs);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_m39_beta_signoff.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_m39_beta_signoff.md',
  );

  outputJson.parent.createSync(recursive: true);
  outputMarkdown.parent.createSync(recursive: true);
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('M39 beta sign-off written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_beta_signoff.dart '
    '[--root path] [--manual-beta-checklist path] '
    '[--m36-live-llm-eval path] [--m23-cycle-outcome path] '
    '[--install-migration-diagnostics path] '
    '[--write-template [path]] [--exit-policy strict|report-only] '
    '[--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}

bool _shouldExitFailure(
  MacosComputerUseBetaSignoffSummary summary,
  String exitPolicy,
) {
  if (exitPolicy == 'report-only') {
    return false;
  }
  return !summary.ready;
}
