import 'dart:async';
import 'dart:io';

import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/lsp_diagnostic_feedback_provider.dart';
import 'lsp_json_rpc_diagnostic_bridge.dart';
import 'lsp_json_rpc_process_transport.dart';
import 'lsp_server_command_resolver.dart';

typedef LspJsonRpcByteTransportStarter =
    Future<LspJsonRpcByteTransport> Function({
      required String command,
      required String workingDirectory,
    });

class LspJsonRpcSessionStartResult {
  const LspJsonRpcSessionStartResult({
    required this.ok,
    required this.status,
    this.session,
    this.languageId,
    this.code,
    this.error,
    this.reused = false,
    this.metadata,
  });

  final bool ok;
  final String status;
  final LspJsonRpcSession? session;
  final String? languageId;
  final String? code;
  final String? error;
  final bool reused;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() {
    return {
      'ok': ok,
      'status': status,
      if (languageId != null) 'language_id': languageId,
      if (session != null) 'session': session!.toJson(),
      if (code != null) 'code': code,
      if (error != null) 'error': error,
      'reused': reused,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class LspJsonRpcSessionRegistry
    implements LspDiagnosticClient, LspServerReadinessProbe {
  LspJsonRpcSessionRegistry({
    LspServerCommandResolver commandResolver = const LspServerCommandResolver(),
    LspServerExecutableProbe executableProbe =
        const PathLspServerExecutableProbe(),
    LspJsonRpcByteTransportStarter? transportStarter,
    this.diagnosticSettleTimeout = const Duration(milliseconds: 600),
    this.diagnosticPollInterval = const Duration(milliseconds: 25),
    this.symbolRequestTimeout = const Duration(milliseconds: 800),
    this.definitionRequestTimeout = const Duration(milliseconds: 800),
    this.initializeTimeout = const Duration(seconds: 2),
  }) : _commandResolver = commandResolver,
       _executableProbe = executableProbe,
       _transportStarter =
           transportStarter ?? ProcessLspJsonRpcByteTransport.startShellCommand;

  final LspServerCommandResolver _commandResolver;
  final LspServerExecutableProbe _executableProbe;
  final LspJsonRpcByteTransportStarter _transportStarter;
  final Duration diagnosticSettleTimeout;
  final Duration diagnosticPollInterval;
  final Duration symbolRequestTimeout;
  final Duration definitionRequestTimeout;
  final Duration initializeTimeout;
  final Map<String, LspJsonRpcSession> _sessions = {};

  @override
  String get providerName => 'lsp_json_rpc';

  @override
  bool get supportsDocumentSymbols => true;

  @override
  bool get supportsGoToDefinition => true;

  List<LspJsonRpcSession> get sessions =>
      List<LspJsonRpcSession>.unmodifiable(_sessions.values);

  Future<LspJsonRpcSessionStartResult> ensureSession({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    final root = Directory(projectRoot).absolute.path;
    final command = _commandResolver.resolve(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    if (command == null) {
      return const LspJsonRpcSessionStartResult(
        ok: false,
        status: 'unavailable',
        code: 'language_server_not_resolved',
        error: 'No language server command could be resolved.',
      );
    }
    final availability = await _executableProbe.check(command);
    if (!availability.available) {
      return LspJsonRpcSessionStartResult(
        ok: false,
        status: 'unavailable',
        languageId: command.languageId,
        code: availability.code ?? 'language_server_executable_not_found',
        error: availability.error,
        metadata: {
          'command': command.command,
          'working_directory': command.workingDirectory,
          'executable': availability.toJson(),
        },
      );
    }

    final key = _sessionKey(projectRoot: root, languageId: command.languageId);
    final existing = _sessions[key];
    if (existing != null && !existing.isClosed) {
      await existing.syncChangedFiles(changedPaths: changedPaths);
      return LspJsonRpcSessionStartResult(
        ok: true,
        status: 'ready',
        languageId: command.languageId,
        session: existing,
        reused: true,
      );
    }

    final byteTransport = await _transportStarter(
      command: command.command,
      workingDirectory: command.workingDirectory,
    );
    final bridge = LspJsonRpcDiagnosticBridge(
      providerName: '${command.languageId}_language_server',
      languageId: command.languageId,
      supportsDocumentSymbols: true,
      supportsGoToDefinition: true,
    );
    final transport = LspJsonRpcProcessTransport(
      bridge: bridge,
      byteTransport: byteTransport,
    );
    final session = LspJsonRpcSession(
      command: command,
      projectRoot: root,
      bridge: bridge,
      transport: transport,
      initializeTimeout: initializeTimeout,
    );
    _sessions[key] = session;
    await session.initialize();
    await session.syncChangedFiles(changedPaths: changedPaths);
    return LspJsonRpcSessionStartResult(
      ok: true,
      status: 'ready',
      languageId: command.languageId,
      session: session,
    );
  }

  @override
  Future<LspServerReadiness> ensureReady({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    try {
      final result = await ensureSession(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
      );
      return LspServerReadiness(
        ok: result.ok,
        status: result.status,
        languageId: result.languageId,
        code: result.code,
        error: result.error,
        metadata: result.toJson(),
      );
    } catch (error) {
      return LspServerReadiness(
        ok: false,
        status: 'unavailable',
        code: 'language_server_session_start_failed',
        error: error.toString(),
      );
    }
  }

  @override
  Future<List<LspDiagnostic>?> collectDiagnostics({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    final root = Directory(projectRoot).absolute.path;
    final command = _commandResolver.resolve(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    if (command == null) {
      return null;
    }
    final session =
        _sessions[_sessionKey(
          projectRoot: root,
          languageId: command.languageId,
        )];
    if (session == null || session.isClosed) {
      return null;
    }
    await session.waitForDiagnostics(
      changedPaths: changedPaths,
      timeout: diagnosticSettleTimeout,
      pollInterval: diagnosticPollInterval,
    );
    return session.bridge.collectDiagnostics(
      projectRoot: root,
      changedPaths: changedPaths,
    );
  }

  Future<List<LspDocumentSymbol>?> collectDocumentSymbols({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    final result = await ensureSession(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
    );
    final session = result.session;
    if (!result.ok || session == null || session.isClosed) {
      return null;
    }
    return session.collectDocumentSymbols(
      changedPaths: changedPaths,
      timeout: symbolRequestTimeout,
    );
  }

  Future<List<LspDefinitionLocation>?> collectDefinitions({
    required String projectRoot,
    required String path,
    required int line,
    required int character,
  }) async {
    final result = await ensureSession(
      projectRoot: projectRoot,
      changedPaths: [path],
    );
    final session = result.session;
    if (!result.ok || session == null || session.isClosed) {
      return null;
    }
    return session.collectDefinitions(
      path: path,
      line: line,
      character: character,
      timeout: definitionRequestTimeout,
    );
  }

  Future<void> close() async {
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    await Future.wait(sessions.map((session) => session.close()));
  }

  String _sessionKey({
    required String projectRoot,
    required String languageId,
  }) {
    return '${DartProjectPath.pathKey(projectRoot)}|$languageId';
  }
}

class LspJsonRpcSession {
  LspJsonRpcSession({
    required this.command,
    required this.projectRoot,
    required this.bridge,
    required this.transport,
    required this.initializeTimeout,
  });

  final LspServerCommand command;
  final String projectRoot;
  final LspJsonRpcDiagnosticBridge bridge;
  final LspJsonRpcProcessTransport transport;
  final Duration initializeTimeout;
  final Map<String, int> _documentVersionsByUri = {};
  var _nextRequestId = 1;
  var _closed = false;

  bool get isClosed => _closed;

  Future<void> initialize() async {
    if (initializeTimeout <= Duration.zero || _closed) {
      return;
    }
    final id = _nextRequestId++;
    final responseCompleter = Completer<Map<String, dynamic>>();
    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = transport.messages.listen(
      (message) {
        if (message['id'] == id && !responseCompleter.isCompleted) {
          responseCompleter.complete(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.completeError(error, stackTrace);
        }
      },
    );
    try {
      await transport.sendInitialize(
        id: id,
        rootUri: Directory(projectRoot).absolute.uri.toString(),
        processId: transport.pid,
      );
      await responseCompleter.future.timeout(initializeTimeout);
      await transport.sendInitialized();
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> syncChangedFiles({
    required Iterable<String> changedPaths,
  }) async {
    for (final document in _changedDocuments(changedPaths)) {
      final previousVersion = _documentVersionsByUri[document.uri];
      final version = (previousVersion ?? 0) + 1;
      if (previousVersion == null) {
        await transport.sendDidOpen(
          uri: document.uri,
          text: document.text,
          version: version,
        );
      } else {
        await transport.sendDidChange(
          uri: document.uri,
          text: document.text,
          version: version,
        );
      }
      _documentVersionsByUri[document.uri] = version;
    }
  }

  Future<void> waitForDiagnostics({
    required Iterable<String> changedPaths,
    required Duration timeout,
    required Duration pollInterval,
  }) async {
    if (timeout <= Duration.zero || _closed) {
      return;
    }
    final documentUris = _changedDocuments(
      changedPaths,
    ).map((document) => document.uri).toList(growable: false);
    if (documentUris.isEmpty ||
        bridge.hasPublishedDiagnosticsForUris(documentUris)) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    while (!_closed && stopwatch.elapsed < timeout) {
      final remaining = timeout - stopwatch.elapsed;
      final delay = pollInterval <= Duration.zero || pollInterval > remaining
          ? remaining
          : pollInterval;
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (bridge.hasPublishedDiagnosticsForUris(documentUris)) {
        return;
      }
    }
  }

  Future<List<LspDocumentSymbol>> collectDocumentSymbols({
    required Iterable<String> changedPaths,
    required Duration timeout,
  }) async {
    final symbols = <LspDocumentSymbol>[];
    for (final document in _changedDocuments(changedPaths)) {
      final documentSymbols = await _requestDocumentSymbols(
        document,
        timeout: timeout,
      );
      if (documentSymbols == null) {
        continue;
      }
      symbols.addAll(documentSymbols);
    }
    return symbols;
  }

  Future<List<LspDocumentSymbol>?> _requestDocumentSymbols(
    _LspDocumentSnapshot document, {
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero || _closed) {
      return null;
    }
    final id = _nextRequestId++;
    final responseCompleter = Completer<Map<String, dynamic>>();
    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = transport.messages.listen(
      (message) {
        if (message['id'] == id && !responseCompleter.isCompleted) {
          responseCompleter.complete(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.completeError(error, stackTrace);
        }
      },
    );
    try {
      await transport.sendDocumentSymbols(id: id, uri: document.uri);
      final response = await responseCompleter.future.timeout(timeout);
      return bridge.documentSymbolsFromResponse(
        uri: document.uri,
        response: response,
      );
    } on Object {
      return null;
    } finally {
      await subscription.cancel();
    }
  }

  Future<List<LspDefinitionLocation>> collectDefinitions({
    required String path,
    required int line,
    required int character,
    required Duration timeout,
  }) async {
    final document = _documentSnapshot(path);
    if (document == null) {
      return const [];
    }
    final definitions = await _requestDefinitions(
      document,
      line: line,
      character: character,
      timeout: timeout,
    );
    return definitions ?? const [];
  }

  Future<List<LspDefinitionLocation>?> _requestDefinitions(
    _LspDocumentSnapshot document, {
    required int line,
    required int character,
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero || _closed) {
      return null;
    }
    final id = _nextRequestId++;
    final responseCompleter = Completer<Map<String, dynamic>>();
    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = transport.messages.listen(
      (message) {
        if (message['id'] == id && !responseCompleter.isCompleted) {
          responseCompleter.complete(message);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!responseCompleter.isCompleted) {
          responseCompleter.completeError(error, stackTrace);
        }
      },
    );
    try {
      await transport.sendDefinition(
        id: id,
        uri: document.uri,
        line: line,
        character: character,
      );
      final response = await responseCompleter.future.timeout(timeout);
      return bridge.definitionLocationsFromResponse(response: response);
    } on Object {
      return null;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await transport.close();
  }

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _closed = true;
    return transport.kill(signal);
  }

  Map<String, dynamic> toJson() {
    return {
      'language_id': command.languageId,
      'project_root': projectRoot,
      'command': command.command,
      'working_directory': command.workingDirectory,
      'pid': transport.pid,
      'open_document_count': _documentVersionsByUri.length,
      'closed': _closed,
    };
  }

  List<_LspDocumentSnapshot> _changedDocuments(Iterable<String> changedPaths) {
    final documents = <_LspDocumentSnapshot>[];
    final seen = <String>{};
    for (final rawPath in changedPaths) {
      final absolutePath = DartProjectPath.resolvePath(
        rawPath,
        projectRoot: projectRoot,
      );
      if (absolutePath == null ||
          !DartProjectPath.isInsideRoot(absolutePath, projectRoot)) {
        continue;
      }
      final file = File(absolutePath);
      if (!file.existsSync()) {
        continue;
      }
      final key = DartProjectPath.pathKey(file.path);
      if (!seen.add(key)) {
        continue;
      }
      documents.add(
        _LspDocumentSnapshot(
          uri: file.absolute.uri.toString(),
          text: file.readAsStringSync(),
        ),
      );
    }
    documents.sort((a, b) => a.uri.compareTo(b.uri));
    return documents;
  }

  _LspDocumentSnapshot? _documentSnapshot(String path) {
    final absolutePath = DartProjectPath.resolvePath(
      path,
      projectRoot: projectRoot,
    );
    if (absolutePath == null ||
        !DartProjectPath.isInsideRoot(absolutePath, projectRoot)) {
      return null;
    }
    final file = File(absolutePath);
    if (!file.existsSync()) {
      return null;
    }
    return _LspDocumentSnapshot(
      uri: file.absolute.uri.toString(),
      text: file.readAsStringSync(),
    );
  }
}

class _LspDocumentSnapshot {
  const _LspDocumentSnapshot({required this.uri, required this.text});

  final String uri;
  final String text;
}
