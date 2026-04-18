import '../entities/message.dart';
import '../entities/session_memory.dart';
import 'memory_extraction_json_parser.dart';
import 'session_memory_service.dart';

class MemoryExtractionDraftService {
  MemoryExtractionDraftService._();

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

  static String buildInput(
    List<Message> messages,
    UserMemoryProfile profile,
  ) {
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
      final content = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
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
      return null;
    }

    try {
      final map = parseResult.decoded;
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

      final draft = MemoryExtractionDraft(
        summary: summary,
        openLoops: openLoops,
        persona: persona,
        preferences: preferences,
        doNot: doNot,
        entries: entries,
      );
      if (parseResult.wasRepaired) {
        onRepair?.call('Repaired malformed memory extraction JSON');
      }
      return draft.isEmpty ? null : draft;
    } catch (error) {
      onError?.call(error);
      return null;
    }
  }

  static List<String> _stringList(Object? raw, {required int maxLength}) {
    if (raw is! List) {
      return const [];
    }
    final values = raw
        .whereType<String>()
        .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.length <= maxLength) {
      return values;
    }
    return values.sublist(0, maxLength);
  }
}
