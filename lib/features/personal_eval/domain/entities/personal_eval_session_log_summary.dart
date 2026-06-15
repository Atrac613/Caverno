import 'dart:collection';
import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'personal_eval_session_log_summary.freezed.dart';
part 'personal_eval_session_log_summary.g.dart';

/// LL19: an in-app summary of an `LlmSessionLogStore` JSONL session log.
///
/// This is the lib-side counterpart of the offline
/// `tool/caverno_session_log_summary.dart` parser, scoped to exactly the
/// structural metrics the `caverno_personal_eval_case_manifest` source block
/// needs (it deliberately drops the CLI's markdown rendering, tool-call
/// previews, and advisory warning heuristics). The `result` derivation matches
/// the CLI so in-app and offline summaries agree.
@freezed
abstract class PersonalEvalSessionLogSummary
    with _$PersonalEvalSessionLogSummary {
  const PersonalEvalSessionLogSummary._();

  const factory PersonalEvalSessionLogSummary({
    @Default('incomplete') String result,
    @Default(0) int entryCount,
    @Default(0) int turnCount,
    @Default(0) int malformedLineCount,
    @Default(0) int toolCallCount,
    @Default(0) int totalDurationMs,
    @Default(<String, int>{}) Map<String, int> operationCounts,
    @Default(<String, int>{}) Map<String, int> finishReasonCounts,
    @Default(<String>[]) List<String> warningCodes,
    @JsonKey(includeIfNull: false) int? finalAnswerLineNumber,
  }) = _PersonalEvalSessionLogSummary;

  factory PersonalEvalSessionLogSummary.fromJson(Map<String, dynamic> json) =>
      _$PersonalEvalSessionLogSummaryFromJson(json);

  /// Parses the raw JSONL contents of a session log file into a summary.
  factory PersonalEvalSessionLogSummary.parseLogContents(String contents) {
    final operationCounts = SplayTreeMap<String, int>();
    final finishReasonCounts = SplayTreeMap<String, int>();
    var malformedLineCount = 0;
    var entryCount = 0;
    var turnCount = 0;
    var toolCallCount = 0;
    var totalDurationMs = 0;
    var hasErrors = false;
    var hasLoopLimitPrompt = false;
    int? finalAnswerLineNumber;

    final lines = const LineSplitter().convert(contents);
    for (var index = 0; index < lines.length; index += 1) {
      final lineNumber = index + 1;
      final line = lines[index].trim();
      if (line.isEmpty) {
        continue;
      }
      final decoded = _decodeJsonObject(line);
      if (decoded == null) {
        malformedLineCount += 1;
        continue;
      }
      entryCount += 1;

      final request = _asStringMap(decoded['request']);
      final response = _asStringMap(decoded['response']);
      final error = _asStringMap(decoded['error']);
      final responseContent = response == null
          ? ''
          : _asString(response['content']) ?? '';
      final responseToolCalls = _asList(response?['toolCalls']);
      final requestMessages = _asList(request?['messages']);
      final operation = _asString(decoded['operation']) ?? 'unknown';
      final finishReason = _asString(response?['finishReason']);
      final requestText = requestMessages.map(_messageText).join('\n');
      final isMemoryExtraction = _isMemoryExtractionResponse(responseContent);
      final isAutoReview = _isAutoReviewResponse(responseContent);
      final hasToolCalls = responseToolCalls.isNotEmpty;
      final hasError = error != null;

      // A turn is a primary agent step; secondary memory-extraction and
      // auto-review calls are excluded (matches the offline parser).
      if (!isMemoryExtraction && !isAutoReview) {
        turnCount += 1;
      }

      operationCounts.update(
        operation,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (finishReason != null) {
        finishReasonCounts.update(
          finishReason,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      if (_hasLoopLimitPrompt(requestText)) {
        hasLoopLimitPrompt = true;
      }
      if (hasError) {
        hasErrors = true;
      }
      toolCallCount += responseToolCalls.length;
      totalDurationMs += _asInt(decoded['durationMs']) ?? 0;

      final isFinalAnswerCandidate =
          responseContent.trim().isNotEmpty &&
          !hasToolCalls &&
          !hasError &&
          !isMemoryExtraction &&
          !isAutoReview;
      if (isFinalAnswerCandidate) {
        finalAnswerLineNumber = lineNumber;
      }
    }

    return PersonalEvalSessionLogSummary(
      result: _summaryResult(
        hasErrors: hasErrors,
        hasLoopLimitPrompt: hasLoopLimitPrompt,
        hasFinalAnswer: finalAnswerLineNumber != null,
      ),
      entryCount: entryCount,
      turnCount: turnCount,
      malformedLineCount: malformedLineCount,
      toolCallCount: toolCallCount,
      totalDurationMs: totalDurationMs,
      operationCounts: Map<String, int>.unmodifiable(operationCounts),
      finishReasonCounts: Map<String, int>.unmodifiable(finishReasonCounts),
      finalAnswerLineNumber: finalAnswerLineNumber,
    );
  }

  /// Builds the manifest `source` block embedding this summary.
  Map<String, dynamic> toCaseManifestSourceJson({
    required String sessionLogPath,
  }) {
    return {'sessionLogPath': sessionLogPath, 'sessionLogSummary': toJson()};
  }
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
    return _asStringMap(jsonDecode(source));
  } on FormatException {
    return null;
  }
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

bool _hasLoopLimitPrompt(String requestText) {
  final normalized = requestText.toLowerCase();
  return normalized.contains('you hit the bounded tool loop limit') ||
      normalized.contains('bounded tool loop limit') ||
      normalized.contains('tool loop reached maximum iterations');
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

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic v) => MapEntry(key.toString(), v));
  }
  return null;
}

String? _asString(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
