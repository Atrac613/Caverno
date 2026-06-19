import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_diagnostic_bridge.dart';
import 'package:caverno/features/chat/domain/services/coding_diagnostic_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';

void main() {
  group('LspJsonRpcMessageCodec', () {
    test('encodes and decodes fragmented Content-Length messages', () {
      final encoded = LspJsonRpcMessageCodec.encode(
        LspJsonRpcMessageCodec.notification(
          method: 'window/logMessage',
          params: {'message': 'ready'},
        ),
      );
      final buffer = LspJsonRpcMessageBuffer();

      expect(buffer.addBytes(encoded.take(12).toList()), isEmpty);
      final decoded = buffer.addBytes(encoded.skip(12).toList());

      expect(decoded, hasLength(1));
      expect(decoded.single['jsonrpc'], '2.0');
      expect(decoded.single['method'], 'window/logMessage');
      expect(decoded.single['params'], containsPair('message', 'ready'));
    });
  });

  group('LspJsonRpcDiagnosticBridge', () {
    test('builds initialize and document sync messages', () {
      final bridge = LspJsonRpcDiagnosticBridge(
        providerName: 'typescript_language_server',
        languageId: 'typescript',
        supportsDocumentSymbols: true,
        supportsGoToDefinition: true,
      );

      final initialize = bridge.initializeRequest(
        id: 1,
        rootUri: 'file:///project',
        processId: 123,
      );
      final didOpen = bridge.didOpenNotification(
        uri: 'file:///project/src/app.ts',
        text: 'const app = true;\n',
      );
      final initialized = bridge.initializedNotification();
      final didChange = bridge.didChangeNotification(
        uri: 'file:///project/src/app.ts',
        text: 'const app = false;\n',
        version: 2,
      );
      final documentSymbol = bridge.documentSymbolRequest(
        id: 2,
        uri: 'file:///project/src/app.ts',
      );
      final definition = bridge.definitionRequest(
        id: 3,
        uri: 'file:///project/src/app.ts',
        line: 4,
        character: 12,
      );

      expect(initialize['method'], 'initialize');
      expect(initialize['params'], containsPair('rootUri', 'file:///project'));
      final initializeCapabilities =
          (initialize['params'] as Map<String, dynamic>)['capabilities']
              as Map<String, dynamic>;
      final textDocumentCapabilities =
          initializeCapabilities['textDocument'] as Map<String, dynamic>;
      expect(textDocumentCapabilities, contains('documentSymbol'));
      expect(textDocumentCapabilities, contains('definition'));
      expect(initialized['method'], 'initialized');
      expect(initialized['params'], isEmpty);
      expect(didOpen['method'], 'textDocument/didOpen');
      expect(
        (didOpen['params'] as Map<String, dynamic>)['textDocument'],
        containsPair('languageId', 'typescript'),
      );
      expect(didChange['method'], 'textDocument/didChange');
      expect(
        ((didChange['params'] as Map<String, dynamic>)['contentChanges']
                as List<dynamic>)
            .single,
        containsPair('text', 'const app = false;\n'),
      );
      expect(documentSymbol['method'], 'textDocument/documentSymbol');
      expect(
        (documentSymbol['params'] as Map<String, dynamic>)['textDocument'],
        containsPair('uri', 'file:///project/src/app.ts'),
      );
      expect(definition['method'], 'textDocument/definition');
      final definitionParams = definition['params'] as Map<String, dynamic>;
      expect(
        definitionParams['textDocument'],
        containsPair('uri', 'file:///project/src/app.ts'),
      );
      expect(definitionParams['position'], containsPair('line', 4));
      expect(definitionParams['position'], containsPair('character', 12));
    });

    test('parses document symbol response payloads', () {
      final bridge = LspJsonRpcDiagnosticBridge(
        providerName: 'typescript_language_server',
        languageId: 'typescript',
      );

      final symbols = bridge.documentSymbolsFromResult(
        uri: 'file:///project/src/app.ts',
        result: [
          {
            'name': 'AppRoot',
            'kind': 5,
            'detail': 'class',
            'range': {
              'start': {'line': 1, 'character': 0},
              'end': {'line': 8, 'character': 1},
            },
            'children': [
              {
                'name': 'render',
                'kind': 6,
                'range': {
                  'start': {'line': 4, 'character': 2},
                  'end': {'line': 7, 'character': 3},
                },
              },
            ],
          },
          {
            'name': 'createApp',
            'kind': 12,
            'containerName': 'factory',
            'location': {
              'uri': 'file:///project/src/app.ts',
              'range': {
                'start': {'line': 10, 'character': 0},
                'end': {'line': 12, 'character': 1},
              },
            },
          },
        ],
      );

      expect(symbols, hasLength(2));
      expect(symbols.first.name, 'AppRoot');
      expect(symbols.first.kindLabel, 'Class');
      expect(symbols.first.detail, 'class');
      expect(symbols.first.children.single.name, 'render');
      expect(symbols.first.children.single.kindLabel, 'Method');
      expect(symbols.first.children.single.containerName, 'AppRoot');
      expect(symbols.last.name, 'createApp');
      expect(symbols.last.kindLabel, 'Function');
      expect(symbols.last.containerName, 'factory');
      expect(symbols.expand((symbol) => symbol.flatten()), hasLength(3));
    });

    test('parses definition response payloads', () {
      final bridge = LspJsonRpcDiagnosticBridge(
        providerName: 'typescript_language_server',
        languageId: 'typescript',
      );

      final locations = bridge.definitionLocationsFromResult(
        result: [
          {
            'uri': 'file:///project/src/target.ts',
            'range': {
              'start': {'line': 2, 'character': 4},
              'end': {'line': 2, 'character': 15},
            },
          },
          {
            'targetUri': 'file:///project/src/linked.ts',
            'targetRange': {
              'start': {'line': 8, 'character': 0},
              'end': {'line': 12, 'character': 1},
            },
            'targetSelectionRange': {
              'start': {'line': 9, 'character': 10},
              'end': {'line': 9, 'character': 21},
            },
          },
        ],
      );

      expect(locations, hasLength(2));
      expect(locations.first.uri, 'file:///project/src/target.ts');
      expect(locations.first.startLine, 2);
      expect(locations.first.startCharacter, 4);
      expect(locations.first.endLine, 2);
      expect(locations.first.endCharacter, 15);
      expect(locations.last.uri, 'file:///project/src/linked.ts');
      expect(locations.last.startLine, 9);
      expect(locations.last.startCharacter, 10);
    });

    test('collects diagnostics published by the language server', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_json_rpc_bridge_',
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
      final bridge = LspJsonRpcDiagnosticBridge(
        providerName: 'typescript_language_server',
        languageId: 'typescript',
        supportsDocumentSymbols: true,
        supportsGoToDefinition: true,
      );

      bridge.handleIncomingBytes(
        LspJsonRpcMessageCodec.encode(
          _publishDiagnostics(changedFile.uri.toString(), [
            {
              'range': {
                'start': {'line': 0, 'character': 12},
                'end': {'line': 0, 'character': 25},
              },
              'severity': 1,
              'code': 'TS2304',
              'source': 'typescript',
              'message': 'Cannot find name missingSymbol.',
            },
          ]),
        ),
      );
      bridge.handleIncomingMessage(
        _publishDiagnostics(unrelatedFile.uri.toString(), [
          {
            'range': {
              'start': {'line': 0, 'character': 0},
              'end': {'line': 0, 'character': 1},
            },
            'severity': 2,
            'message': 'Unrelated warning.',
          },
        ]),
      );

      final diagnostics = await bridge.collectDiagnostics(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics!.single.uri, changedFile.uri.toString());
      expect(diagnostics.single.startLine, 0);
      expect(diagnostics.single.startCharacter, 12);
      expect(diagnostics.single.severity, 1);
      expect(diagnostics.single.code, 'TS2304');
      expect(diagnostics.single.source, 'typescript');
      expect(diagnostics.single.message, 'Cannot find name missingSymbol.');
    });

    test(
      'clears diagnostics when the server publishes an empty list',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_lsp_json_rpc_bridge_clear_',
        );
        addTearDown(() => root.delete(recursive: true));
        final changedFile = await _writeFile(root, 'src/app.py', 'print(x)\n');
        final bridge = LspJsonRpcDiagnosticBridge(
          providerName: 'python_language_server',
          languageId: 'python',
        );

        bridge.handleIncomingMessage(
          _publishDiagnostics(changedFile.uri.toString(), [
            {
              'range': {
                'start': {'line': 0, 'character': 6},
                'end': {'line': 0, 'character': 7},
              },
              'severity': 1,
              'message': 'Undefined name x.',
            },
          ]),
        );
        bridge.handleIncomingMessage(
          _publishDiagnostics(changedFile.uri.toString(), const []),
        );

        final diagnostics = await bridge.collectDiagnostics(
          projectRoot: root.path,
          changedPaths: [changedFile.path],
        );

        expect(diagnostics, isEmpty);
        expect(
          bridge.hasPublishedDiagnosticsForUris([changedFile.uri.toString()]),
          isTrue,
        );
      },
    );

    test(
      'feeds published diagnostics through coding feedback payloads',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_lsp_json_rpc_bridge_feedback_',
        );
        addTearDown(() => root.delete(recursive: true));
        final changedFile = await _writeFile(
          root,
          'src/app.ts',
          'missing();\n',
        );
        final bridge = LspJsonRpcDiagnosticBridge(
          providerName: 'typescript_language_server',
          languageId: 'typescript',
          supportsDocumentSymbols: true,
          supportsGoToDefinition: true,
        );
        bridge.handleIncomingMessage(
          _publishDiagnostics(changedFile.uri.toString(), [
            {
              'range': {
                'start': {'line': 0, 'character': 0},
                'end': {'line': 0, 'character': 7},
              },
              'severity': 1,
              'code': 'TS2304',
              'source': 'typescript',
              'message': 'Cannot find name missing.',
            },
          ]),
        );
        final service = CodingDiagnosticFeedbackService(
          provider: LspDiagnosticFeedbackProvider(client: bridge),
        );

        final result = await service.buildFeedbackToolResult(
          projectRoot: root.path,
          changedPaths: [changedFile.path],
        );

        expect(result, isNotNull);
        final payload = jsonDecode(result!.result) as Map<String, dynamic>;
        expect(payload['provider'], 'typescript_language_server');
        expect(payload['diagnostic_count'], 1);
        final bridgeMetadata =
            payload['language_diagnostics_bridge'] as Map<String, dynamic>;
        expect(bridgeMetadata['protocol'], 'lsp');
        final capabilities =
            bridgeMetadata['capabilities'] as Map<String, dynamic>;
        expect(capabilities['document_symbols'], isTrue);
        expect(capabilities['go_to_definition'], isTrue);
        final diagnostics = payload['diagnostics'] as List<dynamic>;
        expect(diagnostics.single, containsPair('relative_path', 'src/app.ts'));
        expect(
          diagnostics.single,
          containsPair('message', 'Cannot find name missing.'),
        );
      },
    );
  });
}

Map<String, dynamic> _publishDiagnostics(
  String uri,
  List<Map<String, dynamic>> diagnostics,
) {
  return LspJsonRpcMessageCodec.notification(
    method: 'textDocument/publishDiagnostics',
    params: {'uri': uri, 'diagnostics': diagnostics},
  );
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
