import '../entities/message.dart';
import '../entities/session_memory.dart';
import 'memory_extraction_json_parser.dart';
import 'session_memory_service.dart';

class MemoryExtractionDraftService {
  MemoryExtractionDraftService._();

  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _leadingReasoningBullet = RegExp(
    r'^\s*(?:[*\-]\s*)?(?:\d+\.\s*)?',
  );
  static final RegExp _quotedListItemPattern = RegExp(r'"([^"]+)"');
  static final RegExp _memoryTextPattern = RegExp(
    r'\btext\s*:\s*"([^"]+)"',
    caseSensitive: false,
  );
  static final RegExp _memoryTypePattern = RegExp(
    r'\btype\s*:\s*"?(preference|persona|topic|constraint|fact)"?',
    caseSensitive: false,
  );
  static final RegExp _confidencePattern = RegExp(
    r'\bconfidence\s*:\s*([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  );
  static final RegExp _importancePattern = RegExp(
    r'\bimportance\s*:\s*([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  );
  static final RegExp _ttlPattern = RegExp(
    r'\bttl(?:_days)?\s*:\s*(null|[0-9]+)',
    caseSensitive: false,
  );

  static const systemPrompt =
      'You extract reusable user memory from a conversation. '
      'Output only a single valid JSON object with no markdown. '
      'Schema: {"summary":string,"open_loops":[string],'
      '"profile":{"persona":[string],"preferences":[string],"do_not":[string]},'
      '"memories":[{"text":string,"type":"preference|persona|topic|constraint|fact",'
      '"confidence":number,"importance":number,"ttl_days":number|null}]}. '
      'Focus on stable user traits/preferences/constraints. '
      'Also extract specific facts the user mentioned: prices, quantities, '
      'purchases, dates, decisions, events, and other concrete data points. '
      'Use type "fact" with high importance for these. '
      'Facts should have detailed text (up to 300 chars) to preserve specifics. '
      'Do not include temporary assistant instructions.';

  static String buildInput(List<Message> messages, UserMemoryProfile profile) {
    final buffer = StringBuffer()
      ..writeln('Current profile:')
      ..writeln('- persona: ${profile.persona.join(' | ')}')
      ..writeln('- preferences: ${profile.preferences.join(' | ')}')
      ..writeln('- do_not: ${profile.doNot.join(' | ')}')
      ..writeln()
      ..writeln('Conversation log:');

    final tail = messages.length > 12
        ? messages.sublist(messages.length - 12)
        : messages;
    for (final message in tail) {
      if (message.content.trim().isEmpty) {
        continue;
      }
      final role = message.role.name;
      final content = message.content.replaceAll(_whitespaceRun, ' ').trim();
      final clipped = content.length > 360
          ? '${content.substring(0, 360)}...'
          : content;
      buffer.writeln('- $role: $clipped');
    }

    buffer
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- summary must be 160 characters or fewer')
      ..writeln('- open_loops max 3 items')
      ..writeln('- memories max 8 items')
      ..writeln('- confidence/importance range: 0.0 to 1.0')
      ..writeln('- Set confidence low for uncertain items');

    return buffer.toString();
  }

  static MemoryExtractionDraft? parseDraft(
    String rawContent, {
    void Function(String message)? onRepair,
    void Function(Object error)? onError,
  }) {
    final parseResult = MemoryExtractionJsonParser.parse(rawContent);
    if (parseResult == null) {
      final draft = _parseStructuredReasoningDraft(rawContent);
      if (draft != null) {
        onRepair?.call(
          'Recovered memory extraction from structured reasoning text',
        );
      }
      return draft;
    }

    try {
      final draft = _draftFromMap(parseResult.decoded);
      if (parseResult.wasRepaired) {
        onRepair?.call('Repaired malformed memory extraction JSON');
      }
      if (!draft.isEmpty) {
        return draft;
      }
      final structuredDraft = _parseStructuredReasoningDraft(rawContent);
      if (structuredDraft != null) {
        onRepair?.call(
          'Recovered memory extraction from structured reasoning text',
        );
      }
      return structuredDraft;
    } catch (error) {
      onError?.call(error);
      final draft = _parseStructuredReasoningDraft(rawContent);
      if (draft != null) {
        onRepair?.call(
          'Recovered memory extraction from structured reasoning text',
        );
      }
      return draft;
    }
  }

  static MemoryExtractionDraft _draftFromMap(Map<String, dynamic> map) {
    final summary = (map['summary'] as String?)?.trim() ?? '';
    final openLoops = _stringList(map['open_loops'], maxLength: 3);

    final profile = map['profile'];
    List<String> persona = const [];
    List<String> preferences = const [];
    List<String> doNot = const [];
    if (profile is Map) {
      final profileMap = Map<String, dynamic>.from(profile);
      persona = _stringList(profileMap['persona'], maxLength: 12);
      preferences = _stringList(profileMap['preferences'], maxLength: 16);
      doNot = _stringList(profileMap['do_not'], maxLength: 16);
    }

    final entries = <MemoryDraftEntry>[];
    final memoriesRaw = map['memories'];
    if (memoriesRaw is List) {
      for (final raw in memoriesRaw.take(8)) {
        if (raw is! Map) {
          continue;
        }
        final item = Map<String, dynamic>.from(raw);
        final text = (item['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) {
          continue;
        }
        final type = (item['type'] as String?)?.trim() ?? 'topic';
        final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.6;
        final importance = (item['importance'] as num?)?.toDouble() ?? 0.6;
        final ttlDays = (item['ttl_days'] as num?)?.toInt();
        entries.add(
          MemoryDraftEntry(
            text: text,
            type: type,
            confidence: confidence,
            importance: importance,
            ttlDays: ttlDays,
          ),
        );
      }
    }

    return MemoryExtractionDraft(
      summary: summary,
      openLoops: openLoops,
      persona: persona,
      preferences: preferences,
      doNot: doNot,
      entries: entries,
    );
  }

  static MemoryExtractionDraft? _parseStructuredReasoningDraft(
    String rawContent,
  ) {
    final summary = _extractStructuredSummary(rawContent);
    final openLoops = _extractStructuredList(
      rawContent,
      labels: const ['open loops', 'open_loops'],
      maxLength: 3,
    );
    final persona = _extractStructuredList(
      rawContent,
      labels: const ['persona'],
      maxLength: 12,
    );
    final preferences = _extractStructuredList(
      rawContent,
      labels: const ['preferences'],
      maxLength: 16,
    );
    final doNot = _extractStructuredList(
      rawContent,
      labels: const ['do not', 'do_not'],
      maxLength: 16,
    );
    final entries = _extractStructuredEntries(rawContent);

    final draft = MemoryExtractionDraft(
      summary: summary,
      openLoops: openLoops,
      persona: persona,
      preferences: preferences,
      doNot: doNot,
      entries: entries,
    );
    return draft.isEmpty ? null : draft;
  }

  static String _extractStructuredSummary(String rawContent) {
    for (final line in rawContent.split(RegExp(r'\r?\n'))) {
      final normalizedLine = _normalizeStructuredLine(line);
      final separator = normalizedLine.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final label = _normalizeStructuredLabel(
        normalizedLine.substring(0, separator),
      );
      if (label != 'summary') {
        continue;
      }
      return _cleanStructuredValue(normalizedLine.substring(separator + 1));
    }
    return '';
  }

  static List<String> _extractStructuredList(
    String rawContent, {
    required List<String> labels,
    required int maxLength,
  }) {
    final normalizedLabels = labels.map(_normalizeStructuredLabel).toSet();
    for (final line in rawContent.split(RegExp(r'\r?\n'))) {
      final normalizedLine = _normalizeStructuredLine(line);
      final separator = normalizedLine.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final label = _normalizeStructuredLabel(
        normalizedLine.substring(0, separator),
      );
      if (!normalizedLabels.contains(label)) {
        continue;
      }
      final value = normalizedLine.substring(separator + 1).trim();
      final lowerValue = value.toLowerCase();
      if (lowerValue == 'none' || lowerValue == 'none.' || lowerValue == '[]') {
        return const [];
      }
      final quotedItems = _quotedListItemPattern
          .allMatches(value)
          .map((match) => _cleanStructuredValue(match.group(1) ?? ''))
          .where((item) => item.isNotEmpty)
          .take(maxLength)
          .toList(growable: false);
      if (quotedItems.isNotEmpty) {
        return quotedItems;
      }
      return value
          .split(RegExp(r'\s*(?:,|\|)\s*'))
          .map(_cleanStructuredValue)
          .where((item) => item.isNotEmpty)
          .take(maxLength)
          .toList(growable: false);
    }
    return const [];
  }

  static List<MemoryDraftEntry> _extractStructuredEntries(String rawContent) {
    final entries = <MemoryDraftEntry>[];
    final seenTexts = <String>{};
    for (final line in rawContent.split(RegExp(r'\r?\n'))) {
      final normalizedLine = _normalizeStructuredLine(line);
      final textMatch = _memoryTextPattern.firstMatch(normalizedLine);
      final text = _cleanStructuredValue(textMatch?.group(1) ?? '');
      if (text.isEmpty || !seenTexts.add(text.toLowerCase())) {
        continue;
      }
      final type = _memoryTypePattern.firstMatch(normalizedLine)?.group(1);
      final confidence = _doubleFromMatch(
        _confidencePattern.firstMatch(normalizedLine),
      );
      final importance = _doubleFromMatch(
        _importancePattern.firstMatch(normalizedLine),
      );
      entries.add(
        MemoryDraftEntry(
          text: text,
          type: type?.toLowerCase() ?? 'topic',
          confidence: confidence ?? 0.6,
          importance: importance ?? 0.6,
          ttlDays: _ttlFromLine(normalizedLine),
        ),
      );
      if (entries.length >= 8) {
        break;
      }
    }
    return entries;
  }

  static String _normalizeStructuredLine(String line) {
    return line
        .replaceFirst(_leadingReasoningBullet, '')
        .replaceAll('`', '')
        .trim();
  }

  static String _normalizeStructuredLabel(String label) {
    return label
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(_whitespaceRun, ' ')
        .trim()
        .toLowerCase();
  }

  static String _cleanStructuredValue(String value) {
    var cleaned = value.replaceAll(_whitespaceRun, ' ').trim();
    while (cleaned.startsWith('"') || cleaned.startsWith("'")) {
      cleaned = cleaned.substring(1).trimLeft();
    }
    while (cleaned.endsWith('"') ||
        cleaned.endsWith("'") ||
        cleaned.endsWith('.')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trimRight();
    }
    return cleaned;
  }

  static double? _doubleFromMatch(RegExpMatch? match) {
    final value = match?.group(1);
    if (value == null) {
      return null;
    }
    return double.tryParse(value)?.clamp(0.0, 1.0).toDouble();
  }

  static int? _ttlFromLine(String line) {
    final value = _ttlPattern.firstMatch(line)?.group(1);
    if (value == null || value.toLowerCase() == 'null') {
      return null;
    }
    return int.tryParse(value);
  }

  static List<String> _stringList(Object? raw, {required int maxLength}) {
    if (raw is! List) {
      return const [];
    }
    final values = raw
        .whereType<String>()
        .map((value) => value.replaceAll(_whitespaceRun, ' ').trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.length <= maxLength) {
      return values;
    }
    return values.sublist(0, maxLength);
  }
}
