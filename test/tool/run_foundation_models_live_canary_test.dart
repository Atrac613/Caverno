import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Foundation Models live canary runner', () {
    test('wrapper pins the local Apple provider', () {
      final script = File(
        'tool/run_foundation_models_live_canary.sh',
      ).readAsStringSync();
      final chatScript = File(
        'tool/run_chat_live_llm_canary.sh',
      ).readAsStringSync();
      final canary = File(
        'tool/canaries/chat_live_llm_canary_test.dart',
      ).readAsStringSync();

      expect(script, contains('CAVERNO_LLM_PROVIDER="appleFoundationModels"'));
      expect(script, contains('CAVERNO_FOUNDATION_MODELS_LIVE_CANARY=1'));
      expect(script, contains('CAVERNO_FOUNDATION_MODELS_LANGUAGE_MATRIX=1'));
      expect(script, contains('foundation_models_live_canary'));
      expect(script, contains('tool/run_chat_live_llm_canary.sh'));
      expect(chatScript, contains('apple-foundation-models://local'));
      expect(chatScript, contains('CAVERNO_FOUNDATION_MODELS_LANGUAGE_MATRIX'));
      expect(
        chatScript,
        contains('integration_test/chat_live_llm_canary_test.dart'),
      );
      expect(chatScript, contains('CAVERNO_CHAT_LIVE_CANARY_NAME'));
      expect(
        canary,
        contains(
          'Foundation Models surfaces locale rejection without crashing',
        ),
      );
      expect(canary, contains('if (!foundationModelsRun)'));
      expect(canary, contains('foundationLanguageMatrixRun'));
    });

    test(
      'invokes the macOS integration target with Foundation Models env',
      () async {
        final fixture = _ScriptFixture.create();
        fixture.writeFlutter();
        fixture.writeDart();

        final result = await fixture.runFoundationModelsHelper();

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          result.stdout,
          contains('Canary: foundation_models_live_canary'),
        );
        expect(result.stdout, contains('Provider: appleFoundationModels'));
        expect(
          result.stdout,
          contains('Base URL: apple-foundation-models://local'),
        );
        expect(result.stdout, contains('Model: apple-foundation-models'));

        final flutterLog = fixture.flutterLog.readAsStringSync();
        expect(
          flutterLog,
          contains(
            'ARGS:test -d macos integration_test/chat_live_llm_canary_test.dart -r json',
          ),
        );
        expect(flutterLog, contains('PROVIDER:appleFoundationModels'));
        expect(
          flutterLog,
          contains('BASE_URL:apple-foundation-models://local'),
        );
        expect(flutterLog, contains('MODEL:apple-foundation-models'));
        expect(flutterLog, contains('FOUNDATION:1'));
        expect(flutterLog, contains('MATRIX:1'));
        expect(flutterLog, contains('LIVE:1'));

        final dartLog = fixture.dartLog.readAsStringSync();
        expect(
          dartLog,
          contains('--canary-name foundation_models_live_canary'),
        );
        expect(dartLog, contains('--surface chat'));
        expect(dartLog, contains('--base-url apple-foundation-models://local'));
        expect(dartLog, contains('--model apple-foundation-models'));
        expect(
          dartLog,
          contains('--command tool/run_foundation_models_live_canary.sh'),
        );
      },
    );
  });
}

final class _ScriptFixture {
  _ScriptFixture._(this.root, this.bin);

  final Directory root;
  final Directory bin;

  File get dartLog => File('${root.path}/dart.log');
  File get flutterLog => File('${root.path}/flutter.log');

  static _ScriptFixture create() {
    final root = Directory.systemTemp.createTempSync(
      'foundation_models_live_helper_',
    );
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final bin = Directory('${root.path}/bin')..createSync();
    return _ScriptFixture._(root, bin);
  }

  void writeFlutter() {
    _writeExecutable('flutter', '''
#!/usr/bin/env bash
{
  printf 'ARGS:%s\\n' "\$*"
  printf 'PROVIDER:%s\\n' "\${CAVERNO_LLM_PROVIDER:-}"
  printf 'BASE_URL:%s\\n' "\${CAVERNO_LLM_BASE_URL:-}"
  printf 'MODEL:%s\\n' "\${CAVERNO_LLM_MODEL:-}"
  printf 'FOUNDATION:%s\\n' "\${CAVERNO_FOUNDATION_MODELS_LIVE_CANARY:-}"
  printf 'MATRIX:%s\\n' "\${CAVERNO_FOUNDATION_MODELS_LANGUAGE_MATRIX:-}"
  printf 'LIVE:%s\\n' "\${CAVERNO_CHAT_LIVE_CANARY:-}"
} > "\${FLUTTER_LOG}"
printf '{"type":"done","success":true}\\n'
exit 0
''');
  }

  void writeDart() {
    _writeExecutable('dart', '''
#!/usr/bin/env bash
printf 'ARGS:%s\\n' "\$*" > "\${DART_LOG}"
exit 0
''');
  }

  Future<ProcessResult> runFoundationModelsHelper() {
    return Process.run(
      'bash',
      ['tool/run_foundation_models_live_canary.sh'],
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        'CAVERNO_CHAT_LIVE_CANARY_REPORT_ROOT': root.path,
        'DART_LOG': dartLog.path,
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
