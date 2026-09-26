import 'dart:convert';

import 'roadmap_next_task_contract.dart';

/// One structured completion, as the extractor needs it.
typedef RoadmapCompletionPort =
    Future<RoadmapCompletion> Function({
      required String system,
      required String user,
      required String schemaName,
      required Map<String, dynamic> schema,
      required int maxTokens,
    });

final class RoadmapCompletion {
  const RoadmapCompletion({required this.content, this.finishReason});

  final String content;
  final String? finishReason;
}

/// An extracted item together with what the verifier made of it.
final class VerifiedRoadmapItem {
  const VerifiedRoadmapItem({required this.item, required this.verification});

  final ExtractedItem item;
  final ItemVerification verification;
}

enum RoadmapExtractionRoute { direct, outline }

/// The outcome of one extraction, including the trace the FARM0 instrument
/// records. Only [recommended], [current], and [blocked] are product data.
final class RoadmapExtraction {
  const RoadmapExtraction({
    required this.route,
    required this.recommended,
    required this.current,
    required this.blocked,
    required this.rawContent,
    this.finishReason,
    this.parseFailed = false,
    this.outlineChosen = const [],
    this.excerptChars,
  });

  final RoadmapExtractionRoute route;

  /// Every item the model returned, verified or not. A consumer that shows an
  /// item must check its verification.
  final List<VerifiedRoadmapItem> recommended;
  final List<VerifiedRoadmapItem> current;
  final List<VerifiedRoadmapItem> blocked;
  final String rawContent;
  final String? finishReason;
  final bool parseFailed;
  final List<({String heading, int line, int? resolvedLine})> outlineChosen;
  final int? excerptChars;

  /// A cut-off answer is an output-budget problem, not a judgment.
  bool get truncated => parseFailed && finishReason == 'length';

  Iterable<VerifiedRoadmapItem> get allItems => [
    ...recommended,
    ...current,
    ...blocked,
  ];

  int get droppedCount =>
      allItems.where((entry) => !entry.verification.kept).length;
}

/// Thrown when a document too large to read directly yields no section the
/// verifier can resolve, so there is nothing grounded to extract from.
final class RoadmapOutlineUnresolvedException implements Exception {
  const RoadmapOutlineUnresolvedException();

  @override
  String toString() => 'The outline stage chose no verifiable section.';
}

/// Runs the next-task extraction contract measured by FARM0 spike A.
///
/// See `docs/project_farm_roadmap.md`, "Next-Task Extraction Contract". A
/// document within [directBudgetChars] is sent whole; a larger one is read
/// outline-first, and only the sections whose headings resolve are extracted.
final class RoadmapNextTaskExtractor {
  const RoadmapNextTaskExtractor({
    required this.complete,
    this.directBudgetChars = defaultDirectBudgetChars,
  });

  /// About 25k tokens of English markdown: room for the prompt and the answer
  /// inside a 64k-token context, the size FARM0 measured on.
  static const int defaultDirectBudgetChars = 100000;

  static const int extractionMaxTokens = 4000;
  static const int outlineMaxTokens = 500;

  final RoadmapCompletionPort complete;
  final int directBudgetChars;

  Future<RoadmapExtraction> extract(String document) async {
    final lines = const LineSplitter().convert(document);
    final source = NormalizedSource(lines);
    final route = document.length <= directBudgetChars
        ? RoadmapExtractionRoute.direct
        : RoadmapExtractionRoute.outline;

    var outlineChosen =
        const <({String heading, int line, int? resolvedLine})>[];
    int? excerptChars;
    final String excerpt;
    if (route == RoadmapExtractionRoute.direct) {
      excerpt = numberLines(lines);
    } else {
      final outlined = await _outlineExcerpt(lines);
      outlineChosen = outlined.chosen;
      excerpt = outlined.excerpt;
      excerptChars = excerpt.length;
    }

    final completion = await complete(
      system: extractionSystemPrompt,
      user: 'Roadmap document:\n\n$excerpt',
      schemaName: 'caverno_roadmap_next_task',
      schema: extractionSchema,
      maxTokens: extractionMaxTokens,
    );
    final decoded = decodeJsonObject(completion.content);
    List<VerifiedRoadmapItem> verified(String key) => decoded == null
        ? const []
        : [
            for (final item in itemsOf(decoded, key))
              VerifiedRoadmapItem(
                item: item,
                verification: verifyItem(item, source),
              ),
          ];

    return RoadmapExtraction(
      route: route,
      recommended: verified('recommended'),
      current: verified('current'),
      blocked: verified('blocked'),
      rawContent: completion.content,
      finishReason: completion.finishReason,
      parseFailed: decoded == null,
      outlineChosen: outlineChosen,
      excerptChars: excerptChars,
    );
  }

  Future<
    ({
      String excerpt,
      List<({String heading, int line, int? resolvedLine})> chosen,
    })
  >
  _outlineExcerpt(List<String> lines) async {
    final outline = outlineOf(lines);
    final opening = numberLines(
      lines.take(roadmapOutlineOpeningLines).toList(),
    );
    final headings = outline
        .map(
          (heading) =>
              '${heading.line.toString().padLeft(5)}| '
              '${'#' * heading.level} ${heading.text}',
        )
        .join('\n');
    final completion = await complete(
      system: outlineSystemPrompt,
      user: 'Opening lines:\n$opening\nHeadings:\n$headings',
      schemaName: 'caverno_roadmap_sections',
      schema: outlineSchema,
      maxTokens: outlineMaxTokens,
    );
    final decoded = decodeJsonObject(completion.content);
    final chosen = <({String heading, int line, int? resolvedLine})>[];
    final ranges = <({int start, int end})>[];
    final requested = decoded?['sections'];
    if (requested is List) {
      for (final entry in requested) {
        if (entry is! Map) continue;
        final heading = entry['heading'] is String
            ? (entry['heading'] as String).trim()
            : '';
        final line = entry['line'] is num ? (entry['line'] as num).toInt() : 0;
        final resolved = resolveHeading(outline, heading, line);
        chosen.add((
          heading: heading,
          line: line,
          resolvedLine: resolved?.line,
        ));
        if (resolved != null) {
          ranges.add(sectionRange(outline, resolved, lines.length));
        }
      }
    }
    if (ranges.isEmpty) throw const RoadmapOutlineUnresolvedException();

    final buffer = StringBuffer();
    var used = 0;
    for (final range in mergeLineRanges(ranges)) {
      final remaining = directBudgetChars - used;
      if (remaining <= 0) break;
      final numbered = numberLines(
        lines.sublist(range.start - 1, range.end - 1),
        firstLine: range.start,
      );
      final clipped = numbered.length <= remaining
          ? numbered
          : numbered.substring(0, remaining);
      buffer
        ..writeln('[...]')
        ..write(clipped);
      used += clipped.length;
    }
    return (excerpt: buffer.toString(), chosen: chosen);
  }
}

/// Sorts and merges overlapping 1-based `[start, end)` line ranges.
List<({int start, int end})> mergeLineRanges(
  List<({int start, int end})> ranges,
) {
  final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  for (final range in sorted) {
    if (merged.isNotEmpty && range.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: range.end > last.end ? range.end : last.end,
      ));
    } else {
      merged.add(range);
    }
  }
  return merged;
}
