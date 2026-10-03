import 'package:flutter_test/flutter_test.dart';

import '../../tool/farm_completion_canary_evidence.dart';

void main() {
  final summary = <String, dynamic>{
    'result': 'passed',
    'passedCount': 3,
    'failedCount': 0,
    'skippedCount': 0,
    'mainReadiness': {'status': 'ready'},
  };
  Map<String, dynamic> prepared() => {
    'head': 'before',
    'indexFingerprint': 'native-index-hash',
    'fileFingerprints': {
      'fixture.py': 'code-hash',
      'roadmap.md': 'roadmap-hash',
    },
    'stagedPaths': ['fixture.py', 'roadmap.md'],
    'taskUnstagedPaths': [],
    'roadmapComplete': true,
  };
  Map<String, Map<String, dynamic>> records() => {
    for (final name in farmCompletionCases)
      name: {
        'scenario': name,
        'passed': true,
        'liveHttp': true,
        'liveMemoryCalls': 1,
        'callsByStage': {
          'implementation': 1,
          if (name != 'failedVerification') ...{
            'review': 1,
            'prepare': 1,
            'commit': 1,
          },
          if (name == 'reviewRepair') 'repair': 1,
        },
        'nativeExecutions': [
          {
            'arguments': {'workspace_command_containment': true},
          },
        ],
        'result': name == 'failedVerification' ? 'stopped' : 'committed',
        'initialHead': 'before',
        'finalHead': name == 'failedVerification' ? 'before' : 'after',
        'gitExecutions': [],
        'preparationSnapshots': name == 'failedVerification'
            ? []
            : [prepared(), prepared()],
        'commitPermit': name == 'failedVerification' ? null : prepared(),
        'oracle': {'exit_code': 0},
        'changedFiles': 'fixture.py\nroadmap.md',
        'finalStatus': ' M unrelated.txt',
        'faultPreludeUsed': name == 'reviewRepair',
        'phases': ['repair:running'],
      },
  };
  test('accepts all required live paths and scoped commits', () {
    expect(farmCompletionEvidenceGaps(summary, records()), isEmpty);
  });
  test('rejects missing or altered native preparation', () {
    for (final field in ['preparationSnapshots', 'commitPermit']) {
      final cases = records();
      cases['normal']!.remove(field);
      expect(
        farmCompletionEvidenceGaps(summary, cases),
        contains('normal lacks accepted native commit preparation evidence.'),
      );
    }
    final cases = records();
    (cases['normal']!['commitPermit'] as Map)['indexFingerprint'] = 'changed';
    expect(farmCompletionEvidenceGaps(summary, cases), isNotEmpty);
  });
  test('rejects commit execution during preparation', () {
    final cases = records();
    cases['normal']!['gitExecutions'] = [
      {
        'stage': 'prepare',
        'mutation': true,
        'arguments': {'command': 'commit -m "too early"'},
      },
    ];
    expect(
      farmCompletionEvidenceGaps(summary, cases),
      contains('normal executed Git mutations outside their task phase.'),
    );
  });
  test('rejects skipped tests and missing cases', () {
    expect(
      farmCompletionEvidenceGaps({
        ...summary,
        'skippedCount': 1,
      }, records()..remove('normal')),
      hasLength(2),
    );
  });
  test('rejects offline runs', () {
    final cases = records();
    cases['normal']!['liveHttp'] = false;
    expect(farmCompletionEvidenceGaps(summary, cases), isNotEmpty);
  });
  test('rejects a scripted review or repair route', () {
    final cases = records();
    cases['reviewRepair']!['callsByStage'] = {'implementation': 1, 'commit': 1};
    expect(
      farmCompletionEvidenceGaps(summary, cases),
      contains('reviewRepair lacks a required live model route.'),
    );
  });
  test('rejects missing containment evidence', () {
    final cases = records();
    cases['normal']!['nativeExecutions'] = [
      {'arguments': {}},
    ];
    expect(farmCompletionEvidenceGaps(summary, cases), isNotEmpty);
  });
  test('rejects a failed verification followed by Git writes', () {
    final cases = records();
    cases['failedVerification']!['gitExecutions'] = [
      {
        'arguments': {'command': 'add -- fixture.py roadmap.md'},
      },
    ];
    expect(
      farmCompletionEvidenceGaps(summary, cases),
      contains('failedVerification did not stop before Git mutation.'),
    );
  });
  test('rejects oracle failure and unrelated files in commit', () {
    final cases = records();
    cases['normal']!['oracle'] = {'exit_code': 1};
    cases['reviewRepair']!['changedFiles'] =
        'fixture.py\nroadmap.md\nunrelated.txt';
    expect(farmCompletionEvidenceGaps(summary, cases), hasLength(2));
  });
  test('malformed route and native records fail closed', () {
    final cases = records();
    cases['normal']!['callsByStage'] = 'invalid';
    cases['normal']!['nativeExecutions'] = [null];
    expect(farmCompletionEvidenceGaps(summary, cases), hasLength(2));
  });
  test('missing HEAD values cannot prove a safe stop', () {
    final cases = records();
    cases['failedVerification']!.remove('initialHead');
    cases['failedVerification']!.remove('finalHead');
    expect(
      farmCompletionEvidenceGaps(summary, cases),
      contains('failedVerification lacks actual HEAD evidence.'),
    );
  });
  test('downgrades readiness while preserving the Flutter result', () {
    final result = reconcileFarmCompletionEvidence(summary, {});
    expect(result['result'], 'failed');
    expect(result['flutterResult'], 'passed');
    expect((result['mainReadiness'] as Map)['status'], 'blocked');
  });
}
