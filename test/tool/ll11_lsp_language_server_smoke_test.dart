import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';

import '../../tool/ll11_lsp_language_server_smoke.dart';

void main() {
  group('LL11 LSP language-server smoke', () {
    test(
      'passes when a real-probe substitute returns diagnostics and symbols',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'll11_lsp_smoke_pass_',
        );
        addTearDown(() {
          if (root.existsSync()) {
            root.deleteSync(recursive: true);
          }
        });

        final result = await buildLl11LspLanguageServerSmokeReport(
          generatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
          options: Ll11LspLanguageServerSmokeOptions(
            languages: const ['python'],
            requireLanguageServer: true,
            diagnosticTimeoutMs: 10,
            symbolTimeoutMs: 10,
            definitionTimeoutMs: 10,
            command: 'test command',
            workRootPath: root.path,
          ),
          probe: _FakeSmokeProbe(
            Ll11LspLanguageServerProbeResult.ready(
              languageId: 'python',
              status: 'ready',
              command: 'pyright-langserver --stdio',
              workingDirectory: root.path,
              diagnostics: const [
                LspDiagnostic(
                  uri: 'file:///tmp/src/app.py',
                  startLine: 2,
                  startCharacter: 15,
                  severity: 1,
                  code: 'reportUndefinedVariable',
                  source: 'pyright',
                  message: 'Undefined name missing_value.',
                ),
              ],
              documentSymbols: const [
                LspDocumentSymbol(
                  uri: 'file:///tmp/src/app.py',
                  name: 'SmokeSymbol',
                  kind: 5,
                  kindLabel: 'Class',
                  startLine: 0,
                  startCharacter: 6,
                ),
              ],
              definitions: const [
                LspDefinitionLocation(
                  uri: 'file:///tmp/src/app.py',
                  startLine: 0,
                  startCharacter: 6,
                  endLine: 0,
                  endCharacter: 17,
                ),
              ],
            ),
          ),
        );

        expect(result.status, 'passed');
        expect(result.shouldFail, isFalse);
        expect(result.passedCount, 1);
        final json = result.toJson();
        expect(
          json,
          containsPair('schemaName', ll11LspLanguageServerSmokeSchemaName),
        );
        expect(
          json,
          containsPair('canaryName', ll11LspLanguageServerSmokeCanaryName),
        );
        expect(
          json,
          containsPair('surface', ll11LspLanguageServerSmokeSurface),
        );
        final scenarios = json['scenarios'] as List<dynamic>;
        final scenario = scenarios.single as Map<String, dynamic>;
        expect(scenario, containsPair('languageId', 'python'));
        expect(scenario, containsPair('status', 'passed'));
        expect(scenario, containsPair('diagnosticCount', 1));
        expect(scenario, containsPair('symbolCount', 1));
        expect(scenario, containsPair('definitionCount', 1));

        final markdown = result.toMarkdown();
        expect(markdown, contains('# LL11 LSP Language Server Smoke'));
        expect(markdown, contains('| python | passed | 1 | 1 | 1 |'));
        expect(markdown, contains('pyright-langserver --stdio'));
      },
    );

    test('skips unavailable servers unless a server is required', () async {
      final root = Directory.systemTemp.createTempSync('ll11_lsp_smoke_skip_');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });

      final result = await buildLl11LspLanguageServerSmokeReport(
        options: Ll11LspLanguageServerSmokeOptions(
          languages: const ['swift'],
          requireLanguageServer: false,
          diagnosticTimeoutMs: 10,
          symbolTimeoutMs: 10,
          definitionTimeoutMs: 10,
          command: 'test command',
          workRootPath: root.path,
        ),
        probe: _FakeSmokeProbe(
          Ll11LspLanguageServerProbeResult.unavailable(
            languageId: 'swift',
            status: 'unavailable',
            code: 'language_server_session_start_failed',
            error: 'sourcekit-lsp was not available.',
          ),
        ),
      );

      expect(result.status, 'skipped');
      expect(result.shouldFail, isFalse);
      expect(result.skippedCount, 1);
      expect(result.blockedGateIds, isEmpty);
    });

    test('fails when a required language server cannot pass', () async {
      final root = Directory.systemTemp.createTempSync(
        'll11_lsp_smoke_required_',
      );
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });

      final result = await buildLl11LspLanguageServerSmokeReport(
        options: Ll11LspLanguageServerSmokeOptions(
          languages: const ['typescript'],
          requireLanguageServer: true,
          diagnosticTimeoutMs: 10,
          symbolTimeoutMs: 10,
          definitionTimeoutMs: 10,
          command: 'test command',
          workRootPath: root.path,
        ),
        probe: _FakeSmokeProbe(
          Ll11LspLanguageServerProbeResult.unavailable(
            languageId: 'typescript',
            status: 'unavailable',
            code: 'language_server_session_start_failed',
            error: 'typescript-language-server was not available.',
          ),
        ),
      );

      expect(result.status, 'failed');
      expect(result.shouldFail, isTrue);
      expect(result.blockedGateIds, contains('no_language_server_passed'));
    });

    test('parses language aliases and timeout options', () {
      final options = Ll11LspLanguageServerSmokeOptions.parse([
        '--language',
        'py',
        '--language=ts,swift',
        '--require-language-server',
        '--diagnostic-timeout-ms',
        '42',
        '--symbol-timeout-ms=24',
        '--definition-timeout-ms',
        '18',
        '--command',
        'custom command',
      ], environment: const {});

      expect(options.languages, ['python', 'typescript', 'swift']);
      expect(options.requireLanguageServer, isTrue);
      expect(options.diagnosticTimeoutMs, 42);
      expect(options.symbolTimeoutMs, 24);
      expect(options.definitionTimeoutMs, 18);
      expect(options.command, 'custom command');
    });

    test('wrapper writes the expected canary artifacts', () {
      final script = File(
        'tool/run_ll11_lsp_language_server_smoke.sh',
      ).readAsStringSync();

      expect(script, contains(r'll11_lsp_language_server_smoke_$(date +%s)'));
      expect(script, contains('canary_summary.json'));
      expect(script, contains('canary_summary.md'));
      expect(script, contains('CAVERNO_LL11_LSP_SMOKE_LANGUAGES'));
      expect(script, contains('CAVERNO_LL11_LSP_SMOKE_DEFINITION_TIMEOUT_MS'));
      expect(script, contains('--require-language-server'));
    });
  });
}

class _FakeSmokeProbe implements Ll11LspLanguageServerSmokeProbe {
  const _FakeSmokeProbe(this.result);

  final Ll11LspLanguageServerProbeResult result;

  @override
  Future<Ll11LspLanguageServerProbeResult> run({
    required Ll11LspLanguageServerSmokeScenario scenario,
    required String projectRoot,
    required String changedPath,
    required Duration diagnosticTimeout,
    required Duration symbolTimeout,
    required Duration definitionTimeout,
  }) async {
    expect(File(changedPath).existsSync(), isTrue);
    expect(diagnosticTimeout, const Duration(milliseconds: 10));
    expect(symbolTimeout, const Duration(milliseconds: 10));
    expect(definitionTimeout, const Duration(milliseconds: 10));
    return result;
  }
}
