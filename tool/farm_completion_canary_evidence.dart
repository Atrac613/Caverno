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
            'prepare',
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
      final turns = _list(record['turns']);
      final turn = turns.length == 1 ? _map(turns.single) : const {};
      final status = _map(turn['taskStatus']);
      final reasons = _list(status['gaps']);
      if (turn['stage'] != 'implementation' ||
          turn['goalStatus'] != 'blocked' ||
          status['result_origin'] != 'harness' ||
          status['scope'] != 'implementation' ||
          status['status'] != 'blockerLogged' ||
          status['completionAccepted'] != false ||
          reasons.isEmpty ||
          reasons.any((reason) => reason is! String || reason.trim().isEmpty)) {
        gaps.add('$name lacks the recorded terminal blocker.');
      }
      if (record['result'] != 'stopped' ||
          record['finalHead'] != record['initialHead'] ||
          _list(
            record['gitExecutions'],
          ).any((entry) => _map(entry)['mutation'] != false) ||
          _count(counts['commit']) != 0 ||
          _count(counts['prepare']) != 0 ||
          _list(record['preparationSnapshots']).isNotEmpty ||
          record['commitPermit'] != null ||
          _list(record['commitChecks']).isNotEmpty ||
          _list(record['commitPermits']).isNotEmpty) {
        gaps.add('$name did not stop before Git mutation.');
      }
    } else {
      if (!_hasNativePreparation(record)) {
        gaps.add('$name lacks accepted native commit preparation evidence.');
      }
      if (!_hasBoundedCommitTurns(record)) {
        gaps.add('$name lacks safe, bounded commit phase evidence.');
      }
      if (_list(record['gitExecutions']).where((entry) {
            final execution = _map(entry);
            return execution['mutation'] == true &&
                _map(
                  execution['arguments'],
                )['command'].toString().startsWith('commit ');
          }).length !=
          1) {
        gaps.add('$name lacks exactly one native commit execution.');
      }
      if (_list(record['gitExecutions']).any((entry) {
        final execution = _map(entry);
        if (execution['mutation'] == false) return false;
        final command = _map(execution['arguments'])['command'];
        return command is! String ||
            !(execution['stage'] == 'prepare' &&
                    command.startsWith('add -- ') ||
                execution['stage'] == 'commit' &&
                    command.startsWith('commit -m '));
      })) {
        gaps.add('$name executed Git mutations outside their task phase.');
      }
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

bool _hasNativePreparation(Map<String, dynamic> record) {
  final snapshots = _list(record['preparationSnapshots']);
  if (snapshots.length < 2 || snapshots.length > 3) return false;
  final before = _map(snapshots.first);
  final after = _map(snapshots.last);
  final permit = _map(record['commitPermit']);
  const files = ['fixture.py', 'roadmap.md'];
  final hashes = _map(after['fileFingerprints']);
  final permitted = _map(permit['fileFingerprints']);
  return before['head'] == record['initialHead'] &&
      after['head'] == before['head'] &&
      permit['head'] == after['head'] &&
      after['indexFingerprint'] is String &&
      (after['indexFingerprint'] as String).isNotEmpty &&
      permit['indexFingerprint'] == after['indexFingerprint'] &&
      hashes.length == files.length &&
      permitted.length == files.length &&
      files.every(
        (file) =>
            hashes[file] is String &&
            (hashes[file] as String).isNotEmpty &&
            hashes[file] == permitted[file],
      ) &&
      _map(before['fileFingerprints'])['fixture.py'] == hashes['fixture.py'] &&
      _list(after['stagedPaths']).join(',') == files.join(',') &&
      _list(permit['stagedPaths']).join(',') == files.join(',') &&
      after['roadmapComplete'] == true &&
      permit['roadmapComplete'] == true &&
      after['taskUnstagedPaths'] is List &&
      _list(after['taskUnstagedPaths']).isEmpty &&
      permit['taskUnstagedPaths'] is List &&
      _list(permit['taskUnstagedPaths']).isEmpty;
}

bool _sameSnapshot(Object? left, Object? right) {
  final a = _map(left);
  final b = _map(right);
  final hashes = _map(a['fileFingerprints']);
  final other = _map(b['fileFingerprints']);
  return a['head'] is String &&
      a['head'] == b['head'] &&
      a['indexFingerprint'] is String &&
      a['indexFingerprint'] == b['indexFingerprint'] &&
      a['roadmapComplete'] == b['roadmapComplete'] &&
      hashes.length == 2 &&
      other.length == 2 &&
      hashes.keys.every((file) => hashes[file] == other[file]) &&
      ['stagedPaths', 'taskUnstagedPaths'].every(
        (key) =>
            a[key] is List &&
            b[key] is List &&
            _list(a[key]).join(',') == _list(b[key]).join(','),
      );
}

bool _hasBoundedCommitTurns(Map<String, dynamic> record) {
  final turns = _list(record['turns']);
  final preparing = turns
      .where((turn) => _map(turn)['stage'] == 'prepare')
      .toList();
  final committing = turns
      .where((turn) => _map(turn)['stage'] == 'commit')
      .toList();
  final snapshots = _list(record['preparationSnapshots']);
  final permits = _list(record['commitPermits']);
  final checks = _list(record['commitChecks']);
  if (preparing.isEmpty ||
      preparing.length > 2 ||
      committing.isEmpty ||
      committing.length > 2 ||
      snapshots.length != preparing.length + 1 ||
      checks.length != committing.length ||
      permits.length != committing.length) {
    return false;
  }
  for (final phase in [preparing, committing]) {
    if (phase.any((turn) {
      final evidence = _map(_map(turn)['phaseEvidence']);
      return _count(_map(turn)['livePrimaryCalls']) < 1 ||
          evidence['completedNormally'] != true ||
          evidence['failed'] != false;
    })) {
      return false;
    }
    if (phase.length == 2 &&
        _map(_map(phase.first)['phaseEvidence'])['mutationAttempted'] !=
            false) {
      return false;
    }
  }
  if (preparing.length == 2 && !_sameSnapshot(snapshots[0], snapshots[1])) {
    return false;
  }
  if (committing.length == 2 && !_sameSnapshot(permits.first, checks.first)) {
    return false;
  }
  return permits.every(
        (permit) => _sameSnapshot(permit, record['commitPermit']),
      ) &&
      _map(checks.last)['head'] == record['finalHead'];
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
          'Final implementation, dedicated review, repair, native preparation and local Git commit; UI and automatic scheduler excluded',
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
