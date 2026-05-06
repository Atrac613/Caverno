import 'dart:io';

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

  final reportRoot = Directory(reportRootPath);
  final index = await writeReadinessArtifactIndex(
    reportRoot,
    outputJsonPath: outputJsonPath,
    outputMarkdownPath: outputMarkdownPath,
  );
  stdout.writeln('Readiness artifact index written under ${reportRoot.path}');
  final rehearsal = index.mvpFinalSignoffRehearsal;
  stdout.writeln(
    'MVP final sign-off rehearsal: ${rehearsal.ready ? 'ready' : 'blocked'}',
  );
  stdout.writeln(
    'Missing MVP artifacts: ${rehearsal.missingArtifactIds.isEmpty ? 'none' : rehearsal.missingArtifactIds.join(', ')}',
  );
  if (rehearsal.finalAggregationCommand != null) {
    stdout.writeln('Final MVP aggregation command:');
    stdout.writeln(rehearsal.finalAggregationCommand);
  }
  if (rehearsal.nextActions.isNotEmpty) {
    stdout.writeln('MVP rehearsal next actions:');
    for (final action in rehearsal.nextActions) {
      stdout.writeln('- $action');
    }
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_readiness_artifact_index.dart '
    '[--root path] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}
