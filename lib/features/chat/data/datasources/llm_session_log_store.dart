import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/constants/build_info.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/message.dart';
import 'chat_remote_datasource.dart';

const Object _llmSessionLogContextZoneKey = Object();

class LlmSessionLogContext {
  const LlmSessionLogContext({
    required this.workspaceMode,
    required this.sessionId,
    this.sessionTitle,
    this.conversationId,
    this.routineId,
    this.routineRunId,
    this.phase,
    this.participantId,
    this.participantName,
    this.participantRoleLabel,
    this.participantToolsEnabled,
    this.participantToolNames = const <String>[],
  });

  final WorkspaceMode workspaceMode;
  final String sessionId;
  final String? sessionTitle;
  final String? conversationId;
  final String? routineId;
  final String? routineRunId;
  final String? phase;
  final String? participantId;
  final String? participantName;
  final String? participantRoleLabel;
  final bool? participantToolsEnabled;
  final List<String> participantToolNames;

  static String routinePlanSessionId(String routineId) {
    return 'routine-plan-${routineId.trim()}';
  }

  static String routineRunSessionId({
    required String routineId,
    required String runId,
  }) {
    return 'routine-${routineId.trim()}-run-${runId.trim()}';
  }

  static LlmSessionLogContext? get current {
    return Zone.current[_llmSessionLogContextZoneKey] as LlmSessionLogContext?;
  }

  static T run<T>(LlmSessionLogContext context, T Function() body) {
    return runZoned(body, zoneValues: {_llmSessionLogContextZoneKey: context});
  }

  LlmSessionLogContext withParticipant({
    required String participantId,
    required String participantName,
    required String participantRoleLabel,
    required bool toolsEnabled,
    List<String> toolNames = const <String>[],
    String? phase,
  }) {
    return LlmSessionLogContext(
      workspaceMode: workspaceMode,
      sessionId: sessionId,
      sessionTitle: sessionTitle,
      conversationId: conversationId,
      routineId: routineId,
      routineRunId: routineRunId,
      phase: phase ?? this.phase,
      participantId: participantId,
      participantName: participantName,
      participantRoleLabel: participantRoleLabel,
      participantToolsEnabled: toolsEnabled,
      participantToolNames: toolNames,
    );
  }

  Map<String, dynamic> toJson() {
    final normalizedParticipantToolNames = participantToolNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return {
      'workspaceMode': workspaceMode.name,
      'sessionId': sessionId,
      if (sessionTitle != null && sessionTitle!.trim().isNotEmpty)
        'sessionTitle': sessionTitle!.trim(),
      if (conversationId != null && conversationId!.trim().isNotEmpty)
        'conversationId': conversationId!.trim(),
      if (routineId != null && routineId!.trim().isNotEmpty)
        'routineId': routineId!.trim(),
      if (routineRunId != null && routineRunId!.trim().isNotEmpty)
        'routineRunId': routineRunId!.trim(),
      if (phase != null && phase!.trim().isNotEmpty) 'phase': phase!.trim(),
      if (participantId != null && participantId!.trim().isNotEmpty)
        'participantId': participantId!.trim(),
      if (participantName != null && participantName!.trim().isNotEmpty)
        'participantName': participantName!.trim(),
      if (participantRoleLabel != null &&
          participantRoleLabel!.trim().isNotEmpty)
        'participantRoleLabel': participantRoleLabel!.trim(),
      if (participantToolsEnabled != null)
        'participantToolsEnabled': participantToolsEnabled,
      if (normalizedParticipantToolNames.isNotEmpty)
        'participantToolNames': normalizedParticipantToolNames,
    };
  }
}

class LlmSessionLogRequest {
  const LlmSessionLogRequest({
    required this.operation,
    required this.messages,
    this.tools,
    this.toolResults,
    this.toolCallId,
    this.toolName,
    this.toolArguments,
    this.toolResult,
    this.assistantContent,
    this.model,
    this.temperature,
    this.maxTokens,
  });

  final String operation;
  final List<Message> messages;
  final List<Map<String, dynamic>>? tools;
  final List<ToolResultInfo>? toolResults;
  final String? toolCallId;
  final String? toolName;
  final String? toolArguments;
  final String? toolResult;
  final String? assistantContent;
  final String? model;
  final double? temperature;
  final int? maxTokens;
}

class LlmSessionLogResponse {
  const LlmSessionLogResponse({
    required this.content,
    this.finishReason,
    this.toolCalls,
    this.usage = TokenUsage.zero,
  });

  final String content;
  final String? finishReason;
  final List<ToolCallInfo>? toolCalls;
  final TokenUsage usage;
}

class LlmSessionLogRetentionPolicy {
  const LlmSessionLogRetentionPolicy({
    this.maxFileBytes = defaultMaxFileBytes,
    this.maxAge = defaultMaxAge,
    this.maxRotatedFiles = defaultMaxRotatedFiles,
  });

  static const int defaultMaxFileBytes = 10 * 1024 * 1024;
  static const Duration defaultMaxAge = Duration(days: 30);
  static const int defaultMaxRotatedFiles = 4;

  final int? maxFileBytes;
  final Duration? maxAge;
  final int maxRotatedFiles;

  factory LlmSessionLogRetentionPolicy.fromEnvironment([
    Map<String, String>? environment,
  ]) {
    final env = environment ?? Platform.environment;
    return LlmSessionLogRetentionPolicy(
      maxFileBytes: _parsePositiveInt(
        env['CAVERNO_SESSION_LOG_MAX_FILE_BYTES'],
        fallback: defaultMaxFileBytes,
      ),
      maxAge: _parseMaxAge(
        env['CAVERNO_SESSION_LOG_MAX_AGE_DAYS'],
        fallback: defaultMaxAge,
      ),
      maxRotatedFiles:
          _parseNonNegativeInt(
            env['CAVERNO_SESSION_LOG_MAX_ROTATED_FILES'],
            fallback: defaultMaxRotatedFiles,
          ) ??
          0,
    );
  }

  static int? _parsePositiveInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    return parsed <= 0 ? null : parsed;
  }

  static int? _parseNonNegativeInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    return parsed < 0 ? 0 : parsed;
  }

  static Duration? _parseMaxAge(String? value, {required Duration fallback}) {
    final days = _parsePositiveInt(value, fallback: fallback.inDays);
    return days == null ? null : Duration(days: days);
  }
}

class LlmSessionLogStore {
  LlmSessionLogStore({
    Future<Directory> Function()? rootDirectoryProvider,
    LlmSessionLogRetentionPolicy? retentionPolicy,
  }) : _rootDirectoryProvider =
           rootDirectoryProvider ?? _defaultRootDirectoryProvider,
       _retentionPolicy =
           retentionPolicy ?? LlmSessionLogRetentionPolicy.fromEnvironment();

  final Future<Directory> Function() _rootDirectoryProvider;
  final LlmSessionLogRetentionPolicy _retentionPolicy;

  static const schemaName = 'caverno_llm_session_log_entry';
  // v2 adds the `build` field (git commit/dirty/builtAt provenance).
  static const schemaVersion = 2;
  static const enabledEnvironmentKey = 'CAVERNO_SESSION_LOG_ENABLED';
  static const _fallbackSessionId = 'unscoped';
  static final RegExp _safeFileNamePattern = RegExp(r'[^A-Za-z0-9._-]+');
  static const _redactedStringKeys = {
    'imagebase64',
    'image_base64',
    'screenshotbase64',
    'screenshot_base64',
    'audiobase64',
    'audio_base64',
    'access_token',
    'accesstoken',
    'password',
    'passwd',
    'pwd',
    'token',
    'secret',
    'clientsecret',
    'client_secret',
    'credential',
    'credentials',
    'cookie',
    'setcookie',
    'set_cookie',
    'privatekey',
    'private_key',
    'sshkey',
    'ssh_key',
    'xapikey',
    'x_api_key',
    'apikey',
    'api_key',
    'authorization',
  };
  static final RegExp _privateKeyPattern = RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
    caseSensitive: false,
  );
  static final RegExp _authorizationHeaderPattern = RegExp(
    r'\b(authorization\s*[:=]\s*)(?:bearer|basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _bearerTokenPattern = RegExp(
    r'\bbearer\s+[A-Za-z0-9._~+/=-]{8,}',
    caseSensitive: false,
  );
  static final RegExp _openAiStyleKeyPattern = RegExp(
    r'\bsk-[A-Za-z0-9_-]{16,}\b',
  );
  static final RegExp _githubTokenPattern = RegExp(
    r'\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,})\b',
  );
  static final RegExp _jwtPattern = RegExp(
    r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
  );
  static final RegExp _urlCredentialPattern = RegExp(
    r'\b(https?://)[^:\s/@]+:[^@\s]+@',
    caseSensitive: false,
  );
  static final RegExp _sensitiveQueryParamPattern = RegExp(
    r'([?&](?:access_token|refresh_token|id_token|api_key|apikey|token|secret|password|auth|authorization|key)=)[^&#\s]+',
    caseSensitive: false,
  );
  static final RegExp _envSecretLinePattern = RegExp(
    r'^(\s*(?:[A-Z][A-Z0-9_]*(?:TOKEN|SECRET|KEY|PASSWORD|PASS|PWD|AUTH)[A-Z0-9_]*|(?:TOKEN|SECRET|KEY|PASSWORD|PASS|PWD|AUTH))\s*=\s*)(.+)$',
    multiLine: true,
  );

  static bool isEnabled({
    required bool settingsEnabled,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final override = env[enabledEnvironmentKey]?.trim().toLowerCase();
    return switch (override) {
      '1' || 'true' || 'yes' || 'on' => true,
      '0' || 'false' || 'no' || 'off' => false,
      _ => settingsEnabled,
    };
  }

  static dynamic redactSensitiveValue(dynamic value) {
    return _redactValue(value);
  }

  static String redactSensitiveText(String value) {
    return _redactString(value);
  }

  static String redactSessionLogContent(String content) {
    if (content.isEmpty) {
      return content;
    }
    final endsWithNewline = content.endsWith('\n');
    final lines = content.split('\n');
    if (endsWithNewline) {
      lines.removeLast();
    }
    final redactedLines = lines.map(_redactSessionLogLine).join('\n');
    return endsWithNewline ? '$redactedLines\n' : redactedLines;
  }

  static String _redactSessionLogLine(String line) {
    if (line.trim().isEmpty) {
      return line;
    }
    try {
      return jsonEncode(_redactValue(jsonDecode(line)));
    } catch (_) {
      return _redactString(line);
    }
  }

  Future<void> record({
    required LlmSessionLogContext? context,
    required LlmSessionLogRequest request,
    required DateTime startedAt,
    required DateTime finishedAt,
    LlmSessionLogResponse? response,
    Object? error,
  }) async {
    try {
      final effectiveContext = context ?? _fallbackContext();
      final file = await fileForContext(effectiveContext);
      final entry = {
        'schemaName': schemaName,
        'schemaVersion': schemaVersion,
        'timestamp': finishedAt.toIso8601String(),
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'durationMs': finishedAt.difference(startedAt).inMilliseconds,
        'build': BuildInfo.toJson(),
        'context': effectiveContext.toJson(),
        'operation': request.operation,
        'request': _requestToJson(request),
        if (response != null) 'response': _responseToJson(response),
        if (error != null)
          'error': {
            'type': error.runtimeType.toString(),
            'message': error.toString(),
          },
      };
      final line = '${jsonEncode(_redactValue(entry))}\n';
      await _prepareFileForWrite(
        file,
        incomingBytes: utf8.encode(line).length,
        now: finishedAt,
      );
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (error) {
      appLog('[SessionLog] Failed to write LLM session log: $error');
    }
  }

  /// Append a turn-level exit-reason marker (LL31 instrument).
  ///
  /// [record] writes one entry per LLM call; this writes one extra `turn_exit`
  /// entry per finished tool-calling turn so `tool/triage_session_logs.py` can
  /// surface the structured exit-reason distribution and flag turns that
  /// stopped with no visible answer. Callers gate on [isEnabled] before calling.
  ///
  /// [turnId] and [assistantMessageId] are turn-provenance correlation keys:
  /// they let a `turn_exit` entry be joined to the conversation message it
  /// finalized (the conversation store holds the final, post-transform UI
  /// content), so the LLM session log and the on-screen conversation can be
  /// traced to each other without inferring from leaked notice prose.
  Future<void> recordTurnExit({
    required LlmSessionLogContext? context,
    required String reason,
    required bool noVisibleAnswer,
    required DateTime at,
    String? turnId,
    String? assistantMessageId,
    List<String>? transforms,
  }) async {
    try {
      final effectiveContext = context ?? _fallbackContext();
      final file = await fileForContext(effectiveContext);
      final entry = {
        'schemaName': schemaName,
        'schemaVersion': schemaVersion,
        'timestamp': at.toIso8601String(),
        'build': BuildInfo.toJson(),
        'context': effectiveContext.toJson(),
        'operation': 'turn_exit',
        'turnExit': {
          'reason': reason,
          'noVisibleAnswer': noVisibleAnswer,
          if (turnId != null && turnId.isNotEmpty) 'turnId': turnId,
          if (assistantMessageId != null && assistantMessageId.isNotEmpty)
            'assistantMessageId': assistantMessageId,
          // Post-LLM transforms applied to the final message (guard notices,
          // etc.) — explains why the on-screen content differs from the raw
          // response, without inferring from leaked notice prose.
          if (transforms != null && transforms.isNotEmpty)
            'transforms': transforms,
        },
      };
      final line = '${jsonEncode(_redactValue(entry))}\n';
      await _prepareFileForWrite(
        file,
        incomingBytes: utf8.encode(line).length,
        now: at,
      );
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (error) {
      appLog('[SessionLog] Failed to write turn-exit entry: $error');
    }
  }

  /// Append a structured goal auto-continuation decision.
  ///
  /// This sits next to `turn_exit` entries so live/debug triage can prove that
  /// an idle, incomplete goal turn scheduled an automatic hidden continuation
  /// before the next LLM request was made.
  Future<void> recordGoalAutoContinue({
    required LlmSessionLogContext? context,
    required String decision,
    required String reason,
    required DateTime at,
    String? goalId,
    int? nextTurnNumber,
    int? effectiveTurnBudget,
    int? consecutiveAutoContinuations,
    Map<String, dynamic>? evidence,
  }) async {
    try {
      final effectiveContext = context ?? _fallbackContext();
      final file = await fileForContext(effectiveContext);
      final normalizedGoalId = goalId?.trim();
      final goalAutoContinue = <String, dynamic>{
        'decision': decision,
        'reason': reason,
      };
      if (normalizedGoalId != null && normalizedGoalId.isNotEmpty) {
        goalAutoContinue['goalId'] = normalizedGoalId;
      }
      if (nextTurnNumber != null) {
        goalAutoContinue['nextTurnNumber'] = nextTurnNumber;
      }
      if (effectiveTurnBudget != null) {
        goalAutoContinue['effectiveTurnBudget'] = effectiveTurnBudget;
      }
      if (consecutiveAutoContinuations != null) {
        goalAutoContinue['consecutiveAutoContinuations'] =
            consecutiveAutoContinuations;
      }
      if (evidence != null && evidence.isNotEmpty) {
        goalAutoContinue['evidence'] = evidence;
      }
      final entry = {
        'schemaName': schemaName,
        'schemaVersion': schemaVersion,
        'timestamp': at.toIso8601String(),
        'build': BuildInfo.toJson(),
        'context': effectiveContext.toJson(),
        'operation': 'goal_auto_continue',
        'goalAutoContinue': goalAutoContinue,
      };
      final line = '${jsonEncode(_redactValue(entry))}\n';
      await _prepareFileForWrite(
        file,
        incomingBytes: utf8.encode(line).length,
        now: at,
      );
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (error) {
      appLog(
        '[SessionLog] Failed to write goal auto-continuation entry: $error',
      );
    }
  }

  /// Resolves the log file for [context].
  ///
  /// Set [create] to false to resolve the path without creating the workspace
  /// directory as a side effect — useful for read-only views (e.g. the
  /// companion panel) that only want to show where the log lives.
  Future<File> fileForContext(
    LlmSessionLogContext context, {
    bool create = true,
  }) async {
    final root = await _rootDirectoryProvider();
    final workspaceDirectory = Directory(
      '${root.path}/${_sanitizeFileSegment(context.workspaceMode.name)}',
    );
    if (create) {
      await workspaceDirectory.create(recursive: true);
    }
    final sessionId = context.sessionId.trim().isEmpty
        ? _fallbackSessionId
        : context.sessionId.trim();
    return File(
      '${workspaceDirectory.path}/${_sanitizeFileSegment(sessionId)}.jsonl',
    );
  }

  Map<String, dynamic> _requestToJson(LlmSessionLogRequest request) {
    return {
      'model': request.model,
      'temperature': request.temperature,
      'maxTokens': request.maxTokens,
      'messages': request.messages.map(_messageToJson).toList(growable: false),
      if (request.tools != null)
        'tools': request.tools!
            .map(_toolDefinitionToJson)
            .toList(growable: false),
      if (request.toolResults != null)
        'toolResults': request.toolResults!
            .map(_toolResultToJson)
            .toList(growable: false),
      if (request.toolCallId != null) 'toolCallId': request.toolCallId,
      if (request.toolName != null) 'toolName': request.toolName,
      if (request.toolArguments != null)
        'toolArguments': _decodeJsonStringIfPossible(request.toolArguments!),
      if (request.toolResult != null)
        'toolResult': _decodeJsonStringIfPossible(request.toolResult!),
      if (request.assistantContent != null)
        'assistantContent': request.assistantContent,
    };
  }

  Map<String, dynamic> _responseToJson(LlmSessionLogResponse response) {
    return {
      'content': response.content,
      if (response.finishReason != null) 'finishReason': response.finishReason,
      if (response.toolCalls != null)
        'toolCalls': response.toolCalls!
            .map(
              (toolCall) => {
                'id': toolCall.id,
                'name': toolCall.name,
                'arguments': toolCall.arguments,
              },
            )
            .toList(growable: false),
      'usage': {
        'promptTokens': response.usage.promptTokens,
        'completionTokens': response.usage.completionTokens,
        'totalTokens': response.usage.totalTokens,
      },
    };
  }

  Map<String, dynamic> _messageToJson(Message message) {
    return {
      'id': message.id,
      'role': message.role.name,
      'timestamp': message.timestamp.toIso8601String(),
      'content': message.content,
      if (message.imageBase64 != null)
        'image': {
          'mediaType': message.imageMimeType ?? 'image/jpeg',
          'base64Length': message.imageBase64!.length,
          'base64': '[redacted]',
        },
      if (message.error != null) 'error': message.error,
    };
  }

  Map<String, dynamic> _toolDefinitionToJson(Map<String, dynamic> tool) {
    return Map<String, dynamic>.from(_redactValue(tool) as Map);
  }

  Map<String, dynamic> _toolResultToJson(ToolResultInfo toolResult) {
    return {
      'id': toolResult.id,
      'name': toolResult.name,
      'arguments': toolResult.arguments,
      'result': _decodeJsonStringIfPossible(toolResult.result),
    };
  }

  dynamic _decodeJsonStringIfPossible(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return value;
    }
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return value;
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return value;
    }
  }

  static dynamic _redactValue(dynamic value, [String? parentKey]) {
    final normalizedKey = parentKey
        ?.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')
        .toLowerCase();
    if (normalizedKey != null && _redactedStringKeys.contains(normalizedKey)) {
      return '[redacted]';
    }

    if (value is String) {
      return _redactString(value);
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _redactValue(entry.value, entry.key.toString()),
      };
    }
    if (value is List) {
      return value.map(_redactValue).toList(growable: false);
    }
    return value;
  }

  static String _redactString(String value) {
    var redacted = value.replaceAll(
      _privateKeyPattern,
      '[redacted-private-key]',
    );
    redacted = redacted.replaceAllMapped(
      _authorizationHeaderPattern,
      (match) => '${match.group(1)}[redacted]',
    );
    redacted = redacted.replaceAllMapped(
      _bearerTokenPattern,
      (match) => '${match.group(0)!.split(RegExp(r'\s+')).first} [redacted]',
    );
    redacted = redacted.replaceAll(_openAiStyleKeyPattern, 'sk-[redacted]');
    redacted = redacted.replaceAll(
      _githubTokenPattern,
      '[redacted-github-token]',
    );
    redacted = redacted.replaceAll(_jwtPattern, '[redacted-jwt]');
    redacted = redacted.replaceAllMapped(
      _urlCredentialPattern,
      (match) => '${match.group(1)}[redacted]@',
    );
    redacted = redacted.replaceAllMapped(
      _sensitiveQueryParamPattern,
      (match) => '${match.group(1)}[redacted]',
    );
    redacted = redacted.replaceAllMapped(
      _envSecretLinePattern,
      (match) => '${match.group(1)}[redacted]',
    );
    return redacted;
  }

  Future<void> _prepareFileForWrite(
    File file, {
    required int incomingBytes,
    required DateTime now,
  }) async {
    await _deleteExpiredLogs(file.parent, now);
    await _rotateIfNeeded(file, incomingBytes: incomingBytes);
  }

  Future<void> _deleteExpiredLogs(Directory directory, DateTime now) async {
    final maxAge = _retentionPolicy.maxAge;
    if (maxAge == null || !await directory.exists()) {
      return;
    }

    final expiresBefore = now.subtract(maxAge);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !_isSessionLogFile(entity)) {
        continue;
      }
      final modifiedAt = await entity.lastModified();
      if (modifiedAt.isBefore(expiresBefore)) {
        await entity.delete();
      }
    }
  }

  Future<void> _rotateIfNeeded(File file, {required int incomingBytes}) async {
    final maxFileBytes = _retentionPolicy.maxFileBytes;
    if (maxFileBytes == null || !await file.exists()) {
      return;
    }

    final currentBytes = await file.length();
    if (currentBytes == 0 || currentBytes + incomingBytes <= maxFileBytes) {
      return;
    }

    final maxRotatedFiles = _retentionPolicy.maxRotatedFiles;
    if (maxRotatedFiles <= 0) {
      await file.delete();
      return;
    }

    final oldest = File('${file.path}.$maxRotatedFiles');
    if (await oldest.exists()) {
      await oldest.delete();
    }
    for (var index = maxRotatedFiles - 1; index >= 1; index--) {
      final source = File('${file.path}.$index');
      if (await source.exists()) {
        await source.rename('${file.path}.${index + 1}');
      }
    }
    await file.rename('${file.path}.1');
  }

  bool _isSessionLogFile(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    return RegExp(r'\.jsonl(?:\.\d+)?$').hasMatch(name);
  }

  LlmSessionLogContext _fallbackContext() {
    return const LlmSessionLogContext(
      workspaceMode: WorkspaceMode.chat,
      sessionId: _fallbackSessionId,
      phase: 'unscoped',
    );
  }

  static Future<Directory> _defaultRootDirectoryProvider() async {
    final override = Platform.environment['CAVERNO_SESSION_LOG_DIR']?.trim();
    if (override != null && override.isNotEmpty) {
      return Directory(override);
    }
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      return Directory('$home/.caverno/session_logs');
    }
    return Directory('${Directory.systemTemp.path}/caverno_session_logs');
  }

  static String _sanitizeFileSegment(String value) {
    final sanitized = value
        .replaceAll(_safeFileNamePattern, '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? _fallbackSessionId : sanitized;
  }
}
