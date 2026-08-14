import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/flutter_test_failure_set.dart';

void main() {
  test('normalizes worktree paths and reports candidate-only failures', () {
    final base = parseFlutterTestFailureSet(
      _log(
        root: '/tmp/main',
        tests: const [('shared failure', 'failure')],
        success: false,
      ),
    );
    final candidate = parseFlutterTestFailureSet(
      _log(
        root: '/tmp/feature',
        tests: const [
          ('shared failure', 'failure'),
          ('new regression', 'failure'),
          ('passing test', 'success'),
        ],
        success: false,
      ),
    );

    final comparison = compareFlutterTestFailureSets(base, candidate);

    expect(comparison.isComplete, isTrue);
    expect(comparison.shared, ['test/example_test.dart::shared failure']);
    expect(comparison.baseOnly, isEmpty);
    expect(comparison.candidateOnly, [
      'test/example_test.dart::new regression',
    ]);
  });

  test('retains hidden loading failures and detects incomplete logs', () {
    final failure = parseFlutterTestFailureSet(
      _log(
        root: r'C:\main',
        tests: const [(r'loading C:\main\test\broken_test.dart', 'failure')],
        success: false,
      ),
    );
    final incomplete = parseFlutterTestFailureSet(
      '${jsonEncode({'type': 'start'})}\nnot-json\n',
    );

    expect(failure.failures, {
      'test/example_test.dart::loading test/broken_test.dart',
    });
    expect(failure.isComplete, isTrue);
    expect(incomplete.isComplete, isFalse);
    expect(incomplete.malformedLineCount, 1);
  });
}

String _log({
  required String root,
  required List<(String, String)> tests,
  required bool success,
}) {
  final events = <Map<String, Object?>>[
    {'type': 'start'},
    {
      'type': 'suite',
      'suite': {'id': 0, 'path': '$root/test/example_test.dart'},
    },
  ];
  for (var index = 0; index < tests.length; index += 1) {
    final id = index + 1;
    events.add({
      'type': 'testStart',
      'test': {'id': id, 'name': tests[index].$1, 'suiteID': 0, 'url': null},
    });
    events.add({
      'type': 'testDone',
      'testID': id,
      'result': tests[index].$2,
      'hidden': tests[index].$1.startsWith('loading '),
    });
  }
  events.add({'type': 'done', 'success': success});
  return events.map(jsonEncode).join('\n');
}
