import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_m51_production_launch_gate.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var exitPolicy = 'strict';
  var writeTemplateOnly = false;
  String? launchChecklistPath;
  String? releaseArtifactReportPath;
  String? releasePackagingReportPath;
  String? manualTccReportPath;
  String? m46ElementGroundedLlmEvalSummaryPath;
  String? m49PrivacyAuditReleasePackPath;
  String? m50SignedBetaGatePath;
  String? diagnosticsPath;
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
      case '--launch-checklist':
        index += 1;
        if (index >= args.length) {
          return _usageError('--launch-checklist requires a value.');
        }
        launchChecklistPath = args[index];
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
      case '--manual-tcc-report':
        index += 1;
        if (index >= args.length) {
          return _usageError('--manual-tcc-report requires a value.');
        }
        manualTccReportPath = args[index];
      case '--m46-element-grounded-llm-eval':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--m46-element-grounded-llm-eval requires a value.',
          );
        }
        m46ElementGroundedLlmEvalSummaryPath = args[index];
      case '--m49-privacy-audit-release-pack':
        index += 1;
        if (index >= args.length) {
          return _usageError(
            '--m49-privacy-audit-release-pack requires a value.',
          );
        }
        m49PrivacyAuditReleasePackPath = args[index];
      case '--m50-signed-beta-gate':
        index += 1;
        if (index >= args.length) {
          return _usageError('--m50-signed-beta-gate requires a value.');
        }
        m50SignedBetaGatePath = args[index];
      case '--diagnostics':
        index += 1;
        if (index >= args.length) {
          return _usageError('--diagnostics requires a value.');
        }
        diagnosticsPath = args[index];
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
          '${reportRoot.path}/macos_computer_use_m51_launch_checklist_template.json',
    );
    templateFile.parent.createSync(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(m51LaunchChecklistTemplate()),
    );
    stdout.writeln(
      'M51 launch checklist template written to ${templateFile.path}',
    );
    return;
  }

  final inputs = readMacosComputerUseM51ProductionLaunchInputs(
    reportRoot: reportRoot,
    launchChecklistPath: launchChecklistPath,
    releaseArtifactReportPath: releaseArtifactReportPath,
    releasePackagingReportPath: releasePackagingReportPath,
    manualTccReportPath: manualTccReportPath,
    m46ElementGroundedLlmEvalSummaryPath: m46ElementGroundedLlmEvalSummaryPath,
    m49PrivacyAuditReleasePackPath: m49PrivacyAuditReleasePackPath,
    m50SignedBetaGatePath: m50SignedBetaGatePath,
    diagnosticsPath: diagnosticsPath,
  );
  final summary = buildMacosComputerUseM51ProductionLaunchSummary(inputs);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_m51_production_launch_gate.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_m51_production_launch_gate.md',
  );

  outputJson.parent.createSync(recursive: true);
  outputMarkdown.parent.createSync(recursive: true);
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('M51 production launch gate written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_m51_production_launch_gate.dart '
    '[--root path] [--launch-checklist path] '
    '[--release-artifact-report path] [--release-packaging-report path] '
    '[--manual-tcc-report path] [--m46-element-grounded-llm-eval path] '
    '[--m49-privacy-audit-release-pack path] [--m50-signed-beta-gate path] '
    '[--diagnostics path] '
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
  MacosComputerUseM51ProductionLaunchSummary summary,
  String exitPolicy,
) {
  if (exitPolicy == 'report-only') {
    return false;
  }
  return !summary.ready;
}
