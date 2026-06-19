import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/lsp_server_process_manager.dart';

void main() {
  group('LspServerCommandResolver', () {
    test('resolves the FVM Dart language server for Dart projects', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_resolver_dart_',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/.fvm').create(recursive: true);
      await File('${root.path}/.fvm/fvm_config.json').writeAsString('{}');
      final changedFile = await _writeFile(
        root,
        'lib/main.dart',
        'void main() {}\n',
      );

      final command = const LspServerCommandResolver().resolve(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(command, isNotNull);
      expect(command!.languageId, 'dart');
      expect(command.command, 'fvm dart language-server --protocol=lsp');
      expect(command.workingDirectory, root.absolute.path);
    });

    test('resolves TypeScript language server commands', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_resolver_typescript_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(
        root,
        'src/app.ts',
        'const app = true;\n',
      );

      final command = const LspServerCommandResolver().resolve(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(command, isNotNull);
      expect(command!.languageId, 'typescript');
      expect(command.command, 'typescript-language-server --stdio');
      expect(command.workingDirectory, root.absolute.path);
    });
  });

  group('LspServerProcessManager', () {
    test('starts and reuses a running language server process', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_manager_reuse_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print("hi")\n');
      final tools = _FakeBackgroundProcessTools(
        startResults: [
          jsonEncode({'ok': true, 'status': 'running', 'job_id': 'lsp_1'}),
        ],
        statusResults: {
          'lsp_1': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': 'lsp_1',
          }),
        },
      );
      final manager = LspServerProcessManager(
        backgroundProcessTools: tools,
        executableProbe: const _AvailableLspServerExecutableProbe(),
      );

      final first = await manager.ensureStarted(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      final second = await manager.ensureStarted(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(first.ok, isTrue);
      expect(first.session!.jobId, 'lsp_1');
      expect(second.ok, isTrue);
      expect(second.session!.jobId, 'lsp_1');
      expect(second.previousStatus, 'running');
      expect(tools.startCalls, hasLength(1));
      expect(tools.startCalls.single['command'], 'pyright-langserver --stdio');
      expect(tools.startCalls.single['label'], 'LSP python');
    });

    test('replaces an exited language server process', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_manager_restart_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(
        root,
        'Sources/App/main.swift',
        'print("hi")\n',
      );
      final tools = _FakeBackgroundProcessTools(
        startResults: [
          jsonEncode({'ok': true, 'status': 'running', 'job_id': 'lsp_1'}),
          jsonEncode({'ok': true, 'status': 'running', 'job_id': 'lsp_2'}),
        ],
        statusResults: {
          'lsp_1': jsonEncode({
            'ok': true,
            'status': 'exited',
            'job_id': 'lsp_1',
            'exit_code': 1,
          }),
        },
      );
      final manager = LspServerProcessManager(
        backgroundProcessTools: tools,
        executableProbe: const _AvailableLspServerExecutableProbe(),
      );

      final first = await manager.ensureStarted(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );
      final second = await manager.ensureStarted(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(first.session!.jobId, 'lsp_1');
      expect(second.ok, isTrue);
      expect(second.session!.jobId, 'lsp_2');
      expect(tools.startCalls, hasLength(2));
    });

    test('does not start a process when no language server matches', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_manager_unmatched_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'README.md', '# Notes\n');
      final tools = _FakeBackgroundProcessTools(startResults: const []);
      final manager = LspServerProcessManager(
        backgroundProcessTools: tools,
        executableProbe: const _AvailableLspServerExecutableProbe(),
      );

      final result = await manager.ensureStarted(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(result.ok, isFalse);
      expect(result.code, 'language_server_not_resolved');
      expect(tools.startCalls, isEmpty);
    });

    test('reports unavailable when background tools are unsupported', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_manager_unsupported_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print("hi")\n');
      final tools = _FakeBackgroundProcessTools(
        startResults: const [],
        supported: false,
      );
      final manager = LspServerProcessManager(
        backgroundProcessTools: tools,
        executableProbe: const _AvailableLspServerExecutableProbe(),
      );

      final result = await manager.ensureStarted(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(result.ok, isFalse);
      expect(result.code, 'background_process_unavailable');
      expect(tools.startCalls, isEmpty);
    });

    test('exposes process start results as LSP readiness metadata', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_manager_readiness_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(root, 'src/app.py', 'print("hi")\n');
      final tools = _FakeBackgroundProcessTools(
        startResults: [
          jsonEncode({'ok': true, 'status': 'running', 'job_id': 'lsp_1'}),
        ],
      );
      final manager = LspServerProcessManager(
        backgroundProcessTools: tools,
        executableProbe: const _AvailableLspServerExecutableProbe(),
      );

      final readiness = await manager.ensureReady(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(readiness.ok, isTrue);
      expect(readiness.status, 'ready');
      expect(readiness.languageId, 'python');
      expect(readiness.metadata, isNotNull);
      expect(readiness.metadata!['session'], isA<Map<String, dynamic>>());
    });

    test('reports missing executables before starting a process', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_lsp_manager_missing_executable_',
      );
      addTearDown(() => root.delete(recursive: true));
      final changedFile = await _writeFile(
        root,
        'src/app.ts',
        'const x = 1;\n',
      );
      final tools = _FakeBackgroundProcessTools(startResults: const []);
      final manager = LspServerProcessManager(
        backgroundProcessTools: tools,
        executableProbe: const _MissingLspServerExecutableProbe(),
      );

      final result = await manager.ensureStarted(
        projectRoot: root.path,
        changedPaths: [changedFile.path],
      );

      expect(result.ok, isFalse);
      expect(result.languageId, 'typescript');
      expect(result.code, 'language_server_executable_not_found');
      expect(result.error, contains('typescript-language-server'));
      expect(result.metadata, isNotNull);
      expect(tools.startCalls, isEmpty);
    });
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

class _FakeBackgroundProcessTools extends BackgroundProcessTools {
  _FakeBackgroundProcessTools({
    required this.startResults,
    this.statusResults = const {},
    this.supported = true,
  });

  final List<String> startResults;
  final Map<String, String> statusResults;
  final bool supported;
  final List<Map<String, dynamic>> startCalls = [];
  var _startIndex = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<String> start({
    required String command,
    required String workingDirectory,
    String? label,
  }) async {
    final call = {'command': command, 'working_directory': workingDirectory};
    if (label != null) {
      call['label'] = label;
    }
    startCalls.add(call);
    if (_startIndex >= startResults.length) {
      return jsonEncode({
        'ok': false,
        'code': 'start_not_configured',
        'error': 'No start result configured.',
      });
    }
    final result = startResults[_startIndex];
    _startIndex += 1;
    return result;
  }

  @override
  Future<String> status({required String jobId, int? tailChars}) async {
    return statusResults[jobId] ??
        jsonEncode({
          'ok': false,
          'code': 'job_not_found',
          'job_id': jobId,
          'error': 'No background process job exists for job_id: $jobId',
        });
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
