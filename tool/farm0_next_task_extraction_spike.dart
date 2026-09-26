import 'dart:convert';
import 'dart:io';

/// FARM0 spike A: next-task extraction accuracy.
///
/// Design: `docs/project_farm_roadmap.md`, FARM0 and the "Next-Task Extraction
/// Contract". The question is whether a local model can read a project's own
/// roadmap and name the item the document says comes next, reliably enough for
/// a dashboard to show `Next task: <id>` with a citation.
///
/// Three properties it holds deliberately.
///
/// **Scoring never reads the model's prose.** The verdict compares the
/// extracted id with a hand label recorded in the fixture manifest before the
/// run.
///
/// **Citations come from the source, not the model.** Every extracted item
/// must carry a quote that the verifier finds in the document once whitespace,
/// the line-number gutter, and markdown emphasis are normalized away. The
/// recorded line is where the verifier found the quote. An item whose quote is
/// not in the document is dropped and counted, never shown.
///
/// **No pattern decides what "next" means.** The model interprets and the
/// verifier checks. A document too large for the direct budget is read
/// outline-first: the model picks sections from the heading outline, the
/// verifier confirms that the headings exist, and only those sections are
/// extracted.
///
/// Usage:
///
/// ```bash
/// fvm dart run tool/farm0_next_task_extraction_spike.dart \
///   [--endpoint http://192.168.100.241:1234] [--model qwen3.8-27b-exl3] \
///   [--only name,name] [--direct-budget-chars 100000] [--out DIR]
/// ```
Future<void> main(List<String> args) async {
  final options = SpikeOptions.parse(args);
  final manifest =
      jsonDecode(File(options.manifestPath).readAsStringSync())
          as Map<String, dynamic>;
  final fixtures = (manifest['fixtures'] as List)
      .map((entry) => FixtureSpec.fromJson(entry as Map<String, dynamic>))
      .where(
        (fixture) =>
            options.only.isEmpty || options.only.contains(fixture.name),
      )
      .toList(growable: false);

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final records = <Map<String, dynamic>>[];
  final outDir = Directory(options.outDir)..createSync(recursive: true);
  // Written per fixture so an interrupted run still leaves its evidence.
  final partial = File('${outDir.path}/records.jsonl')..writeAsStringSync('');
  try {
    for (final fixture in fixtures) {
      final record = await runFixture(
        client: client,
        options: options,
        fixture: fixture,
      );
      records.add(record);
      partial.writeAsStringSync(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
      );
      stdout.writeln(_consoleLine(record));
    }
  } finally {
    client.close(force: true);
  }

  final summary = summarize(records);
  final report = <String, dynamic>{
    'schema': 'farm0_spike_a_report_v1',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'endpoint': options.endpoint,
    'model': options.model,
    'directBudgetChars': options.directBudgetChars,
    'repository': await _repositoryProvenance(),
    'thresholds': spikeThresholds,
    'summary': summary,
    'fixtures': records,
  };
  File(
    '${outDir.path}/report.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  File('${outDir.path}/report.md').writeAsStringSync(renderMarkdown(report));
  stdout
    ..writeln('')
    ..writeln(
      'historical scored: ${summary['historicalCorrect']}/'
      '${summary['historicalScored']} '
      '(threshold ${spikeThresholds['historicalMinimumCorrect']}) -> '
      '${summary['historicalPass'] ? 'PASS' : 'MISS'}',
    )
    ..writeln(
      'synthetic: ${summary['syntheticCorrect']}/'
      '${summary['syntheticScored']} -> '
      '${summary['syntheticPass'] ? 'PASS' : 'MISS'}',
    )
    ..writeln(
      'quotes dropped: ${summary['droppedItems']}/${summary['totalItems']}',
    )
    ..writeln('report: ${outDir.path}/report.json');
  if (records.any((record) => record['error'] != null)) exitCode = 1;
}

const String defaultEndpoint = 'http://192.168.100.241:1234';
const String defaultModel = 'qwen3.8-27b-exl3';
const String defaultManifestPath =
    'tool/fixtures/farm0_next_task/manifest.json';

/// About 25k tokens of English markdown: leaves room for the prompt and the
/// answer inside the 64k-token context `qwen3.8-27b-exl3` is served with.
const int defaultDirectBudgetChars = 100000;

/// Fixed in `docs/project_farm_roadmap.md` before the first run.
const Map<String, int> spikeThresholds = {
  'historicalMinimumCorrect': 6,
  'historicalScored': 7,
  'syntheticMinimumCorrect': 3,
  'syntheticScored': 3,
};

class SpikeOptions {
  const SpikeOptions({
    required this.endpoint,
    required this.model,
    required this.manifestPath,
    required this.outDir,
    required this.directBudgetChars,
    required this.only,
    required this.requestTimeout,
  });

  factory SpikeOptions.parse(List<String> args) {
    String? valueOf(String flag) {
      final index = args.indexOf(flag);
      return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
    }

    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    return SpikeOptions(
      endpoint: (valueOf('--endpoint') ?? defaultEndpoint).replaceAll(
        RegExp(r'/+$'),
        '',
      ),
      model: valueOf('--model') ?? defaultModel,
      manifestPath: valueOf('--manifest') ?? defaultManifestPath,
      outDir:
          valueOf('--out') ??
          'build/integration_test_reports/farm0_spike_a/$stamp',
      directBudgetChars:
          int.tryParse(valueOf('--direct-budget-chars') ?? '') ??
          defaultDirectBudgetChars,
      only: (valueOf('--only') ?? '')
          .split(',')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet(),
      requestTimeout: Duration(
        seconds: int.tryParse(valueOf('--timeout-seconds') ?? '') ?? 600,
      ),
    );
  }

  final String endpoint;
  final String model;
  final String manifestPath;
  final String outDir;
  final int directBudgetChars;
  final Set<String> only;
  final Duration requestTimeout;
}

class FixtureSpec {
  const FixtureSpec({
    required this.name,
    required this.kind,
    required this.expectedRecommendedId,
    required this.scored,
    this.gitCommit,
    this.path,
    this.file,
  });

  factory FixtureSpec.fromJson(Map<String, dynamic> json) => FixtureSpec(
    name: json['name'] as String,
    kind: json['kind'] as String,
    expectedRecommendedId: json['expectedRecommendedId'] as String?,
    scored: json['scored'] as bool,
    gitCommit: json['gitCommit'] as String?,
    path: json['path'] as String?,
    file: json['file'] as String?,
  );

  final String name;
  final String kind;
  final String? expectedRecommendedId;
  final bool scored;
  final String? gitCommit;
  final String? path;
  final String? file;

  bool get isSynthetic => kind == 'synthetic';

  Future<String> load() async {
    final localFile = file;
    if (localFile != null) return File(localFile).readAsString();
    final result = await Process.run('git', ['show', '$gitCommit:$path']);
    if (result.exitCode != 0) {
      throw StateError('git show $gitCommit:$path failed: ${result.stderr}');
    }
    return result.stdout as String;
  }
}

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
    'current': {'type': 'array', 'items': _itemSchema, 'maxItems': 8},
    'blocked': {'type': 'array', 'items': _itemSchema, 'maxItems': 8},
  },
  'required': ['recommended', 'current', 'blocked'],
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

Report three lists:
- recommended: the single item the document itself says should be worked on
  next. Include it only when the document explicitly recommends, selects, or
  prioritizes one next item. When the document only lists items and their
  statuses, leave this list empty.
- current: items the document says are in progress now (at most 8).
- blocked: items the document says are blocked (at most 8).

For every item give:
- id: the item's identifier exactly as written in the document, such as a
  milestone code. Use an empty string when it has none.
- title: a short title for the item.
- quote: the shortest span, at most 25 words, copied verbatim from the
  document that names the item and supports the classification, without the
  gutter. For a table row, copy only its leading cells. Do not paraphrase.
- line: the gutter number of the line where the quote starts.

Report only what the document states. Do not infer a next step it does not
state.''';

const String outlineSystemPrompt = '''
You are given the outline of a long project roadmap document: its opening
lines and every heading, each with its line number. Choose up to four sections
that most likely state what the project is working on now, what is blocked,
and what should be done next. Return each section's heading text exactly as
shown, without the leading # marks, and its line number.''';

const int _outlineOpeningLines = 60;

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
// Verification. Pure: exercised by
// `test/tool/farm0_next_task_extraction_spike_test.dart`.

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

/// The leading identifier token of an extracted id, upper-cased, so that
/// `ANA3 PR 2b` scores as `ANA3` and `PT-12` stays whole.
String? leadingIdToken(String id) =>
    RegExp('[A-Za-z0-9][A-Za-z0-9-]*').firstMatch(id)?.group(0)?.toUpperCase();

/// Scores a fixture. A null [expectedId] requires the model to abstain
/// entirely: an unverified recommendation would still reach the screen as an
/// "unverified" badge.
bool recommendationCorrect({
  required String? expectedId,
  required ExtractedItem? modelRecommended,
  required bool recommendedVerified,
}) {
  if (expectedId == null) return modelRecommended == null;
  if (modelRecommended == null || !recommendedVerified) return false;
  return leadingIdToken(modelRecommended.id) == expectedId.toUpperCase();
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

// ---------------------------------------------------------------------------
// Model calls.

class CompletionResult {
  const CompletionResult({
    required this.content,
    required this.latency,
    required this.promptChars,
    required this.finishReason,
  });

  final String content;
  final Duration latency;
  final int promptChars;
  final String? finishReason;
}

Future<CompletionResult> completeStructured({
  required HttpClient client,
  required SpikeOptions options,
  required String system,
  required String user,
  required String schemaName,
  required Map<String, dynamic> schema,
  required int maxTokens,
}) async {
  // llama.cpp-style routers reject chunked bodies, so the length is set.
  final payload = utf8.encode(
    jsonEncode({
      'model': options.model,
      'temperature': 0,
      'max_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'response_format': {
        'type': 'json_schema',
        'json_schema': {'name': schemaName, 'strict': true, 'schema': schema},
      },
    }),
  );
  final stopwatch = Stopwatch()..start();
  final request = await client.postUrl(
    Uri.parse('${options.endpoint}/v1/chat/completions'),
  );
  request.headers.contentType = ContentType.json;
  request.contentLength = payload.length;
  request.add(payload);
  final response = await request.close().timeout(options.requestTimeout);
  final body = await response
      .transform(utf8.decoder)
      .join()
      .timeout(options.requestTimeout);
  stopwatch.stop();
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}: ${_clip(body, 400)}');
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final choice = (decoded['choices'] as List).first as Map<String, dynamic>;
  final message = choice['message'] as Map<String, dynamic>;
  return CompletionResult(
    content: (message['content'] as String?) ?? '',
    latency: stopwatch.elapsed,
    promptChars: system.length + user.length,
    finishReason: choice['finish_reason'] as String?,
  );
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

// ---------------------------------------------------------------------------
// One fixture.

Future<Map<String, dynamic>> runFixture({
  required HttpClient client,
  required SpikeOptions options,
  required FixtureSpec fixture,
}) async {
  final record = <String, dynamic>{
    'name': fixture.name,
    'kind': fixture.kind,
    'scored': fixture.scored,
    'expectedRecommendedId': fixture.expectedRecommendedId,
  };
  try {
    final text = await fixture.load();
    final lines = const LineSplitter().convert(text);
    final source = NormalizedSource(lines);
    record['documentChars'] = text.length;
    record['documentLines'] = lines.length;

    final String excerpt;
    if (text.length <= options.directBudgetChars) {
      record['route'] = 'direct';
      excerpt = numberLines(lines);
    } else {
      record['route'] = 'outline';
      excerpt = await _outlineExcerpt(
        client: client,
        options: options,
        lines: lines,
        record: record,
      );
    }

    final result = await completeStructured(
      client: client,
      options: options,
      system: extractionSystemPrompt,
      user: 'Roadmap document:\n\n$excerpt',
      schemaName: 'caverno_roadmap_next_task',
      schema: extractionSchema,
      maxTokens: 4000,
    );
    record['extraction'] = {
      'latencyMs': result.latency.inMilliseconds,
      'promptChars': result.promptChars,
      'finishReason': result.finishReason,
      'rawContent': _clip(result.content, 6000),
    };
    final decoded = decodeJsonObject(result.content);
    if (decoded == null) {
      record['parseFailed'] = true;
      // A cut-off answer is an instrument budget problem, not a judgment.
      record['truncated'] = result.finishReason == 'length';
      record['correct'] = false;
      return record;
    }

    var totalItems = 0;
    var droppedItems = 0;
    final verified = <String, List<Map<String, dynamic>>>{};
    for (final key in const ['recommended', 'current', 'blocked']) {
      verified[key] = [
        for (final item in itemsOf(decoded, key))
          () {
            final verification = verifyItem(item, source);
            totalItems++;
            if (!verification.kept) droppedItems++;
            return {...item.toJson(), 'verification': verification.toJson()};
          }(),
      ];
    }
    record['items'] = verified;
    record['totalItems'] = totalItems;
    record['droppedItems'] = droppedItems;

    final recommended = itemsOf(decoded, 'recommended').firstOrNull;
    final recommendedVerified =
        recommended != null && verifyItem(recommended, source).kept;
    record['recommendedId'] = recommended?.id;
    record['recommendedVerified'] = recommendedVerified;
    record['correct'] = recommendationCorrect(
      expectedId: fixture.expectedRecommendedId,
      modelRecommended: recommended,
      recommendedVerified: recommendedVerified,
    );
  } on Object catch (error) {
    record['error'] = '$error';
    record['correct'] = false;
  }
  return record;
}

Future<String> _outlineExcerpt({
  required HttpClient client,
  required SpikeOptions options,
  required List<String> lines,
  required Map<String, dynamic> record,
}) async {
  final outline = outlineOf(lines);
  final opening = numberLines(lines.take(_outlineOpeningLines).toList());
  final headings = outline
      .map(
        (heading) =>
            '${heading.line.toString().padLeft(5)}| '
            '${'#' * heading.level} ${heading.text}',
      )
      .join('\n');
  final result = await completeStructured(
    client: client,
    options: options,
    system: outlineSystemPrompt,
    user: 'Opening lines:\n$opening\nHeadings:\n$headings',
    schemaName: 'caverno_roadmap_sections',
    schema: outlineSchema,
    maxTokens: 500,
  );
  final decoded = decodeJsonObject(result.content);
  final chosen = <Map<String, dynamic>>[];
  final ranges = <({int start, int end})>[];
  final requested = decoded?['sections'];
  if (requested is List) {
    for (final entry in requested) {
      if (entry is! Map) continue;
      final heading = _string(entry['heading']);
      final line = entry['line'] is num ? (entry['line'] as num).toInt() : 0;
      final resolved = resolveHeading(outline, heading, line);
      chosen.add({
        'heading': heading,
        'line': line,
        'resolvedLine': resolved?.line,
      });
      if (resolved != null) {
        ranges.add(sectionRange(outline, resolved, lines.length));
      }
    }
  }
  record['outline'] = {
    'headings': outline.length,
    'latencyMs': result.latency.inMilliseconds,
    'promptChars': result.promptChars,
    'chosen': chosen,
  };
  if (ranges.isEmpty) {
    throw StateError('The outline stage chose no verifiable section.');
  }

  final buffer = StringBuffer();
  var used = 0;
  for (final range in _mergedRanges(ranges)) {
    final section = lines.sublist(range.start - 1, range.end - 1);
    final numbered = numberLines(section, firstLine: range.start);
    final remaining = options.directBudgetChars - used;
    if (remaining <= 0) break;
    final clipped = numbered.length <= remaining
        ? numbered
        : numbered.substring(0, remaining);
    buffer
      ..writeln('[...]')
      ..write(clipped);
    used += clipped.length;
  }
  record['excerptChars'] = buffer.length;
  return buffer.toString();
}

List<({int start, int end})> _mergedRanges(
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

// ---------------------------------------------------------------------------
// Report.

Map<String, dynamic> summarize(List<Map<String, dynamic>> records) {
  var historicalScored = 0;
  var historicalCorrect = 0;
  var syntheticScored = 0;
  var syntheticCorrect = 0;
  var totalItems = 0;
  var droppedItems = 0;
  for (final record in records) {
    totalItems += (record['totalItems'] as int?) ?? 0;
    droppedItems += (record['droppedItems'] as int?) ?? 0;
    if (record['scored'] != true) continue;
    final correct = record['correct'] == true;
    if (record['kind'] == 'synthetic') {
      syntheticScored++;
      if (correct) syntheticCorrect++;
    } else {
      historicalScored++;
      if (correct) historicalCorrect++;
    }
  }
  return {
    'historicalScored': historicalScored,
    'historicalCorrect': historicalCorrect,
    'historicalPass':
        historicalScored == spikeThresholds['historicalScored'] &&
        historicalCorrect >= spikeThresholds['historicalMinimumCorrect']!,
    'syntheticScored': syntheticScored,
    'syntheticCorrect': syntheticCorrect,
    'syntheticPass':
        syntheticScored == spikeThresholds['syntheticScored'] &&
        syntheticCorrect >= spikeThresholds['syntheticMinimumCorrect']!,
    'totalItems': totalItems,
    'droppedItems': droppedItems,
  };
}

String renderMarkdown(Map<String, dynamic> report) {
  final summary = report['summary'] as Map<String, dynamic>;
  final buffer = StringBuffer()
    ..writeln('# FARM0 spike A report')
    ..writeln()
    ..writeln('- Model: `${report['model']}` at `${report['endpoint']}`')
    ..writeln('- Generated: ${report['generatedAt']}')
    ..writeln('- Repository: ${jsonEncode(report['repository'])}')
    ..writeln(
      '- Historical: ${summary['historicalCorrect']}/'
      '${summary['historicalScored']} '
      '(${summary['historicalPass'] ? 'PASS' : 'MISS'})',
    )
    ..writeln(
      '- Synthetic: ${summary['syntheticCorrect']}/'
      '${summary['syntheticScored']} '
      '(${summary['syntheticPass'] ? 'PASS' : 'MISS'})',
    )
    ..writeln(
      '- Quotes dropped by the verifier: ${summary['droppedItems']}/'
      '${summary['totalItems']}',
    )
    ..writeln()
    ..writeln(
      '| Fixture | Route | Chars | Expected | Extracted | Verified | Correct '
      '| Dropped | Seconds |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|');
  for (final record
      in (report['fixtures'] as List).cast<Map<String, dynamic>>()) {
    final extraction = record['extraction'] as Map<String, dynamic>?;
    final outline = record['outline'] as Map<String, dynamic>?;
    final latencyMs =
        ((extraction?['latencyMs'] as int?) ?? 0) +
        ((outline?['latencyMs'] as int?) ?? 0);
    buffer.writeln(
      '| ${record['name']} | ${record['route'] ?? '-'} '
      '| ${record['documentChars'] ?? '-'} '
      '| ${record['expectedRecommendedId'] ?? '(none)'} '
      '| ${record['recommendedId'] ?? '(none)'} '
      '| ${record['recommendedVerified'] ?? '-'} '
      '| ${record['scored'] == true ? record['correct'] : 'unscored'} '
      '| ${record['droppedItems'] ?? '-'}/${record['totalItems'] ?? '-'} '
      '| ${(latencyMs / 1000).toStringAsFixed(1)} |',
    );
    if (record['error'] != null) {
      buffer.writeln('|  | error: ${record['error']} |||||||| ');
    }
  }
  return buffer.toString();
}

String _consoleLine(Map<String, dynamic> record) {
  final verdict = record['scored'] == true
      ? (record['correct'] == true ? 'OK  ' : 'MISS')
      : 'N/A ';
  final error = record['error'] == null ? '' : ' error=${record['error']}';
  return '$verdict ${record['name']} route=${record['route']} '
      'expected=${record['expectedRecommendedId']} '
      'got=${record['recommendedId']} '
      'verified=${record['recommendedVerified']} '
      'dropped=${record['droppedItems']}/${record['totalItems']}$error';
}

Future<Map<String, dynamic>> _repositoryProvenance() async {
  Future<String> git(List<String> args) async {
    final result = await Process.run('git', args);
    return (result.stdout as String).trim();
  }

  return {
    'head': await git(['rev-parse', '--short', 'HEAD']),
    'dirty': (await git(['status', '--porcelain'])).isNotEmpty,
  };
}

String _string(Object? value) => value is String ? value.trim() : '';

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';
