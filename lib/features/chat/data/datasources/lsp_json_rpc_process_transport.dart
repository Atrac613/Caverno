import 'dart:async';
import 'dart:io';

import '../../../../core/services/login_shell_environment.dart';
import 'lsp_json_rpc_diagnostic_bridge.dart';

abstract interface class LspJsonRpcByteTransport {
  int get pid;

  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  Future<int> get exitCode;

  Future<void> write(List<int> bytes);

  Future<void> close();

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

class ProcessLspJsonRpcByteTransport implements LspJsonRpcByteTransport {
  ProcessLspJsonRpcByteTransport._(this._process);

  final Process _process;

  static Future<ProcessLspJsonRpcByteTransport> startShellCommand({
    required String command,
    required String workingDirectory,
  }) async {
    final normalizedCommand = _normalizeCommand(command);
    if (normalizedCommand.isEmpty) {
      throw ArgumentError.value(command, 'command', 'Command is required.');
    }
    final shellExecutable = Platform.isWindows ? 'cmd' : 'sh';
    final shellArgs = Platform.isWindows
        ? ['/C', normalizedCommand]
        : ['-c', normalizedCommand];
    final process = await Process.start(
      shellExecutable,
      shellArgs,
      workingDirectory: Directory(workingDirectory).absolute.path,
      environment: await LoginShellEnvironment.instance.environment(),
    );
    return ProcessLspJsonRpcByteTransport._(process);
  }

  static final RegExp _modelControlTokenPattern = RegExp(r'<\|[^>]*\|>');

  static String _normalizeCommand(String command) {
    return command.replaceAll(_modelControlTokenPattern, '').trim();
  }

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> write(List<int> bytes) async {
    _process.stdin.add(bytes);
    await _process.stdin.flush();
  }

  @override
  Future<void> close() async {
    await _process.stdin.close();
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }
}

class LspJsonRpcProcessTransport {
  LspJsonRpcProcessTransport({
    required LspJsonRpcDiagnosticBridge bridge,
    required LspJsonRpcByteTransport byteTransport,
  }) : _bridge = bridge,
       _byteTransport = byteTransport {
    _stdoutSubscription = _byteTransport.stdout.listen(
      _handleStdoutBytes,
      onError: _messages.addError,
    );
    _stderrSubscription = _byteTransport.stderr.listen(
      _stderrController.add,
      onError: _stderrController.addError,
    );
  }

  final LspJsonRpcDiagnosticBridge _bridge;
  final LspJsonRpcByteTransport _byteTransport;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;

  int get pid => _byteTransport.pid;

  Future<int> get exitCode => _byteTransport.exitCode;

  Stream<Map<String, dynamic>> get messages => _messages.stream;

  Stream<List<int>> get stderr => _stderrController.stream;

  Future<void> send(Map<String, dynamic> message) {
    return _byteTransport.write(LspJsonRpcMessageCodec.encode(message));
  }

  Future<void> sendInitialize({
    required Object id,
    required String rootUri,
    int? processId,
  }) {
    return send(
      _bridge.initializeRequest(id: id, rootUri: rootUri, processId: processId),
    );
  }

  Future<void> sendInitialized() {
    return send(_bridge.initializedNotification());
  }

  Future<void> sendDidOpen({
    required String uri,
    required String text,
    int version = 1,
  }) {
    return send(
      _bridge.didOpenNotification(uri: uri, text: text, version: version),
    );
  }

  Future<void> sendDidChange({
    required String uri,
    required String text,
    required int version,
  }) {
    return send(
      _bridge.didChangeNotification(uri: uri, text: text, version: version),
    );
  }

  Future<void> sendDocumentSymbols({required Object id, required String uri}) {
    return send(_bridge.documentSymbolRequest(id: id, uri: uri));
  }

  Future<void> sendDefinition({
    required Object id,
    required String uri,
    required int line,
    required int character,
  }) {
    return send(
      _bridge.definitionRequest(
        id: id,
        uri: uri,
        line: line,
        character: character,
      ),
    );
  }

  Future<void> close() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _byteTransport.close();
    await _messages.close();
    await _stderrController.close();
  }

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _byteTransport.kill(signal);
  }

  void _handleStdoutBytes(List<int> bytes) {
    try {
      final decodedMessages = _bridge.handleIncomingBytes(bytes);
      for (final message in decodedMessages) {
        _messages.add(message);
      }
    } catch (error, stackTrace) {
      _messages.addError(error, stackTrace);
    }
  }
}
