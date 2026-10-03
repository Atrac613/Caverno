import 'dart:convert';
import 'dart:io';

const farmStepScenarioNames = [
  'environmentLookup',
  'missingExecution',
  'failedVerification',
  'unissuedCommand',
];

/// An absent/skipped case or a model-free run cannot qualify as live evidence.
List<String> farmStepEvidenceGaps(
  Map<String, dynamic> summary,
  Map<String, Map<String, dynamic>> cases,
) {
  final gaps = <String>[];
  if (summary['result'] != 'passed' ||
      summary['passedCount'] != 4 ||
      summary['skippedCount'] != 0 ||
      summary['failedCount'] != 0) {
    gaps.add('All four required live tests must pass without skips.');
  }
  for (final name in farmStepScenarioNames) {
    final record = cases[name];
    if (record == null ||
        record['scenario'] != name ||
        record['passed'] != true ||
        record['liveHttp'] != true ||
        record['faultPreludeUsed'] != true ||
        (record['livePrimaryCalls'] as num? ?? 0) < 1 ||
        (record['liveMemoryCalls'] as num? ?? 0) < 1) {
      gaps.add('$name lacks passing live execution and persistence evidence.');
    }
  }
  return gaps;
}

Map<String, dynamic> reconcileFarmStepEvidence(
  Map<String, dynamic> input,
  Map<String, Map<String, dynamic>> records,
) {
  final gaps = farmStepEvidenceGaps(input, records);
  return {
    ...input,
    'farmStepEvidence': {
      'passed': gaps.isEmpty,
      'requiredScenarios': farmStepScenarioNames,
      'gaps': gaps,
      'scope':
          'ChatNotifier intermediate project-task steps, memory persistence and next-subtask progression; final review and commit excluded',
    },
    if (gaps.isNotEmpty) ...{
      'flutterResult': input['result'],
      'result': 'failed',
      'mainReadiness': {
        ...?input['mainReadiness'] as Map<String, dynamic>?,
        'status': 'blocked',
        'note': gaps.join(' '),
      },
    },
  };
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/farm_step_canary_evidence.dart RUN_DIR',
    );
    exitCode = 64;
    return;
  }
  final run = args.single;
  final summaryFile = File('$run/canary_summary.json');
  if (!summaryFile.existsSync()) {
    stderr.writeln('Missing canary_summary.json');
    exitCode = 1;
    return;
  }
  final summary =
      jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>;
  final records = <String, Map<String, dynamic>>{};
  for (final name in farmStepScenarioNames) {
    final file = File('$run/fixtures/$name/evidence.json');
    if (file.existsSync()) {
      records[name] =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
  }
  final gaps = farmStepEvidenceGaps(summary, records);
  final reconciled = reconcileFarmStepEvidence(summary, records);
  await summaryFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(reconciled),
  );
  stdout.writeln(
    gaps.isEmpty
        ? 'All four Farm step live evidence records passed.'
        : gaps.join('\n'),
  );
  if (gaps.isNotEmpty) {
    final markdown = File('$run/canary_summary.md');
    if (markdown.existsSync()) {
      final original = await markdown.readAsString();
      await markdown.writeAsString(
        '# Farm Step Evidence Gate\n\nResult: failed. '
        'The Flutter-only summary below is superseded by missing live evidence.\n\n'
        '${gaps.map((gap) => '- $gap').join('\n')}\n\n$original',
      );
    }
    exitCode = 1;
  }
}
