import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_signed_beta_gate.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var exitPolicy = 'strict';
  var writeTemplateOnly = false;
  String? signedBetaChecklistPath;
  String? releaseArtifactReportPath;
  String? releasePackagingReportPath;
  String? m46ElementGroundedLlmEvalSummaryPath;
  String? m48UserOperatedActionPilotPath;
  String? m49PrivacyAuditReleasePackPath;
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
      case '--signed-beta-checklist':
        index += 1;
        if (index >= args.length) {
          return _usageError('--signed-beta-checklist requires a value.');
        }
        signedBetaChecklistPath = args[index];
      case '--release-artifact-report':
        index += 1;
        if (index >= args.length) {
          return _usageError('--release-artifact-report requires a value.');
        }
        releaseArtifactReportPath = args[index];
      case '--release-packaging-report':
        index += 1;
        if (index >= args.length) {
          return _usageError('--release-packaging-report requires a value.');
        }
        releasePackagingReportPath = args[index];
      case '--m46-element-grounded-llm-eval':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--m46-element-grounded-llm-eval requires a value.',
          );
        }
        m46ElementGroundedLlmEvalSummaryPath = args[index];
      case '--m48-user-operated-action-pilot':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--m48-user-operated-action-pilot requires a value.',
          );
        }
        m48UserOperatedActionPilotPath = args[index];
      case '--m49-privacy-audit-release-pack':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--m49-privacy-audit-release-pack requires a value.',
          );
        }
        m49PrivacyAuditReleasePackPath = args[index];
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
          '${reportRoot.path}/macos_computer_use_m50_signed_beta_checklist_template.json',
    );
    templateFile.parent.createSync(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(signedBetaChecklistTemplate()),
    );
    stdout.writeln(
      'M50 signed beta checklist template written to ${templateFile.path}',
    );
    return;
  }

  final inputs = readMacosComputerUseSignedBetaInputs(
    reportRoot: reportRoot,
    signedBetaChecklistPath: signedBetaChecklistPath,
    releaseArtifactReportPath: releaseArtifactReportPath,
    releasePackagingReportPath: releasePackagingReportPath,
    m46ElementGroundedLlmEvalSummaryPath: m46ElementGroundedLlmEvalSummaryPath,
    m48UserOperatedActionPilotPath: m48UserOperatedActionPilotPath,
    m49PrivacyAuditReleasePackPath: m49PrivacyAuditReleasePackPath,
  );
  final summary = buildMacosComputerUseSignedBetaSummary(inputs);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_m50_signed_beta_gate.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_m50_signed_beta_gate.md',
  );

  outputJson.parent.createSync(recursive: true);
  outputMarkdown.parent.createSync(recursive: true);
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('M50 signed beta gate written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_signed_beta_gate.dart '
    '[--root path] [--signed-beta-checklist path] '
    '[--release-artifact-report path] [--release-packaging-report path] '
    '[--m46-element-grounded-llm-eval path] '
    '[--m48-user-operated-action-pilot path] '
    '[--m49-privacy-audit-release-pack path] '
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
  MacosComputerUseSignedBetaSummary summary,
  String exitPolicy,
) {
  if (exitPolicy == 'report-only') {
    return false;
  }
  return !summary.ready;
}
