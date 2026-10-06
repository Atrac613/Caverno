import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/project_farm/domain/roadmap_next_task_contract.dart';
import 'package:caverno/features/project_farm/domain/roadmap_next_task_extractor.dart';

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
  // Timing per stage, keyed by schema name, recorded around the shared port.
  final stages = <String, Map<String, dynamic>>{};
  Future<RoadmapCompletion> complete({
    required String system,
    required String user,
    required String schemaName,
    required Map<String, dynamic> schema,
    required int maxTokens,
  }) async {
    final result = await completeStructured(
      client: client,
      options: options,
      system: system,
      user: user,
      schemaName: schemaName,
      schema: schema,
      maxTokens: maxTokens,
    );
    stages[schemaName] = {
      'latencyMs': result.latency.inMilliseconds,
      'promptChars': result.promptChars,
      'finishReason': result.finishReason,
    };
    return RoadmapCompletion(
      content: result.content,
      finishReason: result.finishReason,
    );
  }

  try {
    final text = await fixture.load();
    record['documentChars'] = text.length;
    record['documentLines'] = const LineSplitter().convert(text).length;
    final extraction = await RoadmapNextTaskExtractor(
      complete: complete,
      directBudgetChars: options.directBudgetChars,
    ).extract(text);

    record['route'] = extraction.route.name;
    final outlineStage = stages['caverno_roadmap_sections'];
    if (outlineStage != null) {
      record['outline'] = {
        ...outlineStage,
        'chosen': [
          for (final chosen in extraction.outlineChosen)
            {
              'heading': chosen.heading,
              'line': chosen.line,
              'resolvedLine': chosen.resolvedLine,
            },
        ],
      };
      record['excerptChars'] = extraction.excerptChars;
    }
    record['extraction'] = {
      ...?stages['caverno_roadmap_next_task'],
      'rawContent': _clip(extraction.rawContent, 6000),
    };
    if (extraction.parseFailed) {
      record['parseFailed'] = true;
      record['truncated'] = extraction.truncated;
      record['correct'] = false;
      return record;
    }

    List<Map<String, dynamic>> encode(List<VerifiedRoadmapItem> items) => [
      for (final entry in items)
        {...entry.item.toJson(), 'verification': entry.verification.toJson()},
    ];
    record['items'] = {
      'recommended': encode(extraction.recommended),
      'current': encode(extraction.current),
      'blocked': encode(extraction.blocked),
    };
    record['totalItems'] = extraction.allItems.length;
    record['droppedItems'] = extraction.droppedCount;

    final recommended = extraction.recommended.firstOrNull;
    final recommendedVerified = recommended?.verification.kept ?? false;
    record['recommendedId'] = recommended?.item.id;
    record['recommendedVerified'] = recommendedVerified;
    record['correct'] = recommendationCorrect(
      expectedId: fixture.expectedRecommendedId,
      modelRecommended: recommended?.item,
      recommendedVerified: recommendedVerified,
    );
  } on Object catch (error) {
    record['error'] = '$error';
    record['correct'] = false;
  }
  return record;
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

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';
