import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/macos_computer_use_m53_post_release_guardrails.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  var exitPolicy = 'strict';
  var writeTemplateOnly = false;
  String? postReleaseChecklistPath;
  String? m52ProductReleaseRolloutPath;
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
      case '--post-release-checklist':
        index += 1;
        if (index >= args.length) {
          return _usageError('--post-release-checklist requires a value.');
        }
        postReleaseChecklistPath = args[index];
      case '--m52-product-release-rollout':
        index += 1;
        if (index >= args.length) {
          return _usageError('--m52-product-release-rollout requires a value.');
        }
        m52ProductReleaseRolloutPath = args[index];
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
          '${reportRoot.path}/macos_computer_use_m53_post_release_checklist_template.json',
    );
    templateFile.parent.createSync(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(m53PostReleaseChecklistTemplate()),
    );
    stdout.writeln(
      'M53 post-release checklist template written to ${templateFile.path}',
    );
    return;
  }

  final inputs = readMacosComputerUseM53PostReleaseInputs(
    reportRoot: reportRoot,
    postReleaseChecklistPath: postReleaseChecklistPath,
    m52ProductReleaseRolloutPath: m52ProductReleaseRolloutPath,
  );
  final summary = buildMacosComputerUseM53PostReleaseSummary(inputs);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_m53_post_release_guardrails.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_m53_post_release_guardrails.md',
  );

  outputJson.parent.createSync(recursive: true);
  outputMarkdown.parent.createSync(recursive: true);
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  await outputMarkdown.writeAsString(summary.toMarkdown());

  stdout.writeln('M53 post-release guardrails written to ${outputJson.path}');
  stdout.writeln(summary.toMarkdown());

  if (_shouldExitFailure(summary, exitPolicy)) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_m53_post_release_guardrails.dart '
    '[--root path] [--post-release-checklist path] '
    '[--m52-product-release-rollout path] [--write-template [path]] '
    '[--exit-policy strict|report-only] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}

bool _shouldExitFailure(
  MacosComputerUseM53PostReleaseSummary summary,
  String exitPolicy,
) {
  if (exitPolicy == 'report-only') {
    return false;
  }
  return !summary.ready;
}
