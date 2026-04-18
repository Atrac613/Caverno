import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/plan_mode_canary_summary.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Pass the canary report directory path.');
    exitCode = 64;
    return;
  }

  final reportDirectory = Directory(args.first);
  if (!reportDirectory.existsSync()) {
    stderr.writeln('Directory not found: ${reportDirectory.path}');
    exitCode = 66;
    return;
  }

  final reportFiles =
      reportDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('_suite_report.json'))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  final reportContents = <String>[];
  for (final file in reportFiles) {
    reportContents.add(await file.readAsString());
  }
  final summary = buildPlanModeCanarySummary(
    decodeCanarySuiteReports(reportContents),
  );

  final jsonFile = File('${reportDirectory.path}/canary_summary.json');
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary.toJson()),
  );
  final markdownFile = File('${reportDirectory.path}/canary_summary.md');
  await markdownFile.writeAsString(summary.toMarkdown());

  stdout.writeln('Canary summary written to ${jsonFile.path}');
  stdout.writeln(summary.toMarkdown());

  if (summary.failedCount > 0) {
    exitCode = 1;
  }
}
