import 'dart:convert';
import 'dart:io';

import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/lsp_diagnostic_feedback_provider.dart';
import 'background_process_tools.dart';
import 'lsp_server_command_resolver.dart';

export 'lsp_server_command_resolver.dart';

class LspServerProcessSession {
  const LspServerProcessSession({
    required this.languageId,
    required this.projectRoot,
    required this.command,
    required this.workingDirectory,
    required this.jobId,
    required this.status,
    this.duplicateExisting = false,
  });

  final String languageId;
  final String projectRoot;
  final String command;
  final String workingDirectory;
  final String jobId;
  final String status;
  final bool duplicateExisting;

  LspServerProcessSession copyWith({String? status, bool? duplicateExisting}) {
    return LspServerProcessSession(
      languageId: languageId,
      projectRoot: projectRoot,
      command: command,
      workingDirectory: workingDirectory,
      jobId: jobId,
      status: status ?? this.status,
      duplicateExisting: duplicateExisting ?? this.duplicateExisting,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'language_id': languageId,
      'project_root': projectRoot,
      'command': command,
      'working_directory': workingDirectory,
      'job_id': jobId,
      'status': status,
      'duplicate_existing': duplicateExisting,
    };
  }
}

class LspServerProcessStartResult {
  const LspServerProcessStartResult({
    required this.ok,
    required this.status,
    this.session,
    this.languageId,
    this.code,
    this.error,
    this.previousStatus,
    this.metadata,
  });

  final bool ok;
  final String status;
  final LspServerProcessSession? session;
  final String? languageId;
  final String? code;
  final String? error;
  final String? previousStatus;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() {
    return {
      'ok': ok,
      'status': status,
      if (languageId != null) 'language_id': languageId,
      if (session != null) 'session': session!.toJson(),
      if (code != null) 'code': code,
      if (error != null) 'error': error,
      if (previousStatus != null) 'previous_status': previousStatus,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class LspServerProcessManager implements LspServerReadinessProbe {
  LspServerProcessManager({
    required BackgroundProcessTools backgroundProcessTools,
    LspServerCommandResolver commandResolver = const LspServerCommandResolver(),
    LspServerExecutableProbe executableProbe =
        const PathLspServerExecutableProbe(),
  }) : _backgroundProcessTools = backgroundProcessTools,
       _commandResolver = commandResolver,
       _executableProbe = executableProbe;

  final BackgroundProcessTools _backgroundProcessTools;
  final LspServerCommandResolver _commandResolver;
  final LspServerExecutableProbe _executableProbe;
  final Map<String, LspServerProcessSession> _sessions = {};

  List<LspServerProcessSession> get sessions =>
      List<LspServerProcessSession>.unmodifiable(_sessions.values);

  Future<LspServerProcessStartResult> ensureStarted({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    if (!_backgroundProcessTools.isSupported) {
      return const LspServerProcessStartResult(
        ok: false,
        status: 'unavailable',
        code: 'background_process_unavailable',
        error: 'Background process tools are not available.',
      );
    }

    final command = _commandResolver.resolve(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
    );
    if (command == null) {
      return const LspServerProcessStartResult(
        ok: false,
        status: 'unavailable',
        code: 'language_server_not_resolved',
        error: 'No language server command could be resolved.',
      );
    }
    final availability = await _executableProbe.check(command);
    if (!availability.available) {
      return LspServerProcessStartResult(
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

    final normalizedRoot = Directory(projectRoot).absolute.path;
    final key = _sessionKey(
      projectRoot: normalizedRoot,
      languageId: command.languageId,
    );
    final existing = _sessions[key];
    if (existing != null) {
      final status = await _refreshExistingSession(existing);
      if (status.ok && status.session?.status == 'running') {
        return status;
      }
      _sessions.remove(key);
    }

    final started = await _start(command: command, projectRoot: normalizedRoot);
    if (started.ok && started.session != null) {
      _sessions[key] = started.session!;
    }
    return started;
  }

  @override
  Future<LspServerReadiness> ensureReady({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    final result = await ensureStarted(
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
  }

  Future<LspServerProcessStartResult> refresh({
    required String projectRoot,
    required String languageId,
  }) async {
    final normalizedRoot = Directory(projectRoot).absolute.path;
    final session =
        _sessions[_sessionKey(
          projectRoot: normalizedRoot,
          languageId: languageId,
        )];
    if (session == null) {
      return LspServerProcessStartResult(
        ok: false,
        status: 'unavailable',
        languageId: languageId,
        code: 'language_server_session_not_found',
        error: 'No language server session exists for this project.',
      );
    }
    final refreshed = await _refreshExistingSession(session);
    if (!refreshed.ok || refreshed.session?.status != 'running') {
      _sessions.remove(
        _sessionKey(projectRoot: normalizedRoot, languageId: languageId),
      );
    } else if (refreshed.session != null) {
      _sessions[_sessionKey(
            projectRoot: normalizedRoot,
            languageId: languageId,
          )] =
          refreshed.session!;
    }
    return refreshed;
  }

  Future<LspServerProcessStartResult> _refreshExistingSession(
    LspServerProcessSession session,
  ) async {
    final statusResult = await _backgroundProcessTools.status(
      jobId: session.jobId,
      tailChars: 1000,
    );
    final decoded = _decodeMap(statusResult);
    if (decoded == null || decoded['ok'] != true) {
      return LspServerProcessStartResult(
        ok: false,
        status: 'unavailable',
        languageId: session.languageId,
        session: session,
        code: _stringValue(decoded?['code']) ?? 'language_server_status_failed',
        error:
            _stringValue(decoded?['error']) ?? 'Language server status failed.',
        previousStatus: session.status,
      );
    }
    final status = _stringValue(decoded['status']) ?? 'unknown';
    final refreshed = session.copyWith(status: status);
    return LspServerProcessStartResult(
      ok: status == 'running',
      status: status == 'running' ? 'ready' : 'exited',
      languageId: session.languageId,
      session: refreshed,
      code: status == 'running' ? null : 'language_server_exited',
      error: status == 'running' ? null : 'Language server process exited.',
      previousStatus: session.status,
    );
  }

  Future<LspServerProcessStartResult> _start({
    required LspServerCommand command,
    required String projectRoot,
  }) async {
    final started = await _backgroundProcessTools.start(
      command: command.command,
      workingDirectory: command.workingDirectory,
      label: 'LSP ${command.languageId}',
    );
    final decoded = _decodeMap(started);
    if (decoded == null || decoded['ok'] != true) {
      return LspServerProcessStartResult(
        ok: false,
        status: 'unavailable',
        languageId: command.languageId,
        code: _stringValue(decoded?['code']) ?? 'language_server_start_failed',
        error:
            _stringValue(decoded?['error']) ?? 'Language server start failed.',
      );
    }

    final jobId = _stringValue(decoded['job_id']);
    if (jobId == null || jobId.isEmpty) {
      return LspServerProcessStartResult(
        ok: false,
        status: 'unavailable',
        languageId: command.languageId,
        code: 'language_server_job_id_missing',
        error: 'Language server start result did not include a job_id.',
      );
    }

    final session = LspServerProcessSession(
      languageId: command.languageId,
      projectRoot: projectRoot,
      command: command.command,
      workingDirectory: command.workingDirectory,
      jobId: jobId,
      status: _stringValue(decoded['status']) ?? 'running',
      duplicateExisting: decoded['duplicate_existing'] == true,
    );
    return LspServerProcessStartResult(
      ok: true,
      status: 'ready',
      languageId: command.languageId,
      session: session,
    );
  }

  String _sessionKey({
    required String projectRoot,
    required String languageId,
  }) {
    return '${DartProjectPath.pathKey(projectRoot)}|$languageId';
  }

  Map<String, dynamic>? _decodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
