import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_setup.dart';

import '../integration_test/test_support/macos_computer_use_readiness_artifact_index.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
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
  final navigator = buildReadinessNextStepNavigator(reportRoot);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/${MacosComputerUseMvpGuidance.nextStepNavigatorJsonFile}',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/${MacosComputerUseMvpGuidance.nextStepNavigatorMarkdownFile}',
  );
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(navigator.toJson()),
  );
  await outputMarkdown.writeAsString(navigator.toMarkdown());

  final recommendation = navigator.recommendation;
  stdout.writeln('M31 next-step navigator written under ${reportRoot.path}');
  stdout.writeln('- JSON: ${outputJson.path}');
  stdout.writeln('- Markdown: ${outputMarkdown.path}');
  stdout.writeln('Next step status: ${navigator.status}');
  stdout.writeln('Priority: ${recommendation.priority}');
  stdout.writeln('Artifact: ${recommendation.artifactId}');
  stdout.writeln('Evidence path: ${recommendation.evidencePath}');
  stdout.writeln('Next action: ${recommendation.nextAction}');
  if (recommendation.recommendedCommand != null) {
    stdout.writeln('Recommended next command:');
    stdout.writeln(recommendation.recommendedCommand);
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_next_step_navigator.dart '
    '[--root path] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}
