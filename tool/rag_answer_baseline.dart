import 'dart:convert';
import 'dart:io';

import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

Future<void> main(List<String> args) async {
  final options = RagAnswerBaselineOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag_answer_baseline.dart '
      '--fixture PATH --out-dir PATH --base-url URL --model ID '
      '[--api-key KEY] [--run-id ID]',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRagAnswerBaseline(options);
    stdout.writeln(report.toMarkdown());
    if (!report.passed) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('RAG answer baseline failed: $error');
    exitCode = 65;
  }
}

Future<RagRetrievalReport> runRagAnswerBaseline(
  RagAnswerBaselineOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await RagRetrievalFixture.load(fixtureFile);
  final documents = await loadRagFixtureDocuments(fixture);
  final workspace = await RagRetrievalBaselineMetadata.fromWorkspace();
  final run = captureRagRetrievalBaseline(
    fixture: fixture,
    documents: documents,
    metadata: workspace,
    runId: options.runId,
    warmState: 'warm',
  );
  final arms = (run['arms'] as List<Object?>).cast<Map<String, Object?>>();
  final client = RagAnswerClient(
    baseUrl: options.baseUrl,
    apiKey: options.apiKey,
    model: options.model,
  );
  final factCatalog = buildRagFactCatalog(fixture);
  for (final armId in const ['NONE', 'L', 'FULL']) {
    final arm = arms.singleWhere((item) => item['id'] == armId);
    final results = (arm['results'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final response = await client.answer(
      buildRagAnswerPrompt(
        fixture: fixture,
        documents: documents,
        results: results,
        factCatalog: factCatalog,
      ),
    );
    applyRagAnswerSelections(
      fixture: fixture,
      results: results,
      selections: response.selections,
      factCatalog: factCatalog,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      latencyMs: response.latencyMs,
    );
  }
  final metadata = (run['metadata'] as Map).cast<String, Object?>();
  metadata.addAll({
    'answerModel': options.model,
    'answerEndpoint': options.baseUrl,
    'answerSampler': 'temperature_0_json_v1',
    'answerScoring': 'candidate_fact_and_citation_selection_v1',
  });
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  final runFile = File('${outputDirectory.path}/rag_retrieval_run.json');
  await runFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(run)}\n',
  );
  return runRagRetrievalEval(
    RagRetrievalEvalOptions(
      fixturePath: fixtureFile.path,
      runPath: runFile.path,
      outDir: outputDirectory.path,
    ),
  );
}

Map<String, String> buildRagFactCatalog(RagRetrievalFixture fixture) {
  final facts =
      fixture.cases.expand((item) => item.answerFacts).toSet().toList()..sort();
  return {
    for (var index = 0; index < facts.length; index++)
      'F${index + 1}': facts[index],
  };
}

String buildRagAnswerPrompt({
  required RagRetrievalFixture fixture,
  required List<RagFixtureDocument> documents,
  required List<Map<String, Object?>> results,
  required Map<String, String> factCatalog,
}) {
  final byObject = {
    for (final document in documents) document.objectId: document,
  };
  final cases = <Map<String, Object?>>[];
  for (final fixtureCase in fixture.cases) {
    final result = results.singleWhere(
      (item) => item['caseId'] == fixtureCase.id,
    );
    final hits = (result['hits'] as List<Object?>).cast<Map<String, Object?>>();
    cases.add({
      'caseId': fixtureCase.id,
      'question': fixtureCase.query,
      'evidence': [
        for (final hit in hits)
          {
            'citationId': hit['chunkId'],
            'content': byObject[hit['objectId']]?.content ?? '',
          },
      ],
    });
  }
  return '''You are a deterministic evidence selector. For each case, select only
candidate fact IDs directly supported by that case's evidence and needed to
answer its question. Select only citation IDs present in that case's evidence.
If evidence does not answer the question, return empty arrays. Do not use prior
knowledge. Return JSON only with this shape:
{"results":[{"caseId":"...","factIds":["F1"],"citations":["path#1"]}]}

Candidate facts:
${jsonEncode(factCatalog)}

Cases:
${jsonEncode(cases)}''';
}

void applyRagAnswerSelections({
  required RagRetrievalFixture fixture,
  required List<Map<String, Object?>> results,
  required List<RagAnswerSelection> selections,
  required Map<String, String> factCatalog,
  required int promptTokens,
  required int completionTokens,
  required int latencyMs,
}) {
  final factsToIds = {
    for (final entry in factCatalog.entries) entry.value: entry.key,
  };
  for (var index = 0; index < results.length; index++) {
    final result = results[index];
    final fixtureCase = fixture.cases.singleWhere(
      (item) => item.id == result['caseId'],
    );
    final selection = selections.singleWhere(
      (item) => item.caseId == fixtureCase.id,
    );
    final expectedFacts = fixtureCase.answerFacts
        .map((fact) => factsToIds[fact])
        .toSet();
    final expectedCitations = fixtureCase.citations.toSet();
    result['answerEvaluation'] = {
      'groundedClaims': selection.factIds
          .toSet()
          .intersection(expectedFacts)
          .length,
      'totalClaims': selection.factIds.length,
      'validCitations': selection.citations
          .toSet()
          .intersection(expectedCitations)
          .length,
      'totalCitations': selection.citations.length,
    };
    result['latencyMs'] = index == 0 ? latencyMs : 0;
    result['promptTokens'] = index == 0 ? promptTokens + completionTokens : 0;
  }
}

final class RagAnswerClient {
  const RagAnswerClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  Future<RagAnswerResponse> answer(String prompt) async {
    final client = HttpClient();
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.postUrl(
        Uri.parse(
          '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(
        jsonEncode({
          'model': model,
          'temperature': 0,
          'max_tokens': 4096,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      stopwatch.stop();
      final json = (jsonDecode(body) as Map).cast<String, Object?>();
      final choices = (json['choices'] as List).cast<Map>();
      final message = choices.first['message'] as Map;
      final content = message['content'] as String;
      final decoded = _decodeModelJson(content);
      final usage =
          (json['usage'] as Map?)?.cast<String, Object?>() ?? const {};
      return RagAnswerResponse(
        selections: [
          for (final item in (decoded['results'] as List).cast<Map>())
            RagAnswerSelection.fromJson(item.cast<String, Object?>()),
        ],
        promptTokens: usage['prompt_tokens'] as int? ?? 0,
        completionTokens: usage['completion_tokens'] as int? ?? 0,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }
}

Map<String, Object?> _decodeModelJson(String content) {
  final start = content.indexOf('{');
  final end = content.lastIndexOf('}');
  if (start < 0 || end < start) {
    throw const FormatException('Model response did not contain JSON.');
  }
  return (jsonDecode(content.substring(start, end + 1)) as Map)
      .cast<String, Object?>();
}

final class RagAnswerSelection {
  const RagAnswerSelection({
    required this.caseId,
    required this.factIds,
    required this.citations,
  });

  final String caseId;
  final List<String> factIds;
  final List<String> citations;

  factory RagAnswerSelection.fromJson(Map<String, Object?> json) =>
      RagAnswerSelection(
        caseId: json['caseId'] as String,
        factIds: (json['factIds'] as List).cast<String>(),
        citations: (json['citations'] as List).cast<String>(),
      );
}

final class RagAnswerResponse {
  const RagAnswerResponse({
    required this.selections,
    required this.promptTokens,
    required this.completionTokens,
    required this.latencyMs,
  });

  final List<RagAnswerSelection> selections;
  final int promptTokens;
  final int completionTokens;
  final int latencyMs;
}

final class RagAnswerBaselineOptions {
  const RagAnswerBaselineOptions({
    required this.fixturePath,
    required this.outDir,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.runId,
  });

  final String fixturePath;
  final String outDir;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String runId;

  static RagAnswerBaselineOptions? parse(List<String> args) {
    if (args.length.isOdd) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    const supported = {
      '--fixture',
      '--out-dir',
      '--base-url',
      '--api-key',
      '--model',
      '--run-id',
    };
    if (!supported.containsAll(values.keys)) return null;
    final fixture = values['--fixture'];
    final outDir = values['--out-dir'];
    final baseUrl = values['--base-url'];
    final model = values['--model'];
    if (fixture == null || outDir == null || baseUrl == null || model == null) {
      return null;
    }
    return RagAnswerBaselineOptions(
      fixturePath: fixture,
      outDir: outDir,
      baseUrl: baseUrl,
      apiKey: values['--api-key'] ?? 'no-key',
      model: model,
      runId:
          values['--run-id'] ??
          'rag1-answer-${DateTime.now().toUtc().toIso8601String()}',
    );
  }
}
