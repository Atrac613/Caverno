import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/utils/logger.dart';
import 'mcp_client.dart';

/// MCP client that communicates with a server process via stdio (stdin/stdout).
///
/// The child process receives JSON-RPC 2.0 requests on stdin (one per line)
/// and writes JSON-RPC 2.0 responses on stdout (one per line).
class McpStdioClient implements McpClientBase {
  McpStdioClient({
    required this.command,
    this.args = const [],
    this.env,
  });

  final String command;
  final List<String> args;
  final Map<String, String>? env;

  Process? _process;
  int _nextId = 1;
  bool _disposed = false;

  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  static const _requestTimeout = Duration(seconds: 30);

  @override
  String get identifier =>
      args.isEmpty ? command.trim() : '${command.trim()} ${args.join(' ')}';

  @override
  Future<void> initialize() async {
    if (_disposed) throw StateError('Client has been disposed');
    if (_process != null) return;

    appLog('[McpStdioClient] Starting process: $identifier');

    final mergedEnv = {...Platform.environment, ...?env};
    try {
      _process = await Process.start(
        command,
        args,
        environment: mergedEnv,
      );
    } on ProcessException catch (error) {
      throw ProcessException(
        error.executable,
        error.arguments,
        _describeStartFailure(error),
        error.errorCode,
      );
    }

    // Listen for unexpected exit.
    _process!.exitCode.then((code) {
      if (!_disposed) {
        appLog('[McpStdioClient] Process exited unexpectedly: code=$code');
        _failAllPending('Process exited with code $code');
      }
    });

    // Parse stdout as newline-delimited JSON-RPC responses.
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine);

    // Log stderr for diagnostics.
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      appLog('[McpStdioClient] stderr: $line');
    });

    // Send initialize request.
    final result = await _sendRequest('initialize', params: {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'caverno', 'version': '1.0.0'},
    });

    appLog('[McpStdioClient] Server info: ${result['result']}');

    // Send initialized notification (no id, fire-and-forget).
    _writeMessage({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
  }

  @override
  Future<List<McpTool>> listTools() async {
    if (_process == null) await initialize();

    final response = await _sendRequest('tools/list');
    final result = response['result'] as Map<String, dynamic>?;
    if (result == null) return [];

    final tools = result['tools'] as List<dynamic>? ?? [];
    appLog('[McpStdioClient] Found ${tools.length} tools');
    return tools
        .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (_process == null) await initialize();

    appLog('[McpStdioClient] callTool: $name');
    final response = await _sendRequest('tools/call', params: {
      'name': name,
      'arguments': arguments,
    });

    if (response.containsKey('error')) {
      final error = response['error'] as Map<String, dynamic>;
      throw Exception('MCP error: ${error['message']}');
    }

    final result = response['result'] as Map<String, dynamic>?;
    if (result == null) return '';

    final content = result['content'] as List<dynamic>? ?? [];
    return content
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join('\n');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    appLog('[McpStdioClient] Disposing: $identifier');
    _failAllPending('Client disposed');

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    try {
      _process?.stdin.close();
    } catch (_) {}
    _process?.kill();
    _process = null;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final id = json['id'];

      if (id is int && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(json);
      } else if (id != null) {
        appLog('[McpStdioClient] Received response for unknown id: $id');
      }
      // Notifications (no id) are silently ignored for now.
    } catch (e) {
      appLog('[McpStdioClient] Failed to parse stdout line: $e');
    }
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    if (_disposed) throw StateError('Client has been disposed');
    if (_process == null) throw StateError('Process not started');

    final id = _nextId++;
    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
    };
    if (params != null) message['params'] = params;

    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _writeMessage(message);

    try {
      return await completer.future.timeout(_requestTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw TimeoutException('MCP request "$method" timed out', _requestTimeout);
    }
  }

  void _writeMessage(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    _process!.stdin.writeln(encoded);
  }

  void _failAllPending(String reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception(reason));
      }
    }
    _pending.clear();
  }

  String _describeStartFailure(ProcessException error) {
    final message = error.message.trim();
    if (Platform.isMacOS &&
        message.toLowerCase().contains('operation not permitted')) {
      return '$message. macOS sandboxing is blocking child process launch. '
          'Set ENABLE_APP_SANDBOX = NO for the Runner target to allow '
          'stdio MCP servers.';
    }
    return message;
  }
}
