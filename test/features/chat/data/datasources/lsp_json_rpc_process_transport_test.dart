import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_diagnostic_bridge.dart';
import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_process_transport.dart';

void main() {
  group('LspJsonRpcProcessTransport', () {
    test(
      'sends initialize and document sync messages as framed JSON-RPC',
      () async {
        final fakeTransport = _FakeLspJsonRpcByteTransport();
        final bridge = LspJsonRpcDiagnosticBridge(
          providerName: 'typescript_language_server',
          languageId: 'typescript',
        );
        final transport = LspJsonRpcProcessTransport(
          bridge: bridge,
          byteTransport: fakeTransport,
        );
        addTearDown(transport.close);

        await transport.sendInitialize(
          id: 1,
          rootUri: 'file:///project',
          processId: 123,
        );
        await transport.sendInitialized();
        await transport.sendDidOpen(
          uri: 'file:///project/src/app.ts',
          text: 'const app = true;\n',
        );
        await transport.sendDidChange(
          uri: 'file:///project/src/app.ts',
          text: 'const app = false;\n',
          version: 2,
        );
        await transport.sendDocumentSymbols(
          id: 2,
          uri: 'file:///project/src/app.ts',
        );
        await transport.sendDefinition(
          id: 3,
          uri: 'file:///project/src/app.ts',
          line: 4,
          character: 12,
        );

        final sentMessages = _decodeWrittenMessages(fakeTransport.writes);
        expect(sentMessages.map((message) => message['method']), [
          'initialize',
          'initialized',
          'textDocument/didOpen',
          'textDocument/didChange',
          'textDocument/documentSymbol',
          'textDocument/definition',
        ]);
        expect(sentMessages.first['params'], containsPair('processId', 123));
        expect(
          ((sentMessages[2]['params'] as Map<String, dynamic>)['textDocument']
              as Map<String, dynamic>),
          containsPair('languageId', 'typescript'),
        );
        expect(
          ((sentMessages[3]['params'] as Map<String, dynamic>)['contentChanges']
                  as List<dynamic>)
              .single,
          containsPair('text', 'const app = false;\n'),
        );
        expect(
          ((sentMessages[4]['params'] as Map<String, dynamic>)['textDocument']
              as Map<String, dynamic>),
          containsPair('uri', 'file:///project/src/app.ts'),
        );
        final definitionParams =
            sentMessages[5]['params'] as Map<String, dynamic>;
        expect(definitionParams['position'], containsPair('line', 4));
        expect(definitionParams['position'], containsPair('character', 12));
      },
    );

    test('routes stdout messages into the diagnostic bridge', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_process_transport_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print(x)\n');
      final fakeTransport = _FakeLspJsonRpcByteTransport();
      final bridge = LspJsonRpcDiagnosticBridge(
        providerName: 'python_language_server',
        languageId: 'python',
      );
      final transport = LspJsonRpcProcessTransport(
        bridge: bridge,
        byteTransport: fakeTransport,
      );
      addTearDown(transport.close);
      final firstMessage = transport.messages.first;
      final encoded = LspJsonRpcMessageCodec.encode(
        LspJsonRpcMessageCodec.notification(
          method: 'textDocument/publishDiagnostics',
          params: {
            'uri': changedFile.uri.toString(),
            'diagnostics': [
              {
                'range': {
                  'start': {'line': 0, 'character': 6},
                  'end': {'line': 0, 'character': 7},
                },
                'severity': 1,
                'message': 'Undefined name x.',
              },
            ],
          },
        ),
      );

      fakeTransport.emitStdout(encoded.take(8).toList());
      fakeTransport.emitStdout(encoded.skip(8).toList());

      final message = await firstMessage;
      expect(message['method'], 'textDocument/publishDiagnostics');
      final diagnostics = await bridge.collectDiagnostics(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics!.single.message, 'Undefined name x.');
    });

    test('forwards stderr bytes and can kill the process', () async {
      final fakeTransport = _FakeLspJsonRpcByteTransport();
      final bridge = LspJsonRpcDiagnosticBridge(
        providerName: 'python_language_server',
        languageId: 'python',
      );
      final transport = LspJsonRpcProcessTransport(
        bridge: bridge,
        byteTransport: fakeTransport,
      );
      addTearDown(transport.close);
      final stderrBytes = transport.stderr.first;

      fakeTransport.emitStderr(utf8.encode('server warning\n'));

      expect(utf8.decode(await stderrBytes), 'server warning\n');
      expect(transport.kill(), isTrue);
      expect(fakeTransport.killCount, 1);
    });
  });
}

List<Map<String, dynamic>> _decodeWrittenMessages(List<List<int>> writes) {
  final buffer = LspJsonRpcMessageBuffer();
  return writes
      .expand(buffer.addBytes)
      .map((message) => Map<String, dynamic>.from(message))
      .toList(growable: false);
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

class _FakeLspJsonRpcByteTransport implements LspJsonRpcByteTransport {
  final StreamController<List<int>> _stdout =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderr =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCode = Completer<int>();
  final List<List<int>> writes = [];
  var closeCount = 0;
  var killCount = 0;

  @override
  int get pid => 1234;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<void> write(List<int> bytes) async {
    writes.add(List<int>.from(bytes));
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    await _stdout.close();
    await _stderr.close();
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount += 1;
    if (!_exitCode.isCompleted) {
      _exitCode.complete(-1);
    }
    return true;
  }

  void emitStdout(List<int> bytes) {
    _stdout.add(bytes);
  }

  void emitStderr(List<int> bytes) {
    _stderr.add(bytes);
  }
}
