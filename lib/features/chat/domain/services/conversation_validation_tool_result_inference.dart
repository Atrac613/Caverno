import 'dart:convert';

import '../entities/conversation_workflow.dart';

class ConversationValidationToolResultInput {
  const ConversationValidationToolResultInput({
    required this.toolName,
    required this.rawResult,
  });

  final String toolName;
  final String rawResult;
}

class ConversationValidationToolResultInferenceResult {
  const ConversationValidationToolResultInferenceResult({
    required this.status,
    required this.validationStatus,
    required this.summary,
    required this.validationCommand,
    required this.validationSummary,
    this.blockedReason,
  });

  final ConversationWorkflowTaskStatus status;
  final ConversationExecutionValidationStatus validationStatus;
  final String summary;
  final String validationCommand;
  final String validationSummary;
  final String? blockedReason;
}

class ConversationValidationToolResultInference {
  static const _supportedToolNames = <String>{
    'local_execute_command',
    'git_execute_command',
  };

  static ConversationValidationToolResultInferenceResult? infer({
    required ConversationWorkflowTask task,
    required Iterable<ConversationValidationToolResultInput> toolResults,
  }) {
    final relevantResults = toolResults
        .where((result) => _supportedToolNames.contains(result.toolName))
        .map(_parseToolResult)
        .whereType<_ParsedValidationToolResult>()
        .toList(growable: false);
    if (relevantResults.isEmpty) {
      return null;
    }

    final selected = _selectMostRelevantResult(relevantResults);
    final command = _resolveCommand(selected.command, task.validationCommand);

    if (selected.isFailure) {
      final detail =
          _normalizeDetail(selected.stderr, maxLength: 280) ??
          _normalizeDetail(selected.error, maxLength: 280) ??
          'The validation command failed without a structured error.';
      final summary = command.isEmpty
          ? 'Validation failed.'
          : 'Validation failed while running $command.';
      return ConversationValidationToolResultInferenceResult(
        status: ConversationWorkflowTaskStatus.blocked,
        validationStatus: ConversationExecutionValidationStatus.failed,
        summary: summary,
        blockedReason: detail,
        validationCommand: command,
        validationSummary: detail,
      );
    }

    final detail =
        _normalizeDetail(selected.stdout, maxLength: 280) ??
        'The validation command completed successfully.';
    final summary = command.isEmpty
        ? 'Validation passed.'
        : 'Validation passed while running $command.';
    return ConversationValidationToolResultInferenceResult(
      status: task.status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowTaskStatus.completed
          : ConversationWorkflowTaskStatus.inProgress,
      validationStatus: ConversationExecutionValidationStatus.passed,
      summary: summary,
      validationCommand: command,
      validationSummary: detail,
    );
  }

  static _ParsedValidationToolResult _selectMostRelevantResult(
    List<_ParsedValidationToolResult> results,
  ) {
    for (final result in results.reversed) {
      if (result.isFailure) {
        return result;
      }
    }
    return results.last;
  }

  static _ParsedValidationToolResult? _parseToolResult(
    ConversationValidationToolResultInput input,
  ) {
    final rawResult = input.rawResult.trim();
    if (rawResult.isEmpty) {
      return null;
    }

    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return _ParsedValidationToolResult(error: rawResult);
    }

    final command = _normalizeText(decoded['command']);
    final error = _normalizeText(decoded['error']);
    final stdout = _normalizeText(decoded['stdout']);
    final stderr = _normalizeText(decoded['stderr']);
    final exitCode = _parseExitCode(decoded['exit_code']);
    if (command == null &&
        error == null &&
        stdout == null &&
        stderr == null &&
        exitCode == null) {
      return null;
    }

    return _ParsedValidationToolResult(
      command: command,
      exitCode: exitCode,
      error: error,
      stdout: stdout,
      stderr: stderr,
    );
  }

  static Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static int? _parseExitCode(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static String _resolveCommand(String? inferred, String fallback) {
    final normalizedInferred = _normalizeText(inferred);
    if (normalizedInferred != null) {
      return normalizedInferred;
    }
    return fallback.trim();
  }

  static String? _normalizeText(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String? _normalizeDetail(String? value, {required int maxLength}) {
    final normalized = _normalizeText(value);
    if (normalized == null) {
      return null;
    }
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }
}

class _ParsedValidationToolResult {
  const _ParsedValidationToolResult({
    this.command,
    this.exitCode,
    this.error,
    this.stdout,
    this.stderr,
  });

  final String? command;
  final int? exitCode;
  final String? error;
  final String? stdout;
  final String? stderr;

  bool get isFailure => error != null || (exitCode != null && exitCode != 0);
}
