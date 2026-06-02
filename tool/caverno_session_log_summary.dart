import 'dart:collection';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = CavernoSessionLogSummaryOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/caverno_session_log_summary.dart '
      '--log PATH [--format markdown|json]',
    );
    exitCode = 64;
    return;
  }

  final logFile = File(options.logPath);
  if (!logFile.existsSync()) {
    stderr.writeln('Log file not found: ${logFile.path}');
    exitCode = 66;
    return;
  }

  final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
  switch (options.format) {
    case CavernoSessionLogSummaryFormat.json:
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(summary.toJson()),
      );
      return;
    case CavernoSessionLogSummaryFormat.markdown:
      stdout.write(summary.toMarkdown());
      return;
  }
}

Future<CavernoLlmSessionLogSummary> buildCavernoLlmSessionLogSummary({
  required File logFile,
  DateTime? generatedAt,
  int previewLength = 240,
  int maxToolCallPreviews = 40,
}) async {
  final operationCounts = SplayTreeMap<String, int>();
  final finishReasonCounts = SplayTreeMap<String, int>();
  final diagnostics = <SessionLogEntryDiagnostic>[];
  final errorEntries = <SessionLogErrorEntry>[];
  final toolCalls = <SessionLogToolCallSummary>[];
  final streamEndLineNumbers = <int>[];
  final loopLimitPromptLineNumbers = <int>[];
  final memoryExtractionLineNumbers = <int>[];
  final autoReviewLineNumbers = <int>[];
  final warnings = <SessionLogWarningEntry>[];
  var malformedLineCount = 0;
  var parsedEntryCount = 0;
  var totalToolCallCount = 0;
  SessionLogEntryDiagnostic? finalAnswer;

  final lines = await logFile.readAsLines();
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final lineNumber = lineIndex + 1;
    final line = lines[lineIndex].trim();
    if (line.isEmpty) {
      continue;
    }

    final decoded = _decodeJsonObject(line);
    if (decoded == null) {
      malformedLineCount += 1;
      continue;
    }
    parsedEntryCount += 1;

    final context = _asStringMap(decoded['context']);
    final request = _asStringMap(decoded['request']);
    final response = _asStringMap(decoded['response']);
    final error = _asStringMap(decoded['error']);
    final responseContent = response == null
        ? ''
        : _asString(response['content']) ?? '';
    final responseToolCalls = _asList(response?['toolCalls']);
    final requestMessages = _asList(request?['messages']);
    final requestTools = _asList(request?['tools']);
    final requestToolResults = _asList(request?['toolResults']);
    final operation = _asString(decoded['operation']) ?? 'unknown';
    final phase = _asString(context?['phase']);
    final finishReason = _asString(response?['finishReason']);
    final requestText = requestMessages.map(_messageText).join('\n');
    final isMemoryExtraction = _isMemoryExtractionResponse(responseContent);
    final isAutoReview = _isAutoReviewResponse(responseContent);
    final hasLoopLimitPrompt = _hasLoopLimitPrompt(requestText);
    final hasToolCalls = responseToolCalls.isNotEmpty;
    final hasError = error != null;

    operationCounts.update(operation, (count) => count + 1, ifAbsent: () => 1);
    if (finishReason != null) {
      finishReasonCounts.update(
        finishReason,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (finishReason == 'stream_end') {
      streamEndLineNumbers.add(lineNumber);
    }
    if (hasLoopLimitPrompt) {
      loopLimitPromptLineNumbers.add(lineNumber);
    }
    if (isMemoryExtraction) {
      memoryExtractionLineNumbers.add(lineNumber);
      warnings.addAll(
        _buildMemoryExtractionWarnings(
          lineNumber: lineNumber,
          content: responseContent,
          requestText: requestText,
          previewLength: previewLength,
        ),
      );
    }
    if (isAutoReview) {
      autoReviewLineNumbers.add(lineNumber);
    }
    if (hasError) {
      errorEntries.add(
        SessionLogErrorEntry(
          lineNumber: lineNumber,
          operation: operation,
          type: _asString(error['type']),
          message:
              _asString(error['message']) ??
              _preview(jsonEncode(error), previewLength),
        ),
      );
    }

    for (final toolCall in responseToolCalls) {
      totalToolCallCount += 1;
      final toolCallMap = _asStringMap(toolCall);
      if (toolCallMap == null) {
        continue;
      }
      final functionMap = _asStringMap(toolCallMap['function']);
      final rawArguments =
          toolCallMap['arguments'] ?? functionMap?['arguments'] ?? const {};
      final arguments = _decodeArguments(rawArguments);
      if (toolCalls.length < maxToolCallPreviews) {
        toolCalls.add(
          SessionLogToolCallSummary(
            lineNumber: lineNumber,
            id: _asString(toolCallMap['id']),
            name:
                _asString(toolCallMap['name']) ??
                _asString(functionMap?['name']) ??
                'unknown',
            commandPreview: _previewNullable(
              _asString(arguments['command']),
              previewLength,
            ),
            argumentsPreview: _preview(jsonEncode(arguments), previewLength),
            reasonPreview: _previewNullable(
              _asString(arguments['reason']),
              previewLength,
            ),
          ),
        );
      }
    }

    final isFinalAnswerCandidate =
        responseContent.trim().isNotEmpty &&
        !hasToolCalls &&
        !hasError &&
        !isMemoryExtraction &&
        !isAutoReview;
    final diagnostic = SessionLogEntryDiagnostic(
      lineNumber: lineNumber,
      startedAt: _asString(decoded['startedAt']),
      finishedAt: _asString(decoded['finishedAt']),
      operation: operation,
      phase: phase,
      finishReason: finishReason,
      durationMs: _asInt(decoded['durationMs']),
      requestMessageCount: requestMessages.length,
      requestToolCount: requestTools.length,
      requestToolResultCount: requestToolResults.length,
      responseContentLength: responseContent.length,
      responseToolCallCount: responseToolCalls.length,
      hasError: hasError,
      hasLoopLimitPrompt: hasLoopLimitPrompt,
      isMemoryExtraction: isMemoryExtraction,
      isAutoReview: isAutoReview,
      isFinalAnswerCandidate: isFinalAnswerCandidate,
      contentPreview: _previewNullable(responseContent, previewLength),
    );
    diagnostics.add(diagnostic);
    if (isFinalAnswerCandidate) {
      finalAnswer = diagnostic;
      final finalAnswerWarning = _buildFinalAnswerWarning(
        lineNumber: lineNumber,
        content: responseContent,
        previewLength: previewLength,
      );
      if (finalAnswerWarning != null) {
        warnings.add(finalAnswerWarning);
      }
    }
  }

  return CavernoLlmSessionLogSummary(
    schemaName: 'caverno_llm_session_log_summary',
    schemaVersion: 3,
    generatedAt: generatedAt ?? DateTime.now(),
    logPath: logFile.path,
    entryCount: parsedEntryCount,
    malformedLineCount: malformedLineCount,
    result: _summaryResult(
      hasErrors: errorEntries.isNotEmpty,
      hasLoopLimitPrompt: loopLimitPromptLineNumbers.isNotEmpty,
      hasFinalAnswer: finalAnswer != null,
    ),
    operationCounts: Map.unmodifiable(operationCounts),
    finishReasonCounts: Map.unmodifiable(finishReasonCounts),
    streamEndLineNumbers: List.unmodifiable(streamEndLineNumbers),
    loopLimitPromptLineNumbers: List.unmodifiable(loopLimitPromptLineNumbers),
    memoryExtractionLineNumbers: List.unmodifiable(memoryExtractionLineNumbers),
    autoReviewLineNumbers: List.unmodifiable(autoReviewLineNumbers),
    errorEntries: List.unmodifiable(errorEntries),
    toolCallCount: totalToolCallCount,
    toolCalls: List.unmodifiable(toolCalls),
    entries: List.unmodifiable(diagnostics),
    finalAnswer: finalAnswer,
    warnings: List.unmodifiable(warnings),
  );
}

String _summaryResult({
  required bool hasErrors,
  required bool hasLoopLimitPrompt,
  required bool hasFinalAnswer,
}) {
  if (hasErrors) {
    return 'error';
  }
  if (hasLoopLimitPrompt && hasFinalAnswer) {
    return 'loop_limit_recovered';
  }
  if (hasLoopLimitPrompt) {
    return 'loop_limit_without_final_answer';
  }
  if (hasFinalAnswer) {
    return 'complete';
  }
  return 'incomplete';
}

Map<String, dynamic>? _decodeJsonObject(String source) {
  try {
    final decoded = jsonDecode(source);
    return _asStringMap(decoded);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic> _decodeArguments(Object? source) {
  if (source is Map) {
    return source.map((key, value) => MapEntry(key.toString(), value));
  }
  if (source is String && source.trim().isNotEmpty) {
    final decoded = _decodeJsonObject(source);
    if (decoded != null) {
      return decoded;
    }
  }
  return const {};
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String? _asString(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

String _messageText(Object? message) {
  final messageMap = _asStringMap(message);
  if (messageMap == null) {
    return '';
  }
  return _contentText(messageMap['content']);
}

String _contentText(Object? content) {
  if (content is String) {
    return content;
  }
  if (content is List) {
    return content
        .map(_contentText)
        .where((text) => text.isNotEmpty)
        .join('\n');
  }
  final contentMap = _asStringMap(content);
  if (contentMap != null) {
    return _contentText(contentMap['text'] ?? contentMap['content']);
  }
  return '';
}

bool _hasLoopLimitPrompt(String requestText) {
  final normalized = requestText.toLowerCase();
  return normalized.contains('you hit the bounded tool loop limit') ||
      normalized.contains('bounded tool loop limit') ||
      normalized.contains('tool loop reached maximum iterations');
}

bool _isMemoryExtractionResponse(String content) {
  final object = _decodeJsonObject(content.trim());
  if (object == null) {
    return false;
  }
  return object.containsKey('summary') &&
      (object.containsKey('memories') ||
          object.containsKey('open_loops') ||
          object.containsKey('profile'));
}

bool _isAutoReviewResponse(String content) {
  final object = _decodeJsonObject(content.trim());
  if (object == null) {
    return false;
  }
  return object.containsKey('outcome') &&
      object.containsKey('riskLevel') &&
      object.containsKey('rationale');
}

List<SessionLogWarningEntry> _buildMemoryExtractionWarnings({
  required int lineNumber,
  required String content,
  required String requestText,
  required int previewLength,
}) {
  final conversationUserText = _memoryExtractionConversationUserText(
    requestText,
  );
  if (_hasExplicitMemoryRequest(conversationUserText)) {
    return const [];
  }

  final object = _decodeJsonObject(content.trim());
  if (object == null) {
    return const [];
  }
  final memories = _asList(object['memories']);
  for (final rawMemory in memories) {
    final memory = _asStringMap(rawMemory);
    if (memory == null) {
      continue;
    }
    final text = _asString(memory['text']) ?? '';
    if (!_isEphemeralDraftMemory(text)) {
      continue;
    }
    return [
      SessionLogWarningEntry(
        code: 'memory_ephemeral_draft',
        lineNumber: lineNumber,
        message:
            'The memory extractor drafted a likely one-off lookup or artifact '
            'memory. Treat this as LLM draft output, not persisted memory; '
            'check the memory_update counts or storage state for added, queued, '
            'and suppressed candidates.',
        evidencePreview: _preview(text, previewLength),
      ),
    ];
  }
  return const [];
}

SessionLogWarningEntry? _buildFinalAnswerWarning({
  required int lineNumber,
  required String content,
  required int previewLength,
}) {
  if (!_misinterpretsStreamEnd(content)) {
    return null;
  }
  return SessionLogWarningEntry(
    code: 'stream_end_misinterpretation',
    lineNumber: lineNumber,
    message:
        'The final answer appears to treat stream_end as an interruption or '
        'transport failure. In Caverno logs, stream_end only means the '
        'streaming response was fully consumed unless an explicit error or '
        'missing final answer is also present.',
    evidencePreview: _preview(content, previewLength),
  );
}

bool _misinterpretsStreamEnd(String content) {
  final normalized = content.toLowerCase();
  if (!normalized.contains('stream_end')) {
    return false;
  }
  if (_containsAny(normalized, const [
    'not an interruption',
    'not a failure',
    'not an error',
    'by itself',
    '単独では',
    'だけでは',
    'ではありません',
    'ではない',
  ])) {
    return false;
  }
  return _containsAny(normalized, const [
    'interrupt',
    'interruption',
    'disconnect',
    'connection closed',
    'cut off',
    'abort',
    'abnormal',
    'failure',
    'failed',
    '中断',
    '切断',
    '打ち切',
    '異常',
    '強制終了',
    '原因',
  ]);
}

bool _containsAny(String text, List<String> needles) {
  return needles.any(text.contains);
}

final RegExp _explicitMemoryRequestPattern = RegExp(
  r'\b(remember|memorize|save to memory|keep in memory)\b|'
  '\\u899a\\u3048\\u3066|\\u8a18\\u61b6|\\u30e1\\u30e2\\u30ea',
  caseSensitive: false,
);

final RegExp _ephemeralArtifactMemoryPattern = RegExp(
  r'\b(saved|wrote|created|updated|generated|exported)\b.*\b(file|path|report|markdown|\.md|\.json|\.txt|\.csv|\.dart|/users/|/tmp/)\b|'
  r'\b(file|path|report|markdown|\.md|\.json|\.txt|\.csv|\.dart|/users/|/tmp/)\b.*\b(saved|wrote|created|updated|generated|exported)\b',
  caseSensitive: false,
);

final RegExp _ephemeralLookupMemoryPattern = RegExp(
  r'\b(retrieved|fetched|looked up|queried|searched|obtained)\b.*\b(weather|forecast|api|search result|tool result)\b|'
  r'\b(weather|forecast)\b.*\b(temperature|precipitation|rain|drizzle|snow|wind|humidity|weathercode|weather code|km/h)\b',
  caseSensitive: false,
);

bool _hasExplicitMemoryRequest(String text) {
  return _explicitMemoryRequestPattern.hasMatch(text);
}

String _memoryExtractionConversationUserText(String requestText) {
  final buffer = StringBuffer();
  var inConversationLog = false;
  for (final rawLine in requestText.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line == 'Conversation log:') {
      inConversationLog = true;
      continue;
    }
    if (!inConversationLog) {
      continue;
    }
    if (line == 'Application-executed tool results for the latest turn:' ||
        line == 'Output rules:') {
      break;
    }
    if (!line.startsWith('- user:')) {
      continue;
    }
    buffer
      ..write(line.substring('- user:'.length).trim())
      ..write('\n');
  }
  return buffer.toString();
}

bool _isEphemeralDraftMemory(String text) {
  final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  return _ephemeralArtifactMemoryPattern.hasMatch(normalized) ||
      _ephemeralLookupMemoryPattern.hasMatch(normalized);
}

String? _previewNullable(String? value, int maxLength) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return _preview(value, maxLength);
}

String _preview(String value, int maxLength) {
  final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.length <= maxLength) {
    return compact;
  }
  return '${compact.substring(0, maxLength - 1)}...';
}

enum CavernoSessionLogSummaryFormat { markdown, json }

final class CavernoSessionLogSummaryOptions {
  const CavernoSessionLogSummaryOptions({
    required this.logPath,
    required this.format,
  });

  final String logPath;
  final CavernoSessionLogSummaryFormat format;

  static CavernoSessionLogSummaryOptions? parse(List<String> args) {
    String? logPath;
    var format = CavernoSessionLogSummaryFormat.markdown;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--log') {
        index += 1;
        if (index >= args.length) {
          return null;
        }
        logPath = args[index];
      } else if (arg == '--format') {
        index += 1;
        if (index >= args.length) {
          return null;
        }
        final parsedFormat = switch (args[index]) {
          'markdown' => CavernoSessionLogSummaryFormat.markdown,
          'json' => CavernoSessionLogSummaryFormat.json,
          _ => null,
        };
        if (parsedFormat == null) {
          return null;
        }
        format = parsedFormat;
      } else {
        if (arg.startsWith('-')) {
          return null;
        }
        logPath ??= arg;
      }
    }

    if (logPath == null) {
      return null;
    }
    return CavernoSessionLogSummaryOptions(logPath: logPath, format: format);
  }
}

final class CavernoLlmSessionLogSummary {
  const CavernoLlmSessionLogSummary({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.logPath,
    required this.entryCount,
    required this.malformedLineCount,
    required this.result,
    required this.operationCounts,
    required this.finishReasonCounts,
    required this.streamEndLineNumbers,
    required this.loopLimitPromptLineNumbers,
    required this.memoryExtractionLineNumbers,
    required this.autoReviewLineNumbers,
    required this.errorEntries,
    required this.toolCallCount,
    required this.toolCalls,
    required this.entries,
    required this.finalAnswer,
    required this.warnings,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String logPath;
  final int entryCount;
  final int malformedLineCount;
  final String result;
  final Map<String, int> operationCounts;
  final Map<String, int> finishReasonCounts;
  final List<int> streamEndLineNumbers;
  final List<int> loopLimitPromptLineNumbers;
  final List<int> memoryExtractionLineNumbers;
  final List<int> autoReviewLineNumbers;
  final List<SessionLogErrorEntry> errorEntries;
  final int toolCallCount;
  final List<SessionLogToolCallSummary> toolCalls;
  final List<SessionLogEntryDiagnostic> entries;
  final SessionLogEntryDiagnostic? finalAnswer;
  final List<SessionLogWarningEntry> warnings;

  bool get hasFatalError => errorEntries.isNotEmpty;

  bool get hasLoopLimitPrompt => loopLimitPromptLineNumbers.isNotEmpty;

  bool get hasWarnings => warnings.isNotEmpty;

  bool get hasStreamEndMisinterpretationWarning =>
      warnings.any((warning) => warning.code == 'stream_end_misinterpretation');

  bool get hasMemoryEphemeralDraftWarning =>
      warnings.any((warning) => warning.code == 'memory_ephemeral_draft');

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'logPath': logPath,
      'entryCount': entryCount,
      'malformedLineCount': malformedLineCount,
      'result': result,
      'operationCounts': operationCounts,
      'finishReasonCounts': finishReasonCounts,
      'streamEndLineNumbers': streamEndLineNumbers,
      'loopLimitPromptLineNumbers': loopLimitPromptLineNumbers,
      'memoryExtractionLineNumbers': memoryExtractionLineNumbers,
      'autoReviewLineNumbers': autoReviewLineNumbers,
      'errorEntries': errorEntries
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'toolCallCount': toolCallCount,
      'toolCalls': toolCalls
          .map((toolCall) => toolCall.toJson())
          .toList(growable: false),
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'finalAnswer': finalAnswer?.toJson(),
      'warnings': warnings
          .map((warning) => warning.toJson())
          .toList(growable: false),
      'streamEndMisinterpretationWarning': hasStreamEndMisinterpretationWarning,
      'memoryEphemeralDraftWarning': hasMemoryEphemeralDraftWarning,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Caverno LLM Session Log Summary')
      ..writeln()
      ..writeln('- Log: `$logPath`')
      ..writeln('- Result: `$result`')
      ..writeln('- Entries: `$entryCount`')
      ..writeln('- Malformed lines: `$malformedLineCount`')
      ..writeln('- Errors: `${errorEntries.length}`')
      ..writeln('- Warnings: `${warnings.length}`')
      ..writeln('- Tool calls: `$toolCallCount`')
      ..writeln('- Loop-limit prompt: `${hasLoopLimitPrompt ? 'yes' : 'no'}`')
      ..writeln(
        '- Final answer line: `${finalAnswer?.lineNumber ?? 'not found'}`',
      )
      ..writeln()
      ..writeln('## Interpretation')
      ..writeln()
      ..writeln(
        '- `stream_end` means Caverno finished reading a streaming response. '
        'It is not an interruption by itself.',
      )
      ..writeln(
        '- Treat a session as interrupted only when `errorEntries` are present, '
        'no final answer is found, or a loop-limit prompt appears without a '
        'usable final answer.',
      )
      ..writeln();

    if (warnings.isNotEmpty) {
      buffer
        ..writeln('## Warnings')
        ..writeln()
        ..writeln('| Code | Line | Message |')
        ..writeln('|------|------|---------|');
      for (final warning in warnings) {
        buffer.writeln(
          '| `${warning.code}` | ${warning.lineNumber} | '
          '${_markdownCell(warning.message)} |',
        );
      }
      buffer.writeln();
    }

    buffer
      ..writeln('## Counts')
      ..writeln()
      ..writeln('### Operations')
      ..writeln();
    _writeCounts(buffer, operationCounts);
    buffer
      ..writeln()
      ..writeln('### Finish Reasons')
      ..writeln();
    _writeCounts(buffer, finishReasonCounts);
    buffer
      ..writeln()
      ..writeln('## Signals')
      ..writeln()
      ..writeln('- `stream_end` lines: `${streamEndLineNumbers.join(', ')}`')
      ..writeln(
        '- Loop-limit prompt lines: '
        '`${loopLimitPromptLineNumbers.join(', ')}`',
      )
      ..writeln(
        '- Memory extraction lines: '
        '`${memoryExtractionLineNumbers.join(', ')}`',
      )
      ..writeln('- Auto-review lines: `${autoReviewLineNumbers.join(', ')}`');

    if (finalAnswer != null) {
      buffer
        ..writeln()
        ..writeln('## Final Answer Preview')
        ..writeln()
        ..writeln('Line `${finalAnswer!.lineNumber}`:')
        ..writeln()
        ..writeln('```text')
        ..writeln(finalAnswer!.contentPreview)
        ..writeln('```');
    }

    if (errorEntries.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Errors')
        ..writeln()
        ..writeln('| Line | Operation | Type | Message |')
        ..writeln('|------|-----------|------|---------|');
      for (final error in errorEntries) {
        buffer.writeln(
          '| ${error.lineNumber} | `${error.operation}` | '
          '`${error.type ?? ''}` | ${_markdownCell(error.message)} |',
        );
      }
    }

    if (toolCalls.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Tool Calls')
        ..writeln()
        ..writeln('| Line | Tool | Command | Reason |')
        ..writeln('|------|------|---------|--------|');
      for (final toolCall in toolCalls) {
        buffer.writeln(
          '| ${toolCall.lineNumber} | `${toolCall.name}` | '
          '${_markdownCell(toolCall.commandPreview ?? '')} | '
          '${_markdownCell(toolCall.reasonPreview ?? '')} |',
        );
      }
    }

    return buffer.toString();
  }

  void _writeCounts(StringBuffer buffer, Map<String, int> counts) {
    if (counts.isEmpty) {
      buffer.writeln('- none');
      return;
    }
    for (final entry in counts.entries) {
      buffer.writeln('- `${entry.key}`: `${entry.value}`');
    }
  }
}

final class SessionLogEntryDiagnostic {
  const SessionLogEntryDiagnostic({
    required this.lineNumber,
    required this.startedAt,
    required this.finishedAt,
    required this.operation,
    required this.phase,
    required this.finishReason,
    required this.durationMs,
    required this.requestMessageCount,
    required this.requestToolCount,
    required this.requestToolResultCount,
    required this.responseContentLength,
    required this.responseToolCallCount,
    required this.hasError,
    required this.hasLoopLimitPrompt,
    required this.isMemoryExtraction,
    required this.isAutoReview,
    required this.isFinalAnswerCandidate,
    required this.contentPreview,
  });

  final int lineNumber;
  final String? startedAt;
  final String? finishedAt;
  final String operation;
  final String? phase;
  final String? finishReason;
  final int? durationMs;
  final int requestMessageCount;
  final int requestToolCount;
  final int requestToolResultCount;
  final int responseContentLength;
  final int responseToolCallCount;
  final bool hasError;
  final bool hasLoopLimitPrompt;
  final bool isMemoryExtraction;
  final bool isAutoReview;
  final bool isFinalAnswerCandidate;
  final String? contentPreview;

  Map<String, dynamic> toJson() {
    return {
      'lineNumber': lineNumber,
      if (startedAt != null) 'startedAt': startedAt,
      if (finishedAt != null) 'finishedAt': finishedAt,
      'operation': operation,
      if (phase != null) 'phase': phase,
      if (finishReason != null) 'finishReason': finishReason,
      if (durationMs != null) 'durationMs': durationMs,
      'requestMessageCount': requestMessageCount,
      'requestToolCount': requestToolCount,
      'requestToolResultCount': requestToolResultCount,
      'responseContentLength': responseContentLength,
      'responseToolCallCount': responseToolCallCount,
      'hasError': hasError,
      'hasLoopLimitPrompt': hasLoopLimitPrompt,
      'isMemoryExtraction': isMemoryExtraction,
      'isAutoReview': isAutoReview,
      'isFinalAnswerCandidate': isFinalAnswerCandidate,
      if (contentPreview != null) 'contentPreview': contentPreview,
    };
  }
}

final class SessionLogErrorEntry {
  const SessionLogErrorEntry({
    required this.lineNumber,
    required this.operation,
    required this.type,
    required this.message,
  });

  final int lineNumber;
  final String operation;
  final String? type;
  final String message;

  Map<String, dynamic> toJson() {
    return {
      'lineNumber': lineNumber,
      'operation': operation,
      if (type != null) 'type': type,
      'message': message,
    };
  }
}

final class SessionLogWarningEntry {
  const SessionLogWarningEntry({
    required this.code,
    required this.lineNumber,
    required this.message,
    required this.evidencePreview,
  });

  final String code;
  final int lineNumber;
  final String message;
  final String evidencePreview;

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'lineNumber': lineNumber,
      'message': message,
      'evidencePreview': evidencePreview,
    };
  }
}

final class SessionLogToolCallSummary {
  const SessionLogToolCallSummary({
    required this.lineNumber,
    required this.id,
    required this.name,
    required this.commandPreview,
    required this.argumentsPreview,
    required this.reasonPreview,
  });

  final int lineNumber;
  final String? id;
  final String name;
  final String? commandPreview;
  final String argumentsPreview;
  final String? reasonPreview;

  Map<String, dynamic> toJson() {
    return {
      'lineNumber': lineNumber,
      if (id != null) 'id': id,
      'name': name,
      if (commandPreview != null) 'commandPreview': commandPreview,
      'argumentsPreview': argumentsPreview,
      if (reasonPreview != null) 'reasonPreview': reasonPreview,
    };
  }
}

String _markdownCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}
