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
    'ssh_execute_command',
    'ping',
    'dns_lookup',
    'port_check',
    'ssl_certificate',
    'http_status',
    'http_get',
    'http_head',
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
          _normalizeDetail(selected.failureDetail, maxLength: 280) ??
          'The validation step failed without a structured error.';
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
        _normalizeDetail(selected.successDetail, maxLength: 280) ??
        'The validation step completed successfully.';
    final summary = command.isEmpty
        ? 'Validation passed.'
        : 'Validation passed while running $command.';
    final shouldMarkCompleted =
        task.status == ConversationWorkflowTaskStatus.completed ||
        _looksLikeTerminalValidationTask(task) ||
        _looksLikeDirectTargetExecutionValidation(task, command);
    return ConversationValidationToolResultInferenceResult(
      status: shouldMarkCompleted
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

    return switch (input.toolName) {
      'local_execute_command' ||
      'git_execute_command' => _parseCommandToolResult(rawResult),
      'ssh_execute_command' => _parseSshToolResult(rawResult),
      'ping' => _parsePingToolResult(rawResult),
      'dns_lookup' => _parseDnsLookupToolResult(rawResult),
      'port_check' => _parsePortCheckToolResult(rawResult),
      'ssl_certificate' => _parseSslCertificateToolResult(rawResult),
      'http_status' ||
      'http_get' ||
      'http_head' => _parseHttpToolResult(rawResult),
      _ => null,
    };
  }

  static _ParsedValidationToolResult? _parseCommandToolResult(
    String rawResult,
  ) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return _ParsedValidationToolResult(failureDetail: rawResult);
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
      successDetail: stdout ?? 'The validation command completed successfully.',
      failureDetail: error ?? stderr,
      exitCode: exitCode,
    );
  }

  static _ParsedValidationToolResult? _parseSshToolResult(String rawResult) {
    final exitCodeMatch = RegExp(
      r'^exit_code:\s*(.+)$',
      multiLine: true,
    ).firstMatch(rawResult);
    final exitCodeLabel = exitCodeMatch?.group(1)?.trim();
    final exitCode = exitCodeLabel == null || exitCodeLabel == 'n/a'
        ? null
        : int.tryParse(exitCodeLabel);

    final stdout = _extractSection(rawResult, 'stdout');
    final stderr = _extractSection(rawResult, 'stderr');
    if (exitCode == null && stdout == null && stderr == null) {
      return _ParsedValidationToolResult(failureDetail: rawResult);
    }

    return _ParsedValidationToolResult(
      successDetail:
          stdout ?? 'The SSH validation command completed successfully.',
      failureDetail: stderr,
      exitCode: exitCode,
    );
  }

  static _ParsedValidationToolResult? _parsePingToolResult(String rawResult) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return null;
    }

    final host = _normalizeText(decoded['host']);
    final resolvedIp = _normalizeText(decoded['resolved_ip']);
    final summary = decoded['summary'];
    final results = decoded['results'];
    final received = summary is Map<String, dynamic>
        ? _parseInt(summary['received'])
        : null;
    final transmitted = summary is Map<String, dynamic>
        ? _parseInt(summary['transmitted'])
        : null;
    final lossPercent = summary is Map<String, dynamic>
        ? _parseNum(summary['loss_percent'])
        : null;
    final firstError = results is List
        ? results
              .map(
                (entry) => entry is Map<String, dynamic>
                    ? _normalizeText(entry['message'])
                    : null,
              )
              .whereType<String>()
              .firstOrNull
        : null;
    final command = host == null ? 'ping' : 'ping $host';

    if (received == null || received <= 0) {
      final detail =
          firstError ??
          (host == null
              ? 'Ping did not receive any response packets.'
              : 'Ping did not receive any response packets from $host.');
      return _ParsedValidationToolResult(
        command: command,
        failureDetail: detail,
      );
    }

    final detailBuffer = StringBuffer()..write('Received $received');
    if (transmitted != null) {
      detailBuffer.write(' of $transmitted ping response(s)');
    }
    if (resolvedIp != null) {
      detailBuffer.write(' from $resolvedIp');
    }
    if (lossPercent != null) {
      detailBuffer.write(
        ' with ${lossPercent.toStringAsFixed(1)}% packet loss',
      );
    }
    detailBuffer.write('.');

    return _ParsedValidationToolResult(
      command: command,
      successDetail: detailBuffer.toString(),
    );
  }

  static _ParsedValidationToolResult? _parseDnsLookupToolResult(
    String rawResult,
  ) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return null;
    }

    final host = _normalizeText(decoded['host']);
    final error = _normalizeText(decoded['error']);
    final records = decoded['records'];
    final recordCount = records is List ? records.length : 0;
    final command = host == null ? 'dns_lookup' : 'dns_lookup $host';

    if (error != null || recordCount == 0) {
      return _ParsedValidationToolResult(
        command: command,
        failureDetail:
            error ??
            (host == null
                ? 'DNS lookup returned no records.'
                : 'DNS lookup returned no records for $host.'),
      );
    }

    final addresses = records is List
        ? records
              .map(
                (entry) => entry is Map<String, dynamic>
                    ? _normalizeText(entry['address'])
                    : null,
              )
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return _ParsedValidationToolResult(
      command: command,
      successDetail: addresses.isEmpty
          ? 'Resolved $recordCount DNS record(s).'
          : 'Resolved $recordCount DNS record(s): ${addresses.join(', ')}.',
    );
  }

  static _ParsedValidationToolResult? _parsePortCheckToolResult(
    String rawResult,
  ) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return null;
    }

    final host = _normalizeText(decoded['host']);
    final port = _parseInt(decoded['port']);
    final open = decoded['open'] == true;
    final error = _normalizeText(decoded['error']);
    final responseTimeMs = _parseNum(decoded['response_time_ms']);
    final endpoint = [
      host,
      if (port != null) '$port',
    ].whereType<String>().join(':');
    final command = endpoint.isEmpty ? 'port_check' : 'port_check $endpoint';

    if (!open) {
      return _ParsedValidationToolResult(
        command: command,
        failureDetail:
            error ??
            (endpoint.isEmpty
                ? 'Port check reported that the target port is closed.'
                : 'Port check reported that $endpoint is closed.'),
      );
    }

    final detail = endpoint.isEmpty
        ? 'The target port is open.'
        : responseTimeMs == null
        ? '$endpoint is open.'
        : '$endpoint is open (${responseTimeMs.toStringAsFixed(0)} ms).';
    return _ParsedValidationToolResult(command: command, successDetail: detail);
  }

  static _ParsedValidationToolResult? _parseSslCertificateToolResult(
    String rawResult,
  ) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return null;
    }

    final host = _normalizeText(decoded['host']);
    final port = _parseInt(decoded['port']);
    final error = _normalizeText(decoded['error']);
    final subject = _normalizeText(decoded['subject']);
    final issuer = _normalizeText(decoded['issuer']);
    final validUntil = _normalizeText(decoded['valid_until']);
    final isValidNow = decoded['is_valid_now'];
    final endpoint = [
      host,
      if (port != null) '$port',
    ].whereType<String>().join(':');
    final command = endpoint.isEmpty
        ? 'ssl_certificate'
        : 'ssl_certificate $endpoint';

    if (error != null) {
      return _ParsedValidationToolResult(
        command: command,
        failureDetail: error,
      );
    }

    if (isValidNow == false) {
      final detail = validUntil == null
          ? 'The certificate is not currently valid.'
          : 'The certificate is not currently valid and expires at $validUntil.';
      return _ParsedValidationToolResult(
        command: command,
        failureDetail: detail,
      );
    }

    if (subject == null) {
      return null;
    }

    final detailBuffer = StringBuffer()..write('Certificate subject: $subject');
    if (issuer != null) {
      detailBuffer.write('; issuer: $issuer');
    }
    if (validUntil != null) {
      detailBuffer.write('; valid until: $validUntil');
    }
    detailBuffer.write('.');

    return _ParsedValidationToolResult(
      command: command,
      successDetail: detailBuffer.toString(),
    );
  }

  static _ParsedValidationToolResult? _parseHttpToolResult(String rawResult) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return null;
    }

    final method = _normalizeText(decoded['method']) ?? 'GET';
    final url = _normalizeText(decoded['url']);
    final statusCode = _parseInt(decoded['status_code']);
    final reasonPhrase = _normalizeText(decoded['reason_phrase']);
    final error = _normalizeText(decoded['error']);
    final responseTimeMs = _parseNum(decoded['response_time_ms']);
    final command = url == null ? method : '$method $url';

    if (error != null) {
      return _ParsedValidationToolResult(
        command: command,
        failureDetail: error,
      );
    }

    if (statusCode == null) {
      return null;
    }

    final detailBuffer = StringBuffer()..write('Received HTTP $statusCode');
    if (reasonPhrase != null) {
      detailBuffer.write(' $reasonPhrase');
    }
    if (url != null) {
      detailBuffer.write(' from $url');
    }
    if (responseTimeMs != null) {
      detailBuffer.write(' (${responseTimeMs.toStringAsFixed(0)} ms)');
    }
    detailBuffer.write('.');

    if (statusCode >= 400) {
      return _ParsedValidationToolResult(
        command: command,
        failureDetail: detailBuffer.toString(),
      );
    }

    return _ParsedValidationToolResult(
      command: command,
      successDetail: detailBuffer.toString(),
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

  static int? _parseInt(dynamic value) {
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

  static double? _parseNum(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
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

  static bool _looksLikeTerminalValidationTask(ConversationWorkflowTask task) {
    final normalized = '${task.title.trim()} ${task.notes.trim()}'
        .toLowerCase();
    const keywords = <String>[
      'verify ',
      'verification',
      'smoke test',
      'test script',
      'test the cli',
      'loopback',
      'real host',
      'live host',
    ];
    return keywords.any(normalized.contains);
  }

  static bool _looksLikeDirectTargetExecutionValidation(
    ConversationWorkflowTask task,
    String command,
  ) {
    final normalizedCommand = command.trim().toLowerCase();
    if (normalizedCommand.isEmpty) {
      return false;
    }

    final launchesExecutableTarget =
        normalizedCommand.startsWith('python ') ||
        normalizedCommand.startsWith('python3 ') ||
        normalizedCommand.startsWith('./') ||
        normalizedCommand.startsWith('bash ') ||
        normalizedCommand.startsWith('sh ');
    if (!launchesExecutableTarget) {
      return false;
    }

    final effectiveTargets = _effectiveTargetFiles(task);
    if (effectiveTargets.isEmpty) {
      return false;
    }

    return effectiveTargets.any(
      (target) =>
          normalizedCommand.contains(target) ||
          normalizedCommand.contains('/$target'),
    );
  }

  static Set<String> _effectiveTargetFiles(ConversationWorkflowTask task) {
    final explicitTargets = task.targetFiles
        .map(_normalizeText)
        .whereType<String>()
        .map((target) => target.toLowerCase())
        .toSet();
    if (explicitTargets.isNotEmpty) {
      return explicitTargets;
    }
    return _inferTargetFilesFromText(task.validationCommand);
  }

  static Set<String> _inferTargetFilesFromText(String text) {
    final matches = RegExp(
      r'(?:(?:^|[\s`"(]))([A-Za-z0-9_./-]+\.[A-Za-z][A-Za-z0-9]{0,7}|__init__\.py|\.gitignore)(?=$|[\s`)",.:;])',
      caseSensitive: false,
    ).allMatches(text);
    final inferredTargets = <String>{};
    for (final match in matches) {
      final candidate = _normalizeText(match.group(1))?.toLowerCase();
      if (candidate == null) {
        continue;
      }
      inferredTargets.add(candidate);
    }
    return inferredTargets;
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

  static String? _extractSection(String rawResult, String label) {
    final startMarker = '--- $label ---';
    final startIndex = rawResult.indexOf(startMarker);
    if (startIndex < 0) {
      return null;
    }

    final contentStart = startIndex + startMarker.length;
    final nextMarkerIndex = rawResult.indexOf('--- ', contentStart);
    final section = nextMarkerIndex < 0
        ? rawResult.substring(contentStart)
        : rawResult.substring(contentStart, nextMarkerIndex);
    return _normalizeText(section);
  }
}

class _ParsedValidationToolResult {
  const _ParsedValidationToolResult({
    this.command,
    this.successDetail,
    this.failureDetail,
    this.exitCode,
  });

  final String? command;
  final String? successDetail;
  final String? failureDetail;
  final int? exitCode;

  bool get isFailure =>
      failureDetail != null || (exitCode != null && exitCode != 0);
}
