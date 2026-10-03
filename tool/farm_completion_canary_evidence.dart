import 'dart:convert';
import 'dart:io';

const farmCompletionCases = ['normal', 'reviewRepair', 'failedVerification'];

Map<dynamic, dynamic> _map(Object? value) => value is Map ? value : const {};
List<dynamic> _list(Object? value) => value is List ? value : const [];
num _count(Object? value) => value is num ? value : 0;

/// Require actual model calls on every route and Git/oracle evidence.
List<String> farmCompletionEvidenceGaps(
  Map<String, dynamic> summary,
  Map<String, Map<String, dynamic>> cases,
) {
  final gaps = <String>[];
  if (summary['result'] != 'passed' ||
      summary['passedCount'] != 3 ||
      summary['skippedCount'] != 0 ||
      summary['failedCount'] != 0) {
    gaps.add('All three required live tests must pass without skips.');
  }
  for (final name in farmCompletionCases) {
    final record = cases[name];
    if (record == null ||
        record['scenario'] != name ||
        record['passed'] != true ||
        record['liveHttp'] != true ||
        _count(record['liveMemoryCalls']) < 1) {
      gaps.add('$name lacks passing live persistence evidence.');
      continue;
    }
    if (record['initialHead'] is! String ||
        (record['initialHead'] as String).isEmpty ||
        record['finalHead'] is! String ||
        (record['finalHead'] as String).isEmpty) {
      gaps.add('$name lacks actual HEAD evidence.');
    }
    final counts = _map(record['callsByStage']);
    final failed = name == 'failedVerification';
    final required = failed
        ? ['implementation']
        : [
            if (name != 'reviewRepair') 'implementation',
            'review',
            if (name == 'reviewRepair') 'repair',
            'commit',
          ];
    if (required.any((stage) => _count(counts[stage]) < 1)) {
      gaps.add('$name lacks a required live model route.');
    }
    final natives = _list(record['nativeExecutions']);
    if (natives.isEmpty ||
        natives.any(
          (entry) =>
              _map(_map(entry)['arguments'])['workspace_command_containment'] !=
              true,
        )) {
      gaps.add('$name lacks native containment evidence.');
    }
    if (failed) {
      if (record['result'] != 'stopped' ||
          record['finalHead'] != record['initialHead'] ||
          _list(
            record['gitExecutions'],
          ).any((entry) => _map(entry)['mutation'] != false) ||
          _count(counts['commit']) != 0) {
        gaps.add('$name did not stop before Git mutation.');
      }
    } else {
      if (record['result'] != 'committed' ||
          record['finalHead'] == record['initialHead'] ||
          _map(record['oracle'])['exit_code'] != 0 ||
          record['finalStatus'] != ' M unrelated.txt' ||
          record['changedFiles'] != 'fixture.py\nroadmap.md') {
        gaps.add('$name lacks a verified, scoped commit.');
      }
      if (name == 'reviewRepair' &&
          (record['faultPreludeUsed'] != true ||
              !_list(record['phases']).contains('repair:running'))) {
        gaps.add('$name did not exercise repair.');
      }
    }
  }
  return gaps;
}

Map<String, dynamic> reconcileFarmCompletionEvidence(
  Map<String, dynamic> input,
  Map<String, Map<String, dynamic>> cases,
) {
  final gaps = farmCompletionEvidenceGaps(input, cases);
  return {
    ...input,
    'farmCompletionEvidence': {
      'passed': gaps.isEmpty,
      'requiredScenarios': farmCompletionCases,
      'gaps': gaps,
      'scope':
          'Final implementation, dedicated review, repair and native local Git commit; UI and automatic scheduler excluded',
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
      'Usage: dart run tool/farm_completion_canary_evidence.dart RUN_DIR',
    );
    exitCode = 64;
    return;
  }
  final file = File('${args.single}/canary_summary.json');
  if (!file.existsSync()) {
    stderr.writeln('Missing canary_summary.json');
    exitCode = 1;
    return;
  }
  final input = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final cases = <String, Map<String, dynamic>>{};
  for (final name in farmCompletionCases) {
    final evidence = File('${args.single}/fixtures/$name/evidence.json');
    if (evidence.existsSync()) {
      try {
        final decoded = jsonDecode(await evidence.readAsString());
        if (decoded is Map<String, dynamic>) {
          cases[name] = decoded;
        }
      } on FormatException {
        // An invalid artifact counts as missing evidence, never a ready run.
      }
    }
  }
  final result = reconcileFarmCompletionEvidence(input, cases);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  final gaps = (result['farmCompletionEvidence'] as Map)['gaps'] as List;
  stdout.writeln(
    gaps.isEmpty
        ? 'All three Farm completion live evidence records passed.'
        : gaps.join('\n'),
  );
  if (gaps.isNotEmpty) {
    final markdown = File('${args.single}/canary_summary.md');
    if (markdown.existsSync()) {
      await markdown.writeAsString(
        '# Farm Completion Evidence Gate\n\nResult: failed. The Flutter-only summary below is superseded.\n\n${gaps.map((gap) => '- $gap').join('\n')}\n\n${await markdown.readAsString()}',
      );
    }
    exitCode = 1;
  }
}
