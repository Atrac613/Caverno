import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_diagnostic_bridge.dart';
import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_process_transport.dart';
import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_session_registry.dart';
import 'package:caverno/features/chat/data/datasources/lsp_server_command_resolver.dart';

void main() {
  group('LspJsonRpcSessionRegistry', () {
    test('starts a session and sends initialize plus didOpen', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_session_registry_start_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print("hi")\n');
      final fakeTransport = _FakeLspJsonRpcByteTransport();
      final registry = LspJsonRpcSessionRegistry(
        executableProbe: const _AvailableLspServerExecutableProbe(),
        transportStarter:
            ({required command, required workingDirectory}) async {
              expect(command, 'pyright-langserver --stdio');
              expect(workingDirectory, root.absolute.path);
              return fakeTransport;
            },
      );
      addTearDown(registry.close);

      final resultFuture = registry.ensureSession(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      await _pumpEventQueue();
      _completeInitialize(fakeTransport);

      final result = await resultFuture;

      expect(result.ok, isTrue);
      expect(result.languageId, 'python');
      expect(result.reused, isFalse);
      final sentMessages = _decodeWrittenMessages(fakeTransport.writes);
      expect(sentMessages.map((message) => message['method']), [
        'initialize',
        'initialized',
        'textDocument/didOpen',
      ]);
      expect(sentMessages.first['params'], containsPair('processId', 4321));
      final textDocument =
          (sentMessages[2]['params'] as Map<String, dynamic>)['textDocument']
              as Map<String, dynamic>;
      expect(textDocument['languageId'], 'python');
      expect(textDocument['version'], 1);
      expect(textDocument['text'], 'print("hi")\n');
    });

    test(
      'reuses a session and sends didChange with incremented version',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_lsp_session_registry_reuse_',
        );
        addTearDown(() => root.delete(recursive: true));
        final changedFile = await _writeFile(
          root,
          'src/app.ts',
          'const app = 1;\n',
        );
        final fakeTransport = _FakeLspJsonRpcByteTransport();
        var startCount = 0;
        final registry = LspJsonRpcSessionRegistry(
          executableProbe: const _AvailableLspServerExecutableProbe(),
          transportStarter:
              ({required command, required workingDirectory}) async {
                startCount += 1;
                return fakeTransport;
              },
        );
        addTearDown(registry.close);

        final firstSessionFuture = registry.ensureSession(
          projectRoot: root.path,
          changedPaths: [changedFile.path],
        );
        await _pumpEventQueue();
        _completeInitialize(fakeTransport);
        await firstSessionFuture;
        await changedFile.writeAsString('const app = 2;\n');
        final reused = await registry.ensureSession(
          projectRoot: root.path,
          changedPaths: [changedFile.path],
        );

        expect(reused.ok, isTrue);
        expect(reused.reused, isTrue);
        expect(startCount, 1);
        final sentMessages = _decodeWrittenMessages(fakeTransport.writes);
        expect(sentMessages.map((message) => message['method']), [
          'initialize',
          'initialized',
          'textDocument/didOpen',
          'textDocument/didChange',
        ]);
        final changeParams = sentMessages[3]['params'] as Map<String, dynamic>;
        expect(changeParams['textDocument'], containsPair('version', 2));
        expect(
          (changeParams['contentChanges'] as List<dynamic>).single,
          containsPair('text', 'const app = 2;\n'),
        );
      },
    );

    test('collects diagnostics from the active session bridge', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_session_registry_diagnostics_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print(x)\n');
      final fakeTransport = _FakeLspJsonRpcByteTransport();
      final registry = LspJsonRpcSessionRegistry(
        executableProbe: const _AvailableLspServerExecutableProbe(),
        transportStarter:
            ({required command, required workingDirectory}) async {
              return fakeTransport;
            },
      );
      addTearDown(registry.close);

      final readinessFuture = registry.ensureReady(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      await _pumpEventQueue();
      _completeInitialize(fakeTransport);
      await readinessFuture;
      fakeTransport.emitStdout(
        LspJsonRpcMessageCodec.encode(
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
        ),
      );
      await _pumpEventQueue();

      final diagnostics = await registry.collectDiagnostics(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics!.single.message, 'Undefined name x.');
    });

    test('waits for async diagnostics before collecting', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_session_registry_wait_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print(x)\n');
      final fakeTransport = _FakeLspJsonRpcByteTransport();
      final registry = LspJsonRpcSessionRegistry(
        executableProbe: const _AvailableLspServerExecutableProbe(),
        diagnosticSettleTimeout: const Duration(milliseconds: 100),
        diagnosticPollInterval: const Duration(milliseconds: 1),
        transportStarter:
            ({required command, required workingDirectory}) async {
              return fakeTransport;
            },
      );
      addTearDown(registry.close);

      final readinessFuture = registry.ensureReady(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      await _pumpEventQueue();
      _completeInitialize(fakeTransport);
      await readinessFuture;
      final diagnosticsFuture = registry.collectDiagnostics(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      await _pumpEventQueue();
      fakeTransport.emitStdout(
        LspJsonRpcMessageCodec.encode(
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
        ),
      );

      final diagnostics = await diagnosticsFuture;

      expect(diagnostics, hasLength(1));
      expect(diagnostics!.single.message, 'Undefined name x.');
    });

    test('requests document symbols from the active session', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_session_registry_symbols_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(
        root,
        'src/app.ts',
        'export class AppRoot {}\n',
      );
      final fakeTransport = _FakeLspJsonRpcByteTransport();
      final registry = LspJsonRpcSessionRegistry(
        executableProbe: const _AvailableLspServerExecutableProbe(),
        symbolRequestTimeout: const Duration(milliseconds: 100),
        transportStarter:
            ({required command, required workingDirectory}) async {
              return fakeTransport;
            },
      );
      addTearDown(registry.close);

      final symbolsFuture = registry.collectDocumentSymbols(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      await _pumpEventQueue();
      _completeInitialize(fakeTransport);
      await _pumpEventQueue();
      final sentMessages = _decodeWrittenMessages(fakeTransport.writes);
      expect(sentMessages.map((message) => message['method']), [
        'initialize',
        'initialized',
        'textDocument/didOpen',
        'textDocument/documentSymbol',
      ]);
      final requestId = sentMessages.last['id'];
      fakeTransport.emitStdout(
        LspJsonRpcMessageCodec.encode({
          'jsonrpc': '2.0',
          'id': requestId,
          'result': [
            {
              'name': 'AppRoot',
              'kind': 5,
              'range': {
                'start': {'line': 0, 'character': 13},
                'end': {'line': 0, 'character': 20},
              },
            },
          ],
        }),
      );

      final symbols = await symbolsFuture;

      expect(symbols, hasLength(1));
      expect(symbols!.single.uri, changedFile.uri.toString());
      expect(symbols.single.name, 'AppRoot');
      expect(symbols.single.kindLabel, 'Class');
      expect(symbols.single.startLine, 0);
      expect(symbols.single.startCharacter, 13);
    });

    test('requests definitions from the active session', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_session_registry_definition_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.ts', '''
export class AppRoot {}
const app = new AppRoot();
''');
      final fakeTransport = _FakeLspJsonRpcByteTransport();
      final registry = LspJsonRpcSessionRegistry(
        executableProbe: const _AvailableLspServerExecutableProbe(),
        definitionRequestTimeout: const Duration(milliseconds: 100),
        transportStarter:
            ({required command, required workingDirectory}) async {
              return fakeTransport;
            },
      );
      addTearDown(registry.close);

      final definitionsFuture = registry.collectDefinitions(
        projectRoot: root.path,
        path: changedFile.path,
        line: 1,
        character: 16,
      );
      await _pumpEventQueue();
      _completeInitialize(fakeTransport);
      await _pumpEventQueue();
      final sentMessages = _decodeWrittenMessages(fakeTransport.writes);
      expect(sentMessages.map((message) => message['method']), [
        'initialize',
        'initialized',
        'textDocument/didOpen',
        'textDocument/definition',
      ]);
      final request = sentMessages.last;
      final params = request['params'] as Map<String, dynamic>;
      expect(params['position'], containsPair('line', 1));
      expect(params['position'], containsPair('character', 16));
      fakeTransport.emitStdout(
        LspJsonRpcMessageCodec.encode({
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': [
            {
              'uri': changedFile.uri.toString(),
              'range': {
                'start': {'line': 0, 'character': 13},
                'end': {'line': 0, 'character': 20},
              },
            },
          ],
        }),
      );

      final definitions = await definitionsFuture;

      expect(definitions, hasLength(1));
      expect(definitions!.single.uri, changedFile.uri.toString());
      expect(definitions.single.startLine, 0);
      expect(definitions.single.startCharacter, 13);
    });

    test(
      'reports unavailable when no language server command resolves',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_lsp_session_registry_unavailable_',
        );
        addTearDown(() => root.delete(recursive: true));
        final changedFile = await _writeFile(root, 'README.md', '# Notes\n');
        final registry = LspJsonRpcSessionRegistry(
          executableProbe: const _AvailableLspServerExecutableProbe(),
          transportStarter: ({required command, required workingDirectory}) {
            throw StateError('Should not start transport.');
          },
        );
        addTearDown(registry.close);

        final readiness = await registry.ensureReady(
          projectRoot: root.path,
          changedPaths: [changedFile.path],
        );

        expect(readiness.ok, isFalse);
        expect(readiness.code, 'language_server_not_resolved');
      },
    );

    test('reports missing executables before starting transport', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_session_registry_missing_executable_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print(x)\n');
      final registry = LspJsonRpcSessionRegistry(
        executableProbe: const _MissingLspServerExecutableProbe(),
        transportStarter: ({required command, required workingDirectory}) {
          throw StateError('Should not start transport.');
        },
      );
      addTearDown(registry.close);

      final readiness = await registry.ensureReady(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(readiness.ok, isFalse);
      expect(readiness.languageId, 'python');
      expect(readiness.code, 'language_server_executable_not_found');
      expect(readiness.error, contains('pyright-langserver'));
      expect(readiness.metadata, isNotNull);
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

void _completeInitialize(_FakeLspJsonRpcByteTransport transport) {
  final sentMessages = _decodeWrittenMessages(transport.writes);
  final initialize = sentMessages.lastWhere(
    (message) => message['method'] == 'initialize',
  );
  transport.emitStdout(
    LspJsonRpcMessageCodec.encode({
      'jsonrpc': '2.0',
      'id': initialize['id'],
      'result': {'capabilities': <String, dynamic>{}},
    }),
  );
}

Future<void> _pumpEventQueue() {
  return Future<void>.delayed(Duration.zero);
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

  @override
  int get pid => 4321;

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
    await _stdout.close();
    await _stderr.close();
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(-1);
    }
    return true;
  }

  void emitStdout(List<int> bytes) {
    _stdout.add(bytes);
  }
}

class _AvailableLspServerExecutableProbe implements LspServerExecutableProbe {
  const _AvailableLspServerExecutableProbe();

  @override
  Future<LspServerExecutableAvailability> check(
    LspServerCommand command,
  ) async {
    return LspServerExecutableAvailability.available(
      executable: command.executable,
      resolvedPath: '/usr/bin/${command.executable}',
    );
  }
}

class _MissingLspServerExecutableProbe implements LspServerExecutableProbe {
  const _MissingLspServerExecutableProbe();

  @override
  Future<LspServerExecutableAvailability> check(
    LspServerCommand command,
  ) async {
    return LspServerExecutableAvailability.unavailable(
      executable: command.executable,
      error: '${command.executable} is not installed.',
    );
  }
}
