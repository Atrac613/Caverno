import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/mcp_response_limits.dart';
import 'package:caverno/features/chat/data/datasources/mcp_stdio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('McpBoundedLineDecoder', () {
    test('accepts a line exactly at the byte ceiling', () async {
      final lines = await Stream<List<int>>.fromIterable([
        utf8.encode('1234'),
        utf8.encode('\n'),
      ]).transform(McpBoundedLineDecoder(maxLineBytes: 4)).toList();

      expect(lines, ['1234']);
    });

    test('counts UTF-8 bytes rather than decoded characters', () async {
      final lines = await Stream<List<int>>.value(
        utf8.encode('éé\n'),
      ).transform(McpBoundedLineDecoder(maxLineBytes: 4)).toList();

      expect(lines, ['éé']);
      await expectLater(
        Stream<List<int>>.value(
          utf8.encode('éé\n'),
        ).transform(McpBoundedLineDecoder(maxLineBytes: 3)).drain<void>(),
        throwsA(isA<McpResponseLimitException>()),
      );
    });
  });

  group('MCP tool text limits', () {
    test('accepts aggregate text exactly at the output ceiling', () {
      expect(
        extractBoundedMcpTextContent([
          {'type': 'text', 'text': 'abc'},
          {'type': 'text', 'text': 'def'},
        ], maxCharacters: 7),
        'abc\ndef',
      );
    });
  });

  group('McpStdioClient limits', () {
    test('terminates the process when stdout crosses the line limit', () async {
      final process = _FakeProcess();
      final client = _clientFor(process, maxLineBytes: 128);
      addTearDown(() => _closeClientAndProcess(client, process));

      final initialize = client.initialize();
      await process.firstStdinWrite;
      process.emitStdout(List<int>.filled(129, 0x61));

      await expectLater(
        initialize,
        throwsA(
          isA<McpResponseLimitException>().having(
            (error) => error.message,
            'message',
            contains('stdout line exceeded 128 bytes'),
          ),
        ),
      );
      expect(process.wasKilled, isTrue);
    });

    test('terminates the process when stderr crosses the line limit', () async {
      final process = _FakeProcess();
      final client = _clientFor(process, maxLineBytes: 128);
      addTearDown(() => _closeClientAndProcess(client, process));

      final initialize = client.initialize();
      await process.firstStdinWrite;
      process.emitStderr(List<int>.filled(129, 0x62));

      await expectLater(
        initialize,
        throwsA(
          isA<McpResponseLimitException>().having(
            (error) => error.message,
            'message',
            contains('stderr line exceeded 128 bytes'),
          ),
        ),
      );
      expect(process.wasKilled, isTrue);
    });

    test('rejects excessive aggregate tool text content', () async {
      final process = _FakeProcess();
      final client = _clientFor(
        process,
        maxLineBytes: 1024,
        maxToolContentCharacters: 6,
      );
      addTearDown(() => _closeClientAndProcess(client, process));

      final initialize = client.initialize();
      await process.firstStdinWrite;
      process.emitStdout(
        utf8.encode('{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{}}}\n'),
      );
      await initialize;

      final call = client.callTool(name: 'oversized', arguments: const {});
      process.emitStdout(
        utf8.encode(
          '{"jsonrpc":"2.0","id":2,"result":{"content":['
          '{"type":"text","text":"abc"},'
          '{"type":"text","text":"def"}'
          ']}}\n',
        ),
      );

      await expectLater(
        call,
        throwsA(
          isA<McpResponseLimitException>().having(
            (error) => error.message,
            'message',
            contains('tool text exceeded 6 characters'),
          ),
        ),
      );
      expect(process.wasKilled, isFalse);
    });

    test('rejects non-positive limits', () {
      final process = _FakeProcess();
      addTearDown(process.close);

      expect(() => _clientFor(process, maxLineBytes: 0), throwsArgumentError);
      expect(
        () => _clientFor(process, maxToolContentCharacters: 0),
        throwsArgumentError,
      );
    });
  });
}

Future<void> _closeClientAndProcess(
  McpStdioClient client,
  _FakeProcess process,
) async {
  final dispose = client.dispose();
  await process.close();
  await dispose;
}

McpStdioClient _clientFor(
  _FakeProcess process, {
  int maxLineBytes = 1024,
  int maxToolContentCharacters = 1024,
}) {
  return McpStdioClient(
    command: 'fake-mcp-server',
    maxLineBytes: maxLineBytes,
    maxToolContentCharacters: maxToolContentCharacters,
    processStarter: (_, _, _) async => process,
  );
}

class _FakeProcess implements Process {
  _FakeProcess()
    : _stdoutController = StreamController<List<int>>.broadcast(),
      _stderrController = StreamController<List<int>>.broadcast(),
      _stdinConsumer = _RecordingConsumer() {
    _stdin = IOSink(_stdinConsumer);
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final _RecordingConsumer _stdinConsumer;
  final Completer<int> _exitCode = Completer<int>();
  late final IOSink _stdin;
  bool wasKilled = false;

  Future<void> get firstStdinWrite => _stdinConsumer.firstWrite;

  void emitStdout(List<int> bytes) => _stdoutController.add(bytes);

  void emitStderr(List<int> bytes) => _stderrController.add(bytes);

  Future<void> close() async {
    await _stdoutController.close();
    await _stderrController.close();
    if (!_exitCode.isCompleted) _exitCode.complete(0);
  }

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 1234;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    if (!_exitCode.isCompleted) _exitCode.complete(-1);
    return true;
  }
}

class _RecordingConsumer implements StreamConsumer<List<int>> {
  final Completer<void> _firstWrite = Completer<void>();

  Future<void> get firstWrite => _firstWrite.future;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      if (bytes.isNotEmpty && !_firstWrite.isCompleted) {
        _firstWrite.complete();
      }
    }
  }

  @override
  Future<void> close() async {
    if (!_firstWrite.isCompleted) _firstWrite.complete();
  }
}
