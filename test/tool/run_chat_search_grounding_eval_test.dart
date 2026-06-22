import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat search grounding eval runner', () {
    test('passes endpoint and model arguments to the Dart eval', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeDart();

      final result = await fixture.runHelper(
        environment: {
          'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:1234/v1',
          'CAVERNO_LLM_API_KEY': 'no-key',
          'CAVERNO_CHAT_SEARCH_GROUNDING_MODELS': 'model-a model-b',
          'CAVERNO_CHAT_SEARCH_GROUNDING_REPORT_ROOT': fixture.reportRoot.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Running chat search grounding eval'));
      final dartLog = fixture.dartLog.readAsStringSync();
      expect(dartLog, contains('run '));
      expect(dartLog, contains('tool/chat_search_grounding_eval.dart'));
      expect(dartLog, contains('--base-url http://127.0.0.1:1234/v1'));
      expect(dartLog, contains('--api-key no-key'));
      expect(dartLog, contains('--model model-a'));
      expect(dartLog, contains('--model model-b'));
      expect(dartLog, contains('--temperature 0.2'));
      expect(dartLog, contains('--max-tokens 8192'));
    });
  });
}

final class _ScriptFixture {
  _ScriptFixture._(this.root, this.bin, this.reportRoot);

  final Directory root;
  final Directory bin;
  final Directory reportRoot;

  File get dartLog => File('${root.path}/dart.log');

  static _ScriptFixture create() {
    final root = Directory.systemTemp.createTempSync(
      'chat_search_grounding_eval_runner_',
    );
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final bin = Directory('${root.path}/bin')..createSync();
    final reportRoot = Directory('${root.path}/reports')..createSync();
    return _ScriptFixture._(root, bin, reportRoot);
  }

  void writeDart() {
    final file = File('${bin.path}/dart')
      ..writeAsStringSync('''
#!/usr/bin/env bash
printf 'ARGS:%s\\n' "\$*" > "\${DART_LOG}"
exit 0
''');
    final result = Process.runSync('chmod', ['+x', file.path]);
    expect(result.exitCode, 0);
  }

  Future<ProcessResult> runHelper({required Map<String, String> environment}) {
    return Process.run(
      'bash',
      ['tool/run_chat_search_grounding_eval.sh'],
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        'DART_LOG': dartLog.path,
        ...environment,
      },
    );
  }
}
