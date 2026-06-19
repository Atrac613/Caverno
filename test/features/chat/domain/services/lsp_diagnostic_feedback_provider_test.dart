import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/coding_diagnostic_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';

void main() {
  group('LspDiagnosticFeedbackProvider', () {
    test(
      'maps LSP diagnostics for changed files into feedback payloads',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_lsp_diagnostic_feedback_',
        );
        addTearDown(() => root.delete(recursive: true));
        final changedFile = await _writeFile(
          root,
          'src/app.ts',
          'const app = missingSymbol;\n',
        );
        final unrelatedFile = await _writeFile(
          root,
          'src/unrelated.ts',
          'const ok = true;\n',
        );
        final client = _FakeLspDiagnosticClient([
          LspDiagnostic(
            uri: changedFile.uri.toString(),
            startLine: 2,
            startCharacter: 4,
            severity: 1,
            code: 'TS2304',
            source: 'typescript',
            message: 'Cannot find name missingSymbol.',
          ),
          LspDiagnostic(
            uri: unrelatedFile.uri.toString(),
            startLine: 0,
            startCharacter: 0,
            severity: 2,
            message: 'Unrelated warning.',
          ),
        ]);
        final service = CodingDiagnosticFeedbackService(
          provider: LspDiagnosticFeedbackProvider(client: client),
        );

        final result = await service.buildFeedbackToolResult(
          projectRoot: root.path,
          changedPaths: [changedFile.path],
        );

        expect(result, isNotNull);
        final payload = jsonDecode(result!.result) as Map<String, dynamic>;
        expect(payload['provider'], 'typescript_language_server');
        expect(payload['changed_paths'], ['src/app.ts']);
        expect(payload['diagnostic_count'], 1);
        final bridge =
            payload['language_diagnostics_bridge'] as Map<String, dynamic>;
        expect(bridge['protocol'], 'lsp');
        expect(bridge['status'], 'ready');
        final capabilities = bridge['capabilities'] as Map<String, dynamic>;
        expect(capabilities['diagnostics'], isTrue);
        expect(capabilities['document_symbols'], isTrue);
        expect(capabilities['go_to_definition'], isTrue);
        final diagnostics = payload['diagnostics'] as List<dynamic>;
        expect(diagnostics.single, containsPair('relative_path', 'src/app.ts'));
        expect(diagnostics.single, containsPair('severity', 'Error'));
        expect(diagnostics.single, containsPair('line', 3));
        expect(diagnostics.single, containsPair('column', 5));
        expect(diagnostics.single, containsPair('code', 'TS2304'));
        expect(diagnostics.single, containsPair('source', 'typescript'));
        expect(
          diagnostics.single,
          containsPair('message', 'Cannot find name missingSymbol.'),
        );
      },
    );

    test('returns null when the LSP client is unavailable', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_diagnostic_feedback_unavailable_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print(x)\n');
      final service = CodingDiagnosticFeedbackService(
        provider: LspDiagnosticFeedbackProvider(
          client: const _UnavailableLspDiagnosticClient(),
        ),
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(result, isNull);
    });

    test(
      'returns null before collecting when the server is not ready',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_lsp_diagnostic_feedback_not_ready_',
        );
        addTearDown(() => root.delete(recursive: true));
        final changedFile = await _writeFile(root, 'src/app.py', 'print(x)\n');
        final client = _CountingLspDiagnosticClient();
        final service = CodingDiagnosticFeedbackService(
          provider: LspDiagnosticFeedbackProvider(
            client: client,
            readinessProbe: const _UnavailableReadinessProbe(),
          ),
        );

        final result = await service.buildFeedbackToolResult(
          projectRoot: root.path,
          changedPaths: [changedFile.path],
        );

        expect(result, isNull);
        expect(client.collectCount, 0);
      },
    );
  });
}

Future<File> _writeFile(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = File.fromUri(root.uri.resolve(relativePath));
  await file.parent.create(recursive: true);
  return file.writeAsString(content);
}

class _FakeLspDiagnosticClient implements LspDiagnosticClient {
  const _FakeLspDiagnosticClient(this.diagnostics);

  final List<LspDiagnostic> diagnostics;

  @override
  String get providerName => 'typescript_language_server';

  @override
  bool get supportsDocumentSymbols => true;

  @override
  bool get supportsGoToDefinition => true;

  @override
  Future<List<LspDiagnostic>?> collectDiagnostics({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    return diagnostics;
  }
}

class _UnavailableLspDiagnosticClient implements LspDiagnosticClient {
  const _UnavailableLspDiagnosticClient();

  @override
  String get providerName => 'python_language_server';

  @override
  bool get supportsDocumentSymbols => false;

  @override
  bool get supportsGoToDefinition => false;

  @override
  Future<List<LspDiagnostic>?> collectDiagnostics({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    return null;
  }
}

class _CountingLspDiagnosticClient implements LspDiagnosticClient {
  var collectCount = 0;

  @override
  String get providerName => 'python_language_server';

  @override
  bool get supportsDocumentSymbols => false;

  @override
  bool get supportsGoToDefinition => false;

  @override
  Future<List<LspDiagnostic>?> collectDiagnostics({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    collectCount += 1;
    return const [];
  }
}

class _UnavailableReadinessProbe implements LspServerReadinessProbe {
  const _UnavailableReadinessProbe();

  @override
  Future<LspServerReadiness> ensureReady({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    return const LspServerReadiness(
      ok: false,
      status: 'unavailable',
      code: 'language_server_start_failed',
      error: 'Language server start failed.',
    );
  }
}
