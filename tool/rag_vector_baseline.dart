import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

Future<void> main(List<String> args) async {
  final options = RagVectorBaselineOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag_vector_baseline.dart '
      '--fixture PATH --out-dir PATH --base-url URL --model ID '
      '[--api-key KEY] [--run-id ID]',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRagVectorBaseline(options);
    stdout.writeln(report.toMarkdown());
    if (!report.passed) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('RAG vector baseline failed: $error');
    exitCode = 65;
  }
}

Future<RagRetrievalReport> runRagVectorBaseline(
  RagVectorBaselineOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await RagRetrievalFixture.load(fixtureFile);
  final documents = await loadRagFixtureDocuments(fixture);
  final metadata = await RagRetrievalBaselineMetadata.fromWorkspace();
  final run = captureRagRetrievalBaseline(
    fixture: fixture,
    documents: documents,
    metadata: metadata,
    runId: options.runId,
    warmState: 'warm',
  );
  final client = RagEmbeddingClient(
    baseUrl: options.baseUrl,
    apiKey: options.apiKey,
    model: options.model,
  );
  final stopwatch = Stopwatch()..start();
  final vectors = await client.embed([
    ...documents.map((item) => item.content),
    ...fixture.cases.map((item) => item.query),
  ]);
  stopwatch.stop();
  final documentVectors = vectors.take(documents.length).toList();
  final queryVectors = vectors.skip(documents.length).toList();
  final vectorResults = <Map<String, Object?>>[];
  for (var index = 0; index < fixture.cases.length; index++) {
    final ranking = rankRagVectors(
      queryVectors[index],
      documentVectors,
      limit: fixture.metricK,
    );
    final hits = [for (final item in ranking) documents[item].toHit()];
    vectorResults.add(_result(fixture.cases[index], hits, documents));
  }
  vectorResults.first['latencyMs'] = stopwatch.elapsedMilliseconds;
  final arms = (run['arms'] as List<Object?>).cast<Map<String, Object?>>();
  final lexical = arms.singleWhere((item) => item['id'] == 'L');
  final lexicalResults = (lexical['results'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final hybridResults = <Map<String, Object?>>[];
  for (var index = 0; index < fixture.cases.length; index++) {
    final lexicalIds =
        ((lexicalResults[index]['hits'] as List<Object?>)
                .cast<Map<String, Object?>>())
            .map((item) => item['objectId']! as String)
            .toList();
    final vectorIds =
        ((vectorResults[index]['hits'] as List<Object?>)
                .cast<Map<String, Object?>>())
            .map((item) => item['objectId']! as String)
            .toList();
    final fused = fuseRagRanks(lexicalIds, vectorIds, limit: fixture.metricK);
    hybridResults.add(
      _result(fixture.cases[index], [
        for (final id in fused)
          documents.singleWhere((item) => item.objectId == id).toHit(),
      ], documents),
    );
  }
  final resource = (lexical['resource'] as Map).cast<String, Object?>();
  arms[arms.indexWhere((item) => item['id'] == 'V')] = _arm(
    'V',
    vectorResults,
    resource,
  );
  arms[arms.indexWhere((item) => item['id'] == 'H')] = _arm(
    'H',
    hybridResults,
    resource,
  );
  final runMetadata = (run['metadata'] as Map).cast<String, Object?>();
  runMetadata['embeddingFingerprint'] = sha256
      .convert(
        utf8.encode(
          '${options.model}:${vectors.first.length}:${vectors.first.take(8).join(',')}',
        ),
      )
      .toString();
  runMetadata['embeddingModel'] = options.model;
  runMetadata['embeddingEndpoint'] = options.baseUrl;
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

List<int> rankRagVectors(
  List<double> query,
  List<List<double>> documents, {
  required int limit,
}) {
  final indices = List<int>.generate(documents.length, (index) => index);
  indices.sort((a, b) {
    final score = _cosine(
      query,
      documents[b],
    ).compareTo(_cosine(query, documents[a]));
    return score != 0 ? score : a.compareTo(b);
  });
  return indices.take(limit).toList();
}

List<String> fuseRagRanks(
  List<String> lexical,
  List<String> vector, {
  required int limit,
}) {
  final scores = <String, double>{};
  for (final ranking in [lexical, vector]) {
    for (var index = 0; index < ranking.length; index++) {
      scores.update(
        ranking[index],
        (value) => value + 1 / (60 + index + 1),
        ifAbsent: () => 1 / (60 + index + 1),
      );
    }
  }
  final ids = scores.keys.toList()
    ..sort((a, b) {
      final score = scores[b]!.compareTo(scores[a]!);
      return score != 0 ? score : a.compareTo(b);
    });
  return ids.take(limit).toList();
}

double _cosine(List<double> left, List<double> right) {
  var dot = 0.0;
  var leftNorm = 0.0;
  var rightNorm = 0.0;
  for (var index = 0; index < left.length; index++) {
    dot += left[index] * right[index];
    leftNorm += left[index] * left[index];
    rightNorm += right[index] * right[index];
  }
  return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
}

Map<String, Object?> _result(
  RagRetrievalFixtureCase fixtureCase,
  List<Map<String, Object?>> hits,
  List<RagFixtureDocument> documents,
) => {
  'caseId': fixtureCase.id,
  'hits': hits,
  'latencyMs': 0,
  'promptTokens': 0,
  'contextTokens':
      ((hits
                  .map((hit) {
                    final content = documents
                        .singleWhere((item) => item.objectId == hit['objectId'])
                        .content;
                    return content.runes.length;
                  })
                  .fold<int>(0, (sum, value) => sum + value)) /
              4)
          .ceil(),
};

Map<String, Object?> _arm(
  String id,
  List<Map<String, Object?>> results,
  Map<String, Object?> resource,
) => {
  'id': id,
  'status': 'available',
  'negativeControl': false,
  'minimumHitAtK': 0,
  'resource': resource,
  'results': results,
};

final class RagEmbeddingClient {
  const RagEmbeddingClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  Future<List<List<double>>> embed(List<String> input) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}/embeddings'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(jsonEncode({'model': model, 'input': input}));
      final response = await request.close();
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(minutes: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      final json = (jsonDecode(body) as Map).cast<String, Object?>();
      final data = (json['data'] as List).cast<Map>()
        ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
      return [
        for (final item in data)
          (item['embedding'] as List)
              .map((value) => (value as num).toDouble())
              .toList(),
      ];
    } finally {
      client.close(force: true);
    }
  }
}

final class RagVectorBaselineOptions {
  const RagVectorBaselineOptions({
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

  static RagVectorBaselineOptions? parse(List<String> args) {
    if (args.length.isOdd) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final fixture = values['--fixture'];
    final outDir = values['--out-dir'];
    final baseUrl = values['--base-url'];
    final model = values['--model'];
    if (fixture == null || outDir == null || baseUrl == null || model == null) {
      return null;
    }
    return RagVectorBaselineOptions(
      fixturePath: fixture,
      outDir: outDir,
      baseUrl: baseUrl,
      apiKey: values['--api-key'] ?? 'no-key',
      model: model,
      runId:
          values['--run-id'] ??
          'rag1-vector-${DateTime.now().toUtc().toIso8601String()}',
    );
  }
}
