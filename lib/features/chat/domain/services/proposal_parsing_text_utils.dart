import 'dart:convert';

import '../../../../core/utils/content_parser.dart';
import '../entities/conversation_workflow.dart';

class ProposalJsonExtractor {
  const ProposalJsonExtractor({void Function()? onJsonRepair})
    : _onJsonRepair = onJsonRepair;

  final void Function()? _onJsonRepair;

  Map<String, dynamic>? extractJsonMap(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) return null;

    final fencedMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final candidate = fencedMatch?.group(1)?.trim() ?? trimmed;

    final direct = ProposalParsingTextUtils.tryDecodeMap(candidate);
    if (direct != null) return direct;
    final repairedDirect = ProposalParsingTextUtils.tryRepairAndDecodeMap(
      candidate,
    );
    if (repairedDirect != null) {
      _onJsonRepair?.call();
      return repairedDirect;
    }

    final firstBrace = candidate.indexOf('{');
    final lastBrace = candidate.lastIndexOf('}');
    if (firstBrace < 0) {
      return null;
    }
    if (lastBrace > firstBrace) {
      final sliced = candidate.substring(firstBrace, lastBrace + 1).trim();
      final slicedDirect = ProposalParsingTextUtils.tryDecodeMap(sliced);
      if (slicedDirect != null) return slicedDirect;
      final repairedSliced = ProposalParsingTextUtils.tryRepairAndDecodeMap(
        sliced,
      );
      if (repairedSliced != null) {
        _onJsonRepair?.call();
      }
      return repairedSliced;
    }
    final repairedTrailing = ProposalParsingTextUtils.tryRepairAndDecodeMap(
      candidate.substring(firstBrace).trim(),
    );
    if (repairedTrailing != null) {
      _onJsonRepair?.call();
    }
    return repairedTrailing;
  }
}

class ProposalParsingTextUtils {
  const ProposalParsingTextUtils._();

  static Map<String, dynamic>? tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? tryRepairAndDecodeMap(String value) {
    final repaired = repairJsonCandidate(value);
    if (repaired == null) return null;
    return tryDecodeMap(repaired);
  }

  static String? repairJsonCandidate(String value) {
    var candidate = value.trim();
    if (candidate.isEmpty || !candidate.contains('{')) {
      return null;
    }

    final start = candidate.indexOf('{');
    candidate = candidate.substring(start).trimRight();
    if (candidate.isEmpty) return null;

    final buffer = StringBuffer();
    final closers = <String>[];
    var inString = false;
    var isEscaped = false;

    for (var i = 0; i < candidate.length; i++) {
      final char = candidate[i];
      buffer.write(char);

      if (inString) {
        if (isEscaped) {
          isEscaped = false;
          continue;
        }
        if (char == r'\') {
          isEscaped = true;
          continue;
        }
        if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
        continue;
      }
      if (char == '{') {
        closers.add('}');
      } else if (char == '[') {
        closers.add(']');
      } else if (char == '}' || char == ']') {
        if (closers.isNotEmpty && closers.last == char) {
          closers.removeLast();
        }
      }
    }

    var repaired = buffer.toString().trimRight();
    if (inString && !isEscaped) {
      repaired = '$repaired"';
    }
    repaired = repaired.replaceFirst(RegExp(r'[\s,:]+$'), '');
    if (repaired.isEmpty) {
      return null;
    }
    if (repaired.endsWith('"') && repaired.split('"').length.isOdd) {
      repaired = '$repaired"';
    }

    for (final closer in closers.reversed) {
      repaired = '$repaired$closer';
    }
    return repaired;
  }

  static String? extractLooseJsonScalar(
    String rawContent, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      final quotedPattern = RegExp(
        "[\\\"']?${RegExp.escape(key)}[\\\"']?\\s*:\\s*(?:\\\"([^\\\"]*)\\\"|'([^']*)'|([A-Za-z_]+))",
        caseSensitive: false,
        dotAll: true,
      );
      final quotedMatch = quotedPattern.firstMatch(rawContent);
      if (quotedMatch == null) {
        continue;
      }
      final value =
          quotedMatch.group(1) ??
          quotedMatch.group(2) ??
          quotedMatch.group(3) ??
          '';
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  static List<String> extractLooseJsonStringList(
    String rawContent, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      final listPattern = RegExp(
        "[\\\"']?${RegExp.escape(key)}[\\\"']?\\s*:\\s*\\[(.*?)(?:\\]\\s*(?:,|\\}|\$)|\$)",
        caseSensitive: false,
        dotAll: true,
      );
      final match = listPattern.firstMatch(rawContent);
      if (match == null) {
        continue;
      }
      final body = match.group(1)?.trim() ?? '';
      if (body.isEmpty) {
        continue;
      }

      final items = RegExp('"([^"]*)"|\'([^\']*)\'', dotAll: true)
          .allMatches(body)
          .map((entry) {
            return (entry.group(1) ?? entry.group(2) ?? '').trim();
          })
          .where((item) => item.isNotEmpty)
          .take(6)
          .toList(growable: false);

      if (items.isNotEmpty) {
        return items;
      }
    }
    return const [];
  }

  static Map<String, List<String>> collectProposalSections(String rawContent) {
    final sections = <String, List<String>>{
      'workflowStage': <String>[],
      'goal': <String>[],
      'constraints': <String>[],
      'acceptanceCriteria': <String>[],
      'openQuestions': <String>[],
    };

    String? currentSection;
    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = matchWorkflowSectionLine(line);
      if (match != null) {
        currentSection = match.$1;
        final value = stripMarkdownListMarker(match.$2);
        if (value.isNotEmpty) {
          sections[currentSection]!.add(value);
        }
        continue;
      }

      if (currentSection == null) continue;
      final value = stripMarkdownListMarker(line);
      if (value.isEmpty) continue;
      sections[currentSection]!.add(value);
    }
    return sections;
  }

  static (String, String)? matchWorkflowSectionLine(String line) {
    final normalizedLine = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    for (final entry in {
      'workflowStage': ['workflow stage', 'stage', 'ワークフローステージ', 'ステージ'],
      'goal': ['goal', '目的'],
      'constraints': ['constraints', 'constraint', '制約'],
      'acceptanceCriteria': [
        'acceptance criteria',
        'acceptance',
        '完了条件',
        '受け入れ条件',
      ],
      'openQuestions': ['open questions', 'questions', '未解決の確認事項', '確認事項'],
    }.entries) {
      for (final label in entry.value) {
        final inlineMatch = RegExp(
          '^(?:[-*]\\s*)?${RegExp.escape(label)}\\s*[:：-]\\s*(.*)\$',
          caseSensitive: false,
        ).firstMatch(normalizedLine);
        if (inlineMatch != null) {
          return (entry.key, inlineMatch.group(1)?.trim() ?? '');
        }
        if (normalizedLine.toLowerCase() == label.toLowerCase()) {
          return (entry.key, '');
        }
      }
    }
    return null;
  }

  static ConversationWorkflowStage? inferWorkflowStageFromSectionKeys(
    Map<String, List<String>> sections,
  ) {
    if ((sections['openQuestions'] ?? const []).isNotEmpty) {
      return ConversationWorkflowStage.clarify;
    }
    if ((sections['acceptanceCriteria'] ?? const []).isNotEmpty ||
        (sections['constraints'] ?? const []).isNotEmpty ||
        (sections['goal'] ?? const []).isNotEmpty) {
      return ConversationWorkflowStage.plan;
    }
    return null;
  }

  static ConversationWorkflowStage inferWorkflowStageFromLooseProposalContent(
    String rawContent,
  ) {
    final openQuestions = extractLooseJsonStringList(
      rawContent,
      keys: const ['openQuestions', 'open_questions', 'questions', '未解決の確認事項'],
    );
    return openQuestions.isNotEmpty
        ? ConversationWorkflowStage.clarify
        : ConversationWorkflowStage.plan;
  }

  static String normalizeProposalContent(String rawContent) {
    return rawContent
        .replaceAll(
          RegExp(
            r'<(?:think|thinking|thought)>[\s\S]*?</(?:think|thinking|thought)>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'</?(?:think|thinking|thought)>', caseSensitive: false),
          ' ',
        )
        .trim();
  }

  static String extractProposalReasoningContent(String rawContent) {
    final matches = RegExp(
      r'<(?:think|thinking|thought)>([\s\S]*?)</(?:think|thinking|thought)>',
      caseSensitive: false,
    ).allMatches(rawContent);
    if (matches.isEmpty) {
      return '';
    }

    return matches
        .map((match) => (match.group(1) ?? '').trim())
        .where((chunk) => chunk.isNotEmpty)
        .join('\n')
        .trim();
  }

  static String extractStructuredWorkflowProposalReasoning(String rawContent) {
    final buffer = StringBuffer();
    String? currentSection;

    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final sectionMatch = matchWorkflowSectionLine(line);
      if (sectionMatch != null) {
        currentSection = sectionMatch.$1;
        final cleanedValue = sanitizeReasoningProposalValue(
          stripMarkdownListMarker(sectionMatch.$2),
          preferSingleSentence: currentSection == 'goal',
        );
        final label = workflowSectionDisplayLabel(currentSection);
        if (cleanedValue.isEmpty) {
          buffer.writeln('$label:');
        } else {
          buffer.writeln('$label: $cleanedValue');
        }
        if (!isWorkflowListSection(currentSection)) {
          currentSection = null;
        }
        continue;
      }

      if (currentSection == null || !isWorkflowListSection(currentSection)) {
        continue;
      }
      if (!looksLikeStructuredReasoningListItem(line)) {
        continue;
      }

      final cleanedValue = sanitizeReasoningProposalValue(
        stripMarkdownListMarker(line),
      );
      if (cleanedValue.isEmpty) {
        continue;
      }
      buffer.writeln('- $cleanedValue');
    }

    return buffer.toString().trim();
  }

  static String extractStructuredTaskProposalReasoning(String rawContent) {
    final buffer = StringBuffer();
    String? currentField;
    var taskCount = 0;

    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final taskTitle = matchTaskTitleLine(line, currentField: currentField);
      if (taskTitle != null) {
        taskCount++;
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.writeln(
          '$taskCount. ${sanitizeReasoningProposalValue(taskTitle, preferSingleSentence: true)}',
        );
        currentField = null;
        continue;
      }

      final taskField = matchTaskFieldLine(line);
      if (taskField != null) {
        currentField = taskField.$1;
        final cleanedValue = sanitizeReasoningProposalValue(
          stripMarkdownListMarker(taskField.$2),
          preferSingleSentence: currentField != 'notes',
        );
        final label = taskFieldDisplayLabel(currentField);
        if (cleanedValue.isEmpty) {
          buffer.writeln('$label:');
        } else {
          buffer.writeln('$label: $cleanedValue');
        }
        continue;
      }

      if (currentField == null || !looksLikeStructuredReasoningListItem(line)) {
        continue;
      }

      final cleanedValue = sanitizeReasoningProposalValue(
        stripMarkdownListMarker(line),
      );
      if (cleanedValue.isEmpty) {
        continue;
      }
      buffer.writeln('- $cleanedValue');
    }

    return buffer.toString().trim();
  }

  static bool looksLikeStructuredReasoningListItem(String line) {
    return RegExp(r'^(?:[-*•]|\d+[.)])\s+').hasMatch(line.trim());
  }

  static bool isWorkflowListSection(String section) {
    return section == 'constraints' ||
        section == 'acceptanceCriteria' ||
        section == 'openQuestions';
  }

  static String workflowSectionDisplayLabel(String section) {
    return switch (section) {
      'workflowStage' => 'Workflow Stage',
      'goal' => 'Goal',
      'constraints' => 'Constraints',
      'acceptanceCriteria' => 'Acceptance Criteria',
      'openQuestions' => 'Open Questions',
      _ => section,
    };
  }

  static String taskFieldDisplayLabel(String field) {
    return switch (field) {
      'targetFiles' => 'Target files',
      'validationCommand' => 'Validation command',
      'notes' => 'Notes',
      _ => field,
    };
  }

  static String asCleanString(Object? value) {
    return value?.toString().trim() ?? '';
  }

  static List<String> asStringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(6)
        .toList(growable: false);
  }

  static bool isCompletionTruncated(String finishReason) {
    final normalized = finishReason.trim().toLowerCase();
    return normalized == 'length';
  }

  static String stripMarkdownListMarker(String value) {
    return value.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s*'), '').trim();
  }

  static String appendTextValue(String current, String next) {
    if (current.isEmpty) return next;
    return '$current $next';
  }

  static String proposalPreview(String rawContent) {
    var normalized = normalizeProposalContent(
      rawContent,
    ).replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      normalized = extractProposalReasoningContent(
        rawContent,
      ).replaceAll(RegExp(r'\s+'), ' ');
    }
    if (normalized.length <= 220) {
      return normalized;
    }
    return '${normalized.substring(0, 220)}...';
  }

  static String extractPlainTextForProposal(String content) {
    final parsed = ContentParser.parse(content);
    final buffer = StringBuffer();
    for (final segment in parsed.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String extractInlineTaskPlanCandidate(String rawContent) {
    final planMatch = RegExp(
      r'(?:^|[\s(])(?:plan|tasks?)\s*[:：-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawContent);
    return (planMatch?.group(1) ?? rawContent).trim();
  }

  static String sanitizeInlineReasoningTaskTitle(String rawValue) {
    var candidate = sanitizeReasoningProposalValue(
      rawValue,
      preferSingleSentence: true,
    );
    if (candidate.isEmpty) {
      return '';
    }

    final fieldMatch = RegExp(
      r'\b(?:target files?|validation command|validation|notes?)\s*[:：-]',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (fieldMatch != null && fieldMatch.start > 0) {
      candidate = candidate.substring(0, fieldMatch.start).trim();
    }

    candidate = candidate.replaceFirst(
      RegExp(r'^(?:task|title)\s*[:：-]\s*', caseSensitive: false),
      '',
    );
    return candidate.trim();
  }

  static String _stripWrappingQuotes(String value) {
    return value.replaceAll(RegExp("^[`\"']+|[`\"']+\$"), '');
  }

  static String sanitizeReasoningProposalValue(
    String value, {
    bool preferSingleSentence = false,
  }) {
    var candidate = _stripWrappingQuotes(
      value.trim(),
    ).replaceAll(RegExp(r'\s+'), ' ');
    if (candidate.isEmpty) {
      return '';
    }

    const suspiciousMarkers = <String>[
      'Recent Context:',
      'Previous session',
      'Previous sessions',
      'Current State:',
      'The current state is',
      'The project name is',
      'Project name is',
      'The project root',
      'The research context',
      'The current workspace',
      'The workspace is',
      'The repository is',
      "The user's request is",
      'Self-Correction',
      'Actually,',
      'Actually ',
      'Wait,',
      'Wait ',
      "Let's check",
      "Let's refine",
      "The user's intent",
      'The prompt asks',
      'kind:',
      'workflowStage:',
      'acceptanceCriteria:',
      'openQuestions:',
      'decisions:',
      "'kind'",
      '"kind"',
      "'workflowStage'",
      '"workflowStage"',
      "'goal'",
      '"goal"',
      "'constraints'",
      '"constraints"',
      "'acceptanceCriteria'",
      '"acceptanceCriteria"',
      "'openQuestions'",
      '"openQuestions"',
      "'decisions'",
      '"decisions"',
    ];

    final lowerCandidate = candidate.toLowerCase();
    var cutIndex = candidate.length;
    for (final marker in suspiciousMarkers) {
      final index = lowerCandidate.indexOf(marker.toLowerCase());
      if (index > 0 && index < cutIndex) {
        cutIndex = index;
      }
    }
    candidate = candidate.substring(0, cutIndex).trim();

    if (preferSingleSentence && candidate.length > 160) {
      final sentenceBreak = RegExp(r'(?<=[.!?])\s+').firstMatch(candidate);
      if (sentenceBreak != null && sentenceBreak.start > 32) {
        candidate = candidate.substring(0, sentenceBreak.start).trim();
      }
    }

    return candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? matchTaskTitleLine(String line, {String? currentField}) {
    final normalizedLine = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    final labeledMatch = RegExp(
      r'^(?:title|task title|task|タイトル|タスク名)\s*[:：-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(normalizedLine);
    if (labeledMatch != null) {
      final value = stripMarkdownListMarker(labeledMatch.group(1) ?? '');
      return value.isEmpty ? null : value;
    }

    final bulletMatch = RegExp(
      r'^([-*•]|\d+[.)])\s+(.+)$',
    ).firstMatch(normalizedLine);
    if (bulletMatch == null) return null;
    final marker = bulletMatch.group(1) ?? '';
    if (currentField != null && !RegExp(r'^\d+[.)]$').hasMatch(marker)) {
      return null;
    }

    final candidate = (bulletMatch.group(2) ?? '').trim();
    final lowerCandidate = candidate.toLowerCase();
    if (lowerCandidate.startsWith('target files') ||
        lowerCandidate.startsWith('validation') ||
        lowerCandidate.startsWith('notes') ||
        lowerCandidate.startsWith('files') ||
        candidate.startsWith('対象ファイル') ||
        candidate.startsWith('確認コマンド') ||
        candidate.startsWith('メモ')) {
      return null;
    }
    return candidate;
  }

  static (String, String)? matchTaskFieldLine(String line) {
    final normalizedLine = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    for (final entry in {
      'targetFiles': ['target files', 'files', '対象ファイル'],
      'validationCommand': [
        'validation command',
        'validation',
        'check',
        '確認コマンド',
        '確認方法',
      ],
      'notes': ['notes', 'memo', 'メモ'],
    }.entries) {
      for (final label in entry.value) {
        final match = RegExp(
          '^(?:[-*]\\s*)?${RegExp.escape(label)}\\s*[:：-]\\s*(.*)\$',
          caseSensitive: false,
        ).firstMatch(normalizedLine);
        if (match != null) {
          return (entry.key, match.group(1)?.trim() ?? '');
        }
      }
    }
    return null;
  }
}
