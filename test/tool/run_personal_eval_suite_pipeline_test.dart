import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('personal eval suite pipeline runner', () {
    test('adds default output directory and label', () async {
      final fixture = _ScriptFixture.create();

      final result = await fixture.runRunner(
        args: const [
          '--manifest',
          'case-a.json',
          '--incumbent-label',
          'incumbent',
          '--candidate-label',
          'candidate',
          '--incumbent-case-log',
          'case-a=incumbent.jsonl',
          '--candidate-case-log',
          'case-a=candidate.jsonl',
          '--incumbent-verification-result',
          'case-a=passed',
          '--candidate-verification-result',
          'case-a=passed',
        ],
        environment: {'CAVERNO_PERSONAL_EVAL_SUITE_LABEL': 'candidate-rollout'},
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Running personal eval suite pipeline'));
      expect(result.stdout, contains('Report label: candidate-rollout'));
      expect(result.stdout, contains(fixture.outDir.path));
      expect(fixture.outDir.existsSync(), isTrue);
      expect(
        fixture.loggedArgs(),
        containsAllInOrder([
          'run',
          fixture.pipelineHelper.path,
          '--manifest',
          'case-a.json',
          '--out-dir',
          fixture.outDir.path,
          '--label',
          'candidate-rollout',
        ]),
      );
    });

    test('keeps explicit output directory and label', () async {
      final fixture = _ScriptFixture.create();
      final explicitOutDir = Directory('${fixture.root.path}/explicit-output');

      final result = await fixture.runRunner(
        args: [
          '--manifest=case-a.json',
          '--incumbent-label',
          'incumbent',
          '--candidate-label',
          'candidate',
          '--incumbent-case-log',
          'case-a=incumbent.jsonl',
          '--candidate-case-log',
          'case-a=candidate.jsonl',
          '--incumbent-verification-result',
          'case-a=passed',
          '--candidate-verification-result',
          'case-a=passed',
          '--out-dir=${explicitOutDir.path}',
          '--label',
          'explicit-label',
        ],
        environment: {'CAVERNO_PERSONAL_EVAL_SUITE_LABEL': 'default-label'},
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains(explicitOutDir.path));
      expect(result.stdout, contains('Report label: explicit-label'));
      expect(explicitOutDir.existsSync(), isTrue);
      final args = fixture.loggedArgs();
      expect(args, contains('--out-dir=${explicitOutDir.path}'));
      expect(args, containsAllInOrder(['--label', 'explicit-label']));
      expect(args, isNot(contains(fixture.outDir.path)));
      expect(args, isNot(contains('default-label')));
    });

    test(
      'prints usage without running the pipeline when arguments are empty',
      () async {
        final fixture = _ScriptFixture.create();

        final result = await fixture.runRunner(args: const []);

        expect(result.exitCode, 64);
        expect(result.stderr, contains('Usage:'));
        expect(fixture.dartLog.existsSync(), isFalse);
      },
    );
  });
}

final class _ScriptFixture {
  _ScriptFixture._({
    required this.root,
    required this.runnerScript,
    required this.fakeDart,
    required this.pipelineHelper,
    required this.dartLog,
    required this.outDir,
  });

  final Directory root;
  final File runnerScript;
  final File fakeDart;
  final File pipelineHelper;
  final File dartLog;
  final Directory outDir;

  static _ScriptFixture create() {
    final root = Directory.systemTemp.createTempSync(
      'personal-eval-suite-runner-test-',
    );
    final fixture = _ScriptFixture._(
      root: root,
      runnerScript: File(
        '${Directory.current.path}/tool/run_personal_eval_suite_pipeline.sh',
      ),
      fakeDart: File('${root.path}/fake-dart.sh'),
      pipelineHelper: File('${root.path}/personal_eval_suite_pipeline.dart'),
      dartLog: File('${root.path}/dart_args.log'),
      outDir: Directory('${root.path}/reports'),
    );
    addTearDown(() => root.deleteSync(recursive: true));
    fixture._writeExecutable(fixture.fakeDart, '''
#!/usr/bin/env bash
{
  for arg in "\$@"; do
    printf 'ARG:%s\\n' "\${arg}"
  done
} > "\${DART_LOG}"
exit 0
''');
    fixture.pipelineHelper.writeAsStringSync('// Test helper placeholder.\n');
    return fixture;
  }

  Future<ProcessResult> runRunner({
    required List<String> args,
    Map<String, String> environment = const {},
  }) {
    return Process.run(
      'bash',
      [runnerScript.path, ...args],
      environment: {
        'CAVERNO_PERSONAL_EVAL_DART_BIN': fakeDart.path,
        'CAVERNO_PERSONAL_EVAL_SUITE_PIPELINE_HELPER': pipelineHelper.path,
        'CAVERNO_PERSONAL_EVAL_SUITE_OUT_DIR': outDir.path,
        'DART_LOG': dartLog.path,
        ...environment,
      },
    );
  }

  List<String> loggedArgs() {
    return dartLog
        .readAsLinesSync()
        .where((line) => line.startsWith('ARG:'))
        .map((line) => line.substring('ARG:'.length))
        .toList(growable: false);
  }

  void _writeExecutable(File file, String contents) {
    file.writeAsStringSync(contents);
    final result = Process.runSync('chmod', ['+x', file.path]);
    if (result.exitCode != 0) {
      throw StateError('Failed to mark ${file.path} executable.');
    }
  }
}
