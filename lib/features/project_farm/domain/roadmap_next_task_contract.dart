/// The roadmap next-task extraction contract measured by FARM0 spike A.
///
/// See `docs/project_farm_roadmap.md`, "Next-Task Extraction Contract". The
/// prompt, schemas, verifier, and outline-first reader here are exactly what
/// `tool/farm0_next_task_extraction_spike.dart` measured, moved rather than
/// rewritten so the evidence still describes the shipped code.
///
/// Pure Dart: no Flutter import, so the measurement tool runs under
/// `dart run`.
library;

import 'dart:convert';

/// Bump when the prompt, schema, or verifier changes, so cached snapshots made
/// by an earlier contract are re-extracted.
const int roadmapExtractorVersion = 3;

// ---------------------------------------------------------------------------
// Extraction contract.

const Map<String, dynamic> _itemSchema = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'id': {'type': 'string'},
    'title': {'type': 'string'},
    'quote': {'type': 'string'},
    'line': {'type': 'integer'},
  },
  'required': ['id', 'title', 'quote', 'line'],
};

const Map<String, dynamic> extractionSchema = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'recommended': {'type': 'array', 'items': _itemSchema, 'maxItems': 1},
    'recommendation_basis': {
      'type': 'string',
      'enum': ['explicit', 'priority', 'none'],
    },
    'current': {'type': 'array', 'items': _itemSchema, 'maxItems': 8},
    'blocked': {'type': 'array', 'items': _itemSchema, 'maxItems': 8},
    'upcoming': {'type': 'array', 'items': _itemSchema, 'maxItems': 8},
  },
  'required': [
    'recommended',
    'recommendation_basis',
    'current',
    'blocked',
    'upcoming',
  ],
};

const Map<String, dynamic> outlineSchema = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'sections': {
      'type': 'array',
      'maxItems': 4,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'heading': {'type': 'string'},
          'line': {'type': 'integer'},
        },
        'required': ['heading', 'line'],
      },
    },
  },
  'required': ['sections'],
};

const String extractionSystemPrompt = '''
You read one project roadmap document and report where the project stands.
The document is shown with a line-number gutter such as "   42| ". The gutter
is not part of the document.

Report four lists:
- recommended: choose one unfinished item. First use the single next item the
  document explicitly recommends or selects. Otherwise, if the document ranks
  work by priority, choose an unfinished item in its highest-priority group.
  If that group singles out particular items as especially important, choose
  the first unfinished one of those in document order, even if other unfinished
  items appear earlier in the group. Phrases meaning "especially" in any
  language single out the named items. Otherwise choose the first
  unfinished item in the group. A phase containing multiple tasks is a
  group, not an item: choose one task within it. Do not choose a completed or
  blocked item. If no explicit next item or priority ranking supports a choice,
  leave this list empty.
- recommendation_basis: "explicit" for a named next item, "priority" for an
  item chosen from a priority group, or "none" when recommended is empty.
- current: items the document says are in progress now (at most 8).
- blocked: items the document says are blocked (at most 8).
- upcoming: up to eight other unfinished, unblocked, not-in-progress tasks in
  priority order, excluding recommended. A priority assigned to a phase applies
  to its unfinished tasks. Within each priority level, list specially singled
  out tasks first, then its other tasks in document order. Exhaust the higher
  priority level before listing anything from a lower level. Fill all eight
  slots from the highest level when it has at least eight eligible tasks after
  excluding recommended. Never include a medium-priority task while an
  eligible high-priority task was omitted. Include only tasks supported by a
  priority ranking; do not treat an entire phase as one task or infer that a
  listed task is already in progress. Example: if a priority table says "High:
  Phase 1 (especially A and B); Medium: C", rank A and B, then all other
  unfinished Phase 1 tasks, then C.

For every item give:
- id: the item's identifier exactly as written in the document, such as a
  milestone code. Use an empty string when it has none.
- title: a short title for the item.
- quote: the shortest span, at most 25 words, copied verbatim from the
  document that names the item and supports the classification, without the
  gutter. For a priority-based recommendation, quote the unfinished task's own
  entry rather than the priority summary. For a table row, copy only its
  leading cells. Do not paraphrase.
- line: the gutter number of the line where the quote starts.

Use only tasks and priorities present in the document. A priority-based choice
is a suggestion, not a claim that the document explicitly names the next task.''';

const String outlineSystemPrompt = '''
You are given the outline of a long project roadmap document: its opening
lines and every heading, each with its line number. Choose up to four sections
that most likely state an explicit next item, priority ranking and its
unfinished tasks, current work, or blockers. When there is no explicit next
item, include both the priority section and the section containing tasks in
its highest-priority group. Return each heading text exactly as shown, without
the leading # marks, and its line number.''';

/// Opening lines shown beside the heading outline in the outline stage.
const int roadmapOutlineOpeningLines = 60;

class ExtractedItem {
  const ExtractedItem({
    required this.id,
    required this.title,
    required this.quote,
    required this.line,
  });

  static ExtractedItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final line = json['line'];
    return ExtractedItem(
      id: _string(json['id']),
      title: _string(json['title']),
      quote: _string(json['quote']),
      line: line is num ? line.toInt() : int.tryParse('$line') ?? 0,
    );
  }

  final String id;
  final String title;
  final String quote;
  final int line;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'quote': quote,
    'line': line,
  };
}

List<ExtractedItem> itemsOf(Map<String, dynamic> decoded, String key) {
  final raw = decoded[key];
  if (raw is! List) return const [];
  return raw
      .map(ExtractedItem.fromJson)
      .whereType<ExtractedItem>()
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// Verification.

final RegExp _gutterPattern = RegExp(r'^\s*\d+\|\s?', multiLine: true);
final RegExp _emphasisPattern = RegExp('[*_`]');
final RegExp _whitespacePattern = RegExp(r'\s+');

/// Normalizes text so a quote copied from the gutter-numbered document matches
/// the source regardless of whitespace, gutter, or emphasis differences.
String normalizeForMatch(String text) => text
    .replaceAll(_gutterPattern, '')
    .replaceAll(_emphasisPattern, '')
    .replaceAll(_whitespacePattern, ' ')
    .trim();

/// The document joined into one normalized string, with a map back to lines.
class NormalizedSource {
  NormalizedSource(List<String> lines) {
    final buffer = StringBuffer();
    for (var index = 0; index < lines.length; index++) {
      final normalized = normalizeForMatch(lines[index]);
      if (normalized.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      _starts.add(buffer.length);
      _lineNumbers.add(index + 1);
      buffer.write(normalized);
    }
    text = buffer.toString();
  }

  late final String text;
  final List<int> _starts = [];
  final List<int> _lineNumbers = [];

  /// 1-based line on which the normalized [offset] falls.
  int lineForOffset(int offset) {
    var low = 0;
    var high = _starts.length - 1;
    var found = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_starts[mid] <= offset) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return _lineNumbers.isEmpty ? 0 : _lineNumbers[found];
  }

  /// 1-based lines where [normalizedQuote] starts, in document order.
  List<int> occurrenceLines(String normalizedQuote) {
    if (normalizedQuote.isEmpty) return const [];
    final lines = <int>[];
    var from = 0;
    while (true) {
      final index = text.indexOf(normalizedQuote, from);
      if (index < 0) break;
      lines.add(lineForOffset(index));
      from = index + 1;
    }
    return lines;
  }
}

enum QuoteVerdict { verified, emptyQuote, quoteNotFound, idNotInQuote }

class ItemVerification {
  const ItemVerification({
    required this.verdict,
    this.sourceLine,
    this.lineError,
  });

  final QuoteVerdict verdict;
  final int? sourceLine;
  final int? lineError;

  bool get kept => verdict == QuoteVerdict.verified;

  Map<String, dynamic> toJson() => {
    'verdict': verdict.name,
    'sourceLine': sourceLine,
    'lineError': lineError,
  };
}

ItemVerification verifyItem(ExtractedItem item, NormalizedSource source) {
  final quote = normalizeForMatch(item.quote);
  if (quote.isEmpty) {
    return const ItemVerification(verdict: QuoteVerdict.emptyQuote);
  }
  final occurrences = source.occurrenceLines(quote);
  if (occurrences.isEmpty) {
    return const ItemVerification(verdict: QuoteVerdict.quoteNotFound);
  }
  final id = normalizeForMatch(item.id).toLowerCase();
  if (id.isNotEmpty && !quote.toLowerCase().contains(id)) {
    return const ItemVerification(verdict: QuoteVerdict.idNotInQuote);
  }
  var nearest = occurrences.first;
  for (final line in occurrences) {
    if ((line - item.line).abs() < (nearest - item.line).abs()) nearest = line;
  }
  return ItemVerification(
    verdict: QuoteVerdict.verified,
    sourceLine: nearest,
    lineError: (nearest - item.line).abs(),
  );
}

// ---------------------------------------------------------------------------
// Outline-first reading for documents over the direct budget.

class OutlineHeading {
  const OutlineHeading({
    required this.line,
    required this.level,
    required this.text,
  });

  final int line;
  final int level;
  final String text;
}

final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$');

List<OutlineHeading> outlineOf(List<String> lines) {
  final headings = <OutlineHeading>[];
  var inFence = false;
  for (var index = 0; index < lines.length; index++) {
    final trimmed = lines[index].trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final match = _headingPattern.firstMatch(lines[index]);
    if (match == null) continue;
    headings.add(
      OutlineHeading(
        line: index + 1,
        level: match.group(1)!.length,
        text: match.group(2)!.trim(),
      ),
    );
  }
  return headings;
}

/// 1-based `[start, end)` line range of [heading]'s section.
({int start, int end}) sectionRange(
  List<OutlineHeading> outline,
  OutlineHeading heading,
  int lineCount,
) {
  for (final candidate in outline) {
    if (candidate.line > heading.line && candidate.level <= heading.level) {
      return (start: heading.line, end: candidate.line);
    }
  }
  return (start: heading.line, end: lineCount + 1);
}

/// Finds the outline heading the model named: exact text, nearest to the line
/// it reported. Returns null when no heading carries that text.
OutlineHeading? resolveHeading(
  List<OutlineHeading> outline,
  String heading,
  int reportedLine,
) {
  final wanted = normalizeForMatch(heading.replaceFirst(RegExp('^#+'), ''));
  OutlineHeading? best;
  for (final candidate in outline) {
    if (normalizeForMatch(candidate.text) != wanted) continue;
    if (best == null ||
        (candidate.line - reportedLine).abs() <
            (best.line - reportedLine).abs()) {
      best = candidate;
    }
  }
  return best;
}

String numberLines(List<String> lines, {int firstLine = 1}) {
  final buffer = StringBuffer();
  for (var index = 0; index < lines.length; index++) {
    buffer.writeln(
      '${(firstLine + index).toString().padLeft(5)}| ${lines[index]}',
    );
  }
  return buffer.toString();
}

/// Decodes a JSON object from a model answer, tolerating a reasoning block and
/// a code fence around it.
Map<String, dynamic>? decodeJsonObject(String content) {
  var text = content.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String _string(Object? value) => value is String ? value.trim() : '';
