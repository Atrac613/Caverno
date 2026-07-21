import 'dart:convert';

import '../entities/message.dart';

class ConversationToolResultPruneResult {
  const ConversationToolResultPruneResult({
    required this.messages,
    required this.originalCharacterCount,
    required this.prunedCharacterCount,
    required this.summarizedResultCount,
    required this.duplicateResultCount,
  });

  final List<Message> messages;
  final int originalCharacterCount;
  final int prunedCharacterCount;
  final int summarizedResultCount;
  final int duplicateResultCount;

  int get savedCharacterCount => originalCharacterCount - prunedCharacterCount;

  double get savingsRatio => originalCharacterCount <= 0
      ? 0
      : savedCharacterCount / originalCharacterCount;
}

/// Structurally reduces old rendered tool results at compaction boundaries.
///
/// Exact duplicate sections are detected newest-first so older copies can
/// point at the later result. Every parsed result becomes one informative line
/// that retains its tool name, key argument, and outcome. Content that does not
/// match Caverno's rendered tool-result format is preserved verbatim.
class ConversationToolResultPruner {
  ConversationToolResultPruner._();

  static final RegExp _toolMarkerPattern = RegExp(
    r'^\[Tool: ([a-zA-Z0-9_.-]+)\]\s*$',
    multiLine: true,
  );
  static final RegExp _argumentsPattern = RegExp(
    r'^Arguments:\s*(.+)$',
    multiLine: true,
  );
  static const String _resultMarker = '\nResult:\n';
  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static const int _maxTargetLength = 88;
  static const int _maxOutcomeLength = 100;

  static ConversationToolResultPruneResult prune(List<Message> messages) {
    final originalCharacterCount = _characterCount(messages);
    final seenSections = <String>{};
    final transformed = List<Message>.from(messages);
    var summarizedResultCount = 0;
    var duplicateResultCount = 0;

    for (
      var messageIndex = messages.length - 1;
      messageIndex >= 0;
      messageIndex--
    ) {
      final message = messages[messageIndex];
      final parsed = _parseMessage(message.content);
      if (parsed == null) {
        continue;
      }

      final renderedParts = <String>[];
      if (parsed.preamble.trim().isNotEmpty) {
        renderedParts.add(parsed.preamble.trim());
      }
      var changed = false;
      for (
        var sectionIndex = parsed.sections.length - 1;
        sectionIndex >= 0;
        sectionIndex--
      ) {
        final section = parsed.sections[sectionIndex];
        if (!section.isResult) {
          continue;
        }
        section.isDuplicate = !seenSections.add(section.fingerprint);
        summarizedResultCount++;
        if (section.isDuplicate) {
          duplicateResultCount++;
        }
        changed = true;
      }
      if (!changed) {
        continue;
      }

      for (final section in parsed.sections) {
        renderedParts.add(
          section.isResult ? _summarize(section) : section.raw.trim(),
        );
      }
      transformed[messageIndex] = message.copyWith(
        content: renderedParts.where((part) => part.isNotEmpty).join('\n'),
      );
    }

    return ConversationToolResultPruneResult(
      messages: List<Message>.unmodifiable(transformed),
      originalCharacterCount: originalCharacterCount,
      prunedCharacterCount: _characterCount(transformed),
      summarizedResultCount: summarizedResultCount,
      duplicateResultCount: duplicateResultCount,
    );
  }

  static _ParsedToolResultMessage? _parseMessage(String content) {
    final matches = _toolMarkerPattern.allMatches(content).toList();
    if (matches.isEmpty ||
        content.substring(0, matches.first.start).trim().isNotEmpty) {
      return null;
    }

    final sections = <_ParsedToolResultSection>[];
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final end = index + 1 < matches.length
          ? matches[index + 1].start
          : content.length;
      final raw = content.substring(match.start, end).trimRight();
      final markerOffset = raw.indexOf(_resultMarker);
      if (markerOffset < 0) {
        sections.add(
          _ParsedToolResultSection.unparsed(name: match.group(1)!, raw: raw),
        );
        continue;
      }

      final header = raw.substring(0, markerOffset);
      final payload = raw.substring(markerOffset + _resultMarker.length).trim();
      final argumentsMatch = _argumentsPattern.firstMatch(header);
      final argumentsText = argumentsMatch?.group(1)?.trim() ?? '';
      sections.add(
        _ParsedToolResultSection.result(
          name: match.group(1)!,
          raw: raw,
          argumentsText: argumentsText,
          arguments: _decodeMap(argumentsText),
          payload: payload,
          decodedPayload: _decodeMap(payload),
        ),
      );
    }

    if (sections.any((section) => !section.isResult)) {
      return null;
    }
    return _ParsedToolResultMessage(
      preamble: content.substring(0, matches.first.start),
      sections: sections,
    );
  }

  static String _summarize(_ParsedToolResultSection section) {
    final target = _targetFor(section.arguments);
    var outcome = _outcomeFor(
      section.name,
      section.payload,
      section.decodedPayload,
    );
    if (section.isDuplicate) {
      outcome = 'duplicate of later result; $outcome';
    }
    return '[${section.name}] ${_truncate(target, _maxTargetLength)} '
        '-> ${_truncate(outcome, _maxOutcomeLength)}';
  }

  static String _targetFor(Map<String, dynamic>? arguments) {
    if (arguments == null || arguments.isEmpty) {
      return 'call';
    }
    final command = _clean(arguments['command']);
    if (command != null) {
      return '`$command`';
    }
    final path = _clean(arguments['path']);
    if (path != null) {
      final offset = _asInt(arguments['offset']);
      return offset == null ? path : '$path from line ${offset + 1}';
    }
    final query = _clean(arguments['query'] ?? arguments['pattern']);
    if (query != null) {
      return '"$query"';
    }
    final url = _clean(arguments['url'] ?? arguments['host']);
    if (url != null) {
      return url;
    }
    return 'call';
  }

  static String _outcomeFor(
    String toolName,
    String payload,
    Map<String, dynamic>? decoded,
  ) {
    final error = _clean(decoded?['error']);
    if (error != null) {
      return 'error: $error';
    }
    final exitCode = _asInt(decoded?['exit_code']);
    if (exitCode != null) {
      final rawOutput = decoded?['stdout'] ?? decoded?['output'];
      final lineCount = rawOutput is String && rawOutput.trim().isNotEmpty
          ? const LineSplitter().convert(rawOutput).length
          : 0;
      return lineCount > 0
          ? 'exit $exitCode, $lineCount output lines'
          : 'exit $exitCode';
    }
    final matchCount = _asInt(
      decoded?['match_count'] ?? decoded?['entry_count'],
    );
    if (matchCount != null) {
      return '$matchCount results';
    }
    final replacements = _asInt(decoded?['replacements']);
    if (replacements != null) {
      return '$replacements replacements';
    }
    final bytesWritten = _asInt(decoded?['bytes_written']);
    if (bytesWritten != null) {
      return '$bytesWritten bytes written';
    }
    if (decoded?['already_applied'] == true) {
      return 'already applied; no file change';
    }
    if (decoded?['changed'] is bool) {
      return decoded!['changed'] == true ? 'changed' : 'unchanged';
    }

    final content = decoded?['content'];
    if (content is String) {
      return '${content.length} content chars';
    }
    if (toolName == 'read_file') {
      return '${payload.length} content chars';
    }
    if (decoded != null) {
      return '${decoded.length} result fields';
    }
    final normalized = payload.replaceAll(_whitespacePattern, ' ').trim();
    if (normalized.isEmpty) {
      return 'empty result';
    }
    return 'result: $normalized';
  }

  static Map<String, dynamic>? _decodeMap(String value) {
    if (value.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _clean(Object? value) {
    final normalized = value
        ?.toString()
        .replaceAll(_whitespacePattern, ' ')
        .trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static int? _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength - 3)}...';
  }

  static int _characterCount(List<Message> messages) {
    return messages.fold<int>(
      0,
      (total, message) => total + message.content.length,
    );
  }
}

class _ParsedToolResultMessage {
  const _ParsedToolResultMessage({
    required this.preamble,
    required this.sections,
  });

  final String preamble;
  final List<_ParsedToolResultSection> sections;
}

class _ParsedToolResultSection {
  _ParsedToolResultSection.result({
    required this.name,
    required this.raw,
    required this.argumentsText,
    required this.arguments,
    required this.payload,
    required this.decodedPayload,
  }) : isResult = true;

  _ParsedToolResultSection.unparsed({required this.name, required this.raw})
    : isResult = false,
      argumentsText = '',
      arguments = null,
      payload = '',
      decodedPayload = null;

  final String name;
  final String raw;
  final bool isResult;
  final String argumentsText;
  final Map<String, dynamic>? arguments;
  final String payload;
  final Map<String, dynamic>? decodedPayload;
  bool isDuplicate = false;

  String get fingerprint => '$name\n$argumentsText\n$payload';
}
