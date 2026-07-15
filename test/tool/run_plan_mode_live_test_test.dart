import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plan mode live test helper', () {
    test(
      'fails before Flutter when endpoint preflight cannot reach models',
      () async {
        final fixture = _ScriptFixture.create();
        fixture.writeCurl(exitCode: 22);
        fixture.writeFlutter();

        final result = await fixture.runLiveHelper(
          environment: const {
            'CAVERNO_LLM_BASE_URL': 'http://localhost:65535/v1/',
            'CAVERNO_LLM_API_KEY': 'test-token',
            'CAVERNO_LLM_MODEL': 'test-model',
            'CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS': '1',
          },
        );

        expect(result.exitCode, 78);
        expect(
          result.stdout,
          contains('Checking live endpoint: http://localhost:65535/v1/models'),
        );
        expect(
          result.stderr,
          contains(
            'Live endpoint preflight failed: could not reach '
            'http://localhost:65535/v1/models.',
          ),
        );
        expect(
          result.stderr,
          contains('set CAVERNO_PLAN_MODE_PREFLIGHT=0 to skip this check'),
        );
        expect(fixture.curlLog.readAsStringSync(), contains('--max-time\n1'));
        expect(
          fixture.curlLog.readAsStringSync(),
          contains('Authorization: Bearer test-token'),
        );
        expect(fixture.curlLog.readAsStringSync(), contains('/v1/models'));
        expect(fixture.flutterLog.existsSync(), isFalse);
      },
    );

    test(
      'skips endpoint preflight when disabled and invokes Flutter',
      () async {
        final fixture = _ScriptFixture.create();
        fixture.writeCurl(exitCode: 99);
        fixture.writeFlutter();

        final result = await fixture.runLiveHelper(
          environment: const {
            'CAVERNO_LLM_BASE_URL': 'http://localhost:65535/v1',
            'CAVERNO_LLM_API_KEY': 'test-token',
            'CAVERNO_LLM_MODEL': 'test-model',
            'CAVERNO_PLAN_MODE_PREFLIGHT': '0',
            'CAVERNO_PLAN_MODE_SCENARIOS': 'live_clarify_recovery',
            'CAVERNO_PLAN_MODE_TAGS': 'smoke',
            'CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS': '1',
            'CAVERNO_PLAN_MODE_DEVICE': 'macos',
            'CAVERNO_PLAN_MODE_REPORTER': 'compact',
            'CAVERNO_LLM_LOG_TOOL_SCHEMAS': '1',
          },
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('Endpoint preflight: 0'));
        expect(result.stdout, contains('Log tool schemas: 1'));
        expect(result.stdout, isNot(contains('Checking live endpoint')));
        expect(fixture.curlLog.existsSync(), isFalse);

        final flutterLog = fixture.flutterLog.readAsStringSync();
        expect(
          flutterLog,
          contains('ARGS:test integration_test/plan_mode_scenario_test.dart'),
        );
        expect(flutterLog, contains('-d macos -r compact'));
        expect(
          flutterLog,
          contains('--dart-define=CAVERNO_LLM_LOG_TOOL_SCHEMAS=true'),
        );
        expect(flutterLog, contains('LIVE:1'));
        expect(flutterLog, contains('SCENARIOS:live_clarify_recovery'));
        expect(flutterLog, contains('TAGS:smoke'));
        expect(flutterLog, contains('FAIL_ON_WARNINGS:1'));
      },
    );

    test('omits tool schema dart define by default', () async {
      final fixture = _ScriptFixture.create();
      fixture.writeCurl(exitCode: 99);
      fixture.writeFlutter();

      final result = await fixture.runLiveHelper(
        environment: const {
          'CAVERNO_LLM_BASE_URL': 'http://localhost:65535/v1',
          'CAVERNO_LLM_API_KEY': 'test-token',
          'CAVERNO_LLM_MODEL': 'test-model',
          'CAVERNO_PLAN_MODE_PREFLIGHT': '0',
        },
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Log tool schemas: 0'));

      final flutterLog = fixture.flutterLog.readAsStringSync();
      expect(flutterLog, isNot(contains('CAVERNO_LLM_LOG_TOOL_SCHEMAS')));
    });
  });
}

final class _ScriptFixture {
  _ScriptFixture._(this.root, this.bin);

  final Directory root;
  final Directory bin;

  File get curlLog => File('${root.path}/curl.log');
  File get flutterLog => File('${root.path}/flutter.log');

  static _ScriptFixture create() {
    final root = Directory.systemTemp.createTempSync('plan_mode_live_helper_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final bin = Directory('${root.path}/bin')..createSync();
    return _ScriptFixture._(root, bin);
  }

  void writeCurl({required int exitCode}) {
    _writeExecutable('curl', '''
#!/usr/bin/env bash
printf '%s\\n' "\$@" > "\${CURL_LOG}"
exit $exitCode
''');
  }

  void writeFlutter() {
    _writeExecutable('flutter', '''
#!/usr/bin/env bash
{
  printf 'ARGS:%s\\n' "\$*"
  printf 'LIVE:%s\\n' "\${CAVERNO_PLAN_MODE_LIVE_LLM:-}"
  printf 'SCENARIOS:%s\\n' "\${CAVERNO_PLAN_MODE_SCENARIOS:-}"
  printf 'TAGS:%s\\n' "\${CAVERNO_PLAN_MODE_TAGS:-}"
  printf 'FAIL_ON_WARNINGS:%s\\n' "\${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-}"
} > "\${FLUTTER_LOG}"
exit 0
''');
    _writeExecutable('fvm', '''
#!/usr/bin/env bash
if [[ "\${1:-}" != "flutter" ]]; then
  exit 64
fi
shift
exec flutter "\$@"
''');
  }

  Future<ProcessResult> runLiveHelper({
    required Map<String, String> environment,
  }) {
    return Process.run(
      'bash',
      ['tool/run_plan_mode_live_test.sh'],
      environment: {
        ...environment,
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        'CURL_LOG': curlLog.path,
        'FLUTTER_LOG': flutterLog.path,
      },
    );
  }

  void _writeExecutable(String name, String contents) {
    final file = File('${bin.path}/$name')..writeAsStringSync(contents);
    final result = Process.runSync('chmod', ['+x', file.path]);
    expect(result.exitCode, 0);
  }
}
