import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:drift/drift.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag2_storage_replay.dart';
import 'rag3_candidate_run_producer.dart';
import 'rag3_offline_hybrid_eval.dart';
import 'rag2_hosted_retrieval_eval.dart';

const rag3PromotionRunId = 'rag3-promotion-run-v1';
const rag3PromotionProjectId = 'rag3-promotion-eval-project';

Future<void> main(List<String> args) async {
  final options = Rag3PromotionRunOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag3_promotion_run.dart '
      '--fixture PATH --oracle PATH --out-dir PATH '
      '--base-url URL --model ID [--api-key KEY]',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag3Promotion(options);
    stdout.write(report.toMarkdown());
    if (!report.passed) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('RAG3 promotion run failed: $error');
    exitCode = 65;
  }
}

Future<Rag3HybridReport> runRag3Promotion(
  Rag3PromotionRunOptions options, {
  Rag3EmbeddingProvider? embeddingProvider,
  String? buildCommit,
  bool? buildDirty,
}) async {
  final output = Directory(options.outDir);
  if (output.existsSync() && output.listSync().isNotEmpty) {
    throw StateError('RAG3 promotion output already exists; refusing rerun.');
  }
  final fixture = await Rag3HybridFixture.load(
    fixtureFile: File(options.fixturePath),
    oracleFile: File(options.oraclePath),
  );
  final gitState = buildCommit == null || buildDirty == null
      ? await _readGitState()
      : null;
  final resolvedCommit = buildCommit ?? gitState!.$1;
  final resolvedDirty = buildDirty ?? gitState!.$2;
  final endpointIdentity = Rag3VectorFingerprint.normalizeEndpointIdentity(
    '${options.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/embeddings',
  );
  final provider =
      embeddingProvider ??
      Rag3HttpEmbeddingProvider(
        endpoint: endpointIdentity,
        apiKey: options.apiKey,
      );
  final snapshot = _buildHostedSnapshot(fixture);
  final temporary = await Directory.systemTemp.createTemp('rag3-promotion-');
  try {
    final databasePath = '${temporary.path}/caverno.sqlite';
    await prepareRag2DriftHost(databasePath: databasePath);
    final declarationIdentity = rag2ExplicitSourceRootsDeclarationIdentity(
      const ['docs'],
    );
    final store = Rag2DriftDaoGenerationStore.open(
      databasePath: databasePath,
      projectId: rag3PromotionProjectId,
    );
    try {
      final applied = await store.apply(
        declarationIdentity: declarationIdentity,
        snapshot: snapshot.snapshot,
        indexSearch: true,
      );
      if (applied.decision != 'applied') {
        throw StateError('RAG3 promotion snapshot was not applied.');
      }
      final generation = await store.read(declarationIdentity);
      if (generation == null) {
        throw StateError('RAG3 promotion snapshot did not reopen.');
      }
      final ranker = _Rag3HostedLexicalRanker(
        store: store,
        generation: generation,
        declarationIdentity: declarationIdentity,
        externalChunkIds: snapshot.externalChunkIds,
      );
      final corpusChunkIds = fixture.chunks.keys.toList();
      final corpusEmbedding = await provider.embed(
        model: options.model,
        inputs: [
          for (final chunkId in corpusChunkIds) _chunkContent(fixture, chunkId),
        ],
      );
      if (corpusEmbedding.vectors.length != corpusChunkIds.length) {
        throw StateError('Embedding corpus response count is incomplete.');
      }
      final corpusDimension = _uniformDimension(corpusEmbedding.vectors);
      final corpusFingerprint = Rag3VectorFingerprint(
        schemaVersion: 1,
        endpointIdentity: endpointIdentity,
        requestedModelId: options.model,
        responseModelId: corpusEmbedding.responseModelId,
        dimension: corpusDimension,
      );
      final corpusVectors = {
        for (var index = 0; index < corpusChunkIds.length; index++)
          corpusChunkIds[index]: corpusEmbedding.vectors[index],
      };
      final cases = <Rag3CandidateCaseInput>[];
      for (final fixtureCase in fixture.cases.values) {
        if (!fixtureCase.shouldSearch) {
          cases.add(
            Rag3CandidateCaseInput(
              caseId: fixtureCase.id,
              submitted: false,
              lexicalRankedChunkIds: const [],
              vector: Rag3VectorRankingInput.unavailable(
                fingerprint: corpusFingerprint,
                reason: 'not_submitted',
              ),
              lexicalLatencyMs: 0,
              peakRssBytes: ProcessInfo.currentRss,
              peakVramBytes: 0,
            ),
          );
          continue;
        }
        final fixtureInput = await _queryForCase(
          fixturePath: options.fixturePath,
          caseId: fixtureCase.id,
        );
        final lexical = await ranker.rank(
          fixtureInput,
          limit: rag3MaxInputDepth,
        );
        final queryEmbedding = await provider.embed(
          model: options.model,
          inputs: [fixtureInput],
        );
        if (queryEmbedding.vectors.length != 1) {
          throw StateError('Embedding query response count is invalid.');
        }
        final queryFingerprint = Rag3VectorFingerprint(
          schemaVersion: 1,
          endpointIdentity: endpointIdentity,
          requestedModelId: options.model,
          responseModelId: queryEmbedding.responseModelId,
          dimension: queryEmbedding.vectors.single.length,
        );
        cases.add(
          Rag3CandidateCaseInput(
            caseId: fixtureCase.id,
            submitted: true,
            lexicalRankedChunkIds: lexical.chunkIds,
            vector: Rag3VectorRankingInput.available(
              queryFingerprint: queryFingerprint,
              corpusFingerprint: corpusFingerprint,
              queryVector: queryEmbedding.vectors.single,
              corpusVectors: corpusVectors,
              latencyMs: queryEmbedding.latencyMs,
            ),
            lexicalLatencyMs: lexical.latencyMs,
            peakRssBytes: ProcessInfo.currentRss,
            peakVramBytes: 0,
          ),
        );
      }
      final runJson = const Rag3CandidateRunProducer().produce(
        fixture: fixture,
        runId: rag3PromotionRunId,
        metadata: {
          'buildCommit': resolvedCommit,
          'buildDirty': resolvedDirty,
          'hardware':
              '${Platform.operatingSystem}/${Platform.numberOfProcessors}',
          'warmState': 'cold',
          'tokenEstimateMethod': 'unicode_code_points_div_4_v1',
          'lexicalCandidate': rag2HostedRetrievalCandidate,
          'lexicalThreshold': rag2HostedRetrievalThreshold,
          'hostedSnapshotHash': generation.snapshot.snapshotHash,
          'corpusEmbeddingLatencyMs': corpusEmbedding.latencyMs,
          'resourceScope': 'local_producer_process',
        },
        cases: cases,
      );
      final run = Rag3CandidateRun.fromJson(runJson);
      final report = evaluateRag3HybridRun(fixture: fixture, run: run);
      await output.create(recursive: true);
      await _writeJson(File('${output.path}/rag3_promotion_run.json'), runJson);
      await _writeJson(
        File('${output.path}/rag3_offline_hybrid_eval.json'),
        report.toJson(),
      );
      await File(
        '${output.path}/rag3_offline_hybrid_eval.md',
      ).writeAsString(report.toMarkdown());
      return report;
    } finally {
      await store.close();
    }
  } finally {
    await temporary.delete(recursive: true);
  }
}

abstract interface class Rag3EmbeddingProvider {
  Future<Rag3EmbeddingResponse> embed({
    required String model,
    required List<String> inputs,
  });
}

final class Rag3HttpEmbeddingProvider implements Rag3EmbeddingProvider {
  const Rag3HttpEmbeddingProvider({
    required this.endpoint,
    required this.apiKey,
  });

  final String endpoint;
  final String apiKey;

  @override
  Future<Rag3EmbeddingResponse> embed({
    required String model,
    required List<String> inputs,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final watch = Stopwatch()..start();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      final payload = utf8.encode(
        jsonEncode({'model': model, 'input': inputs}),
      );
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(minutes: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Embedding request failed with HTTP ${response.statusCode}.',
        );
      }
      final json = (jsonDecode(body) as Map).cast<String, Object?>();
      final responseModelId = json['model'];
      final rawData = json['data'];
      if (responseModelId is! String ||
          responseModelId.isEmpty ||
          rawData is! List) {
        throw const FormatException('Embedding response metadata is invalid.');
      }
      final data = rawData.cast<Map>()
        ..sort((left, right) {
          return (left['index'] as int).compareTo(right['index'] as int);
        });
      final vectors = [
        for (final item in data)
          (item['embedding'] as List)
              .map((value) => (value as num).toDouble())
              .toList(),
      ];
      watch.stop();
      return Rag3EmbeddingResponse(
        responseModelId: responseModelId,
        vectors: vectors,
        latencyMs: _elapsedMilliseconds(watch),
      );
    } finally {
      client.close(force: true);
    }
  }
}

final class Rag3EmbeddingResponse {
  const Rag3EmbeddingResponse({
    required this.responseModelId,
    required this.vectors,
    required this.latencyMs,
  });

  final String responseModelId;
  final List<List<double>> vectors;
  final int latencyMs;
}

final class Rag3PromotionRunOptions {
  const Rag3PromotionRunOptions({
    required this.fixturePath,
    required this.oraclePath,
    required this.outDir,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String fixturePath;
  final String oraclePath;
  final String outDir;
  final String baseUrl;
  final String model;
  final String apiKey;

  static Rag3PromotionRunOptions? parse(List<String> args) {
    if (args.length.isOdd) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final fixture = values['--fixture'];
    final oracle = values['--oracle'];
    final out = values['--out-dir'];
    final baseUrl = values['--base-url'];
    final model = values['--model'];
    if ([fixture, oracle, out, baseUrl, model].any((value) => value == null)) {
      return null;
    }
    return Rag3PromotionRunOptions(
      fixturePath: fixture!,
      oraclePath: oracle!,
      outDir: out!,
      baseUrl: baseUrl!,
      model: model!,
      apiKey: values['--api-key'] ?? 'no-key',
    );
  }
}

final class _HostedSnapshot {
  const _HostedSnapshot({
    required this.snapshot,
    required this.externalChunkIds,
  });

  final Rag2KnowledgeSnapshot snapshot;
  final Map<String, String> externalChunkIds;
}

_HostedSnapshot _buildHostedSnapshot(Rag3HybridFixture fixture) {
  final objects = <Rag2KnowledgeObject>[];
  final externalChunkIds = <String, String>{};
  for (final source in fixture.objects.values) {
    final objectId = rag2KnowledgeObjectId(
      projectId: rag3PromotionProjectId,
      repoRelativePath: source.sourcePath,
    );
    final chunks = <Rag2KnowledgeChunk>[];
    for (final sourceChunk in source.chunks) {
      final content = source.sourceLines
          .sublist(sourceChunk.lineStart - 1, sourceChunk.lineEnd)
          .join('\n');
      final locator = 'rag3:${sourceChunk.id}';
      final chunkId = rag2KnowledgeChunkId(
        objectId: objectId,
        locator: locator,
        contentHash: sourceChunk.contentHash,
      );
      externalChunkIds[chunkId] = sourceChunk.id;
      chunks.add(
        Rag2KnowledgeChunk(
          chunkId: chunkId,
          objectId: objectId,
          locator: locator,
          contentHash: sourceChunk.contentHash,
          content: content,
          passageRole: 'unknown',
          provenance: Rag2KnowledgeProvenance(
            projectId: rag3PromotionProjectId,
            repoRelativePath: source.sourcePath,
            revision: source.revision,
            objectContentHash: source.objectContentHash,
            lineStart: sourceChunk.lineStart,
            lineEnd: sourceChunk.lineEnd,
            sourceTrust: source.sourceTrust,
          ),
        ),
      );
    }
    objects.add(
      Rag2KnowledgeObject(
        objectId: objectId,
        projectId: rag3PromotionProjectId,
        repoRelativePath: source.sourcePath,
        sourceKind: source.sourcePath.endsWith('.dart') ? 'dart' : 'document',
        sourceTrust: source.sourceTrust,
        revision: source.revision,
        contentHash: source.objectContentHash,
        chunkIds: [for (final chunk in chunks) chunk.chunkId],
        chunks: chunks,
      ),
    );
  }
  objects.sort(
    (left, right) => left.repoRelativePath.compareTo(right.repoRelativePath),
  );
  return _HostedSnapshot(
    snapshot: Rag2KnowledgeSnapshot(
      snapshotId: 'rag3-promotion-hosted-v1',
      snapshotHash: rag2KnowledgeSnapshotHash(objects),
      objects: objects,
    ),
    externalChunkIds: Map.unmodifiable(externalChunkIds),
  );
}

final class _Rag3HostedLexicalRanker {
  _Rag3HostedLexicalRanker({
    required this.store,
    required this.generation,
    required this.declarationIdentity,
    required this.externalChunkIds,
  }) : _chunks = {
         for (final chunk in generation.snapshot.chunks) chunk.chunkId: chunk,
       },
       _documentTerms = {
         for (final chunk in generation.snapshot.chunks)
           chunk.chunkId: tokenizeRag2Lexical(
             chunk.content,
             Rag2LexicalPolicy.trigram,
           ),
       } {
    for (final terms in _documentTerms.values) {
      for (final term in terms) {
        _documentFrequency.update(
          term,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  final Rag2DriftDaoGenerationStore store;
  final Rag2StoredGeneration generation;
  final String declarationIdentity;
  final Map<String, String> externalChunkIds;
  final Map<String, Rag2KnowledgeChunk> _chunks;
  final Map<String, Set<String>> _documentTerms;
  final Map<String, int> _documentFrequency = {};

  Future<_LexicalRanking> rank(String query, {required int limit}) async {
    final watch = Stopwatch()..start();
    final queryTerms = tokenizeRag2Lexical(query, Rag2LexicalPolicy.trigram);
    if (queryTerms.isEmpty) {
      return const _LexicalRanking(chunkIds: [], latencyMs: 0);
    }
    final denominator = queryTerms.fold<double>(
      0,
      (sum, term) => sum + _idf(term),
    );
    final matchQuery = queryTerms
        .map((term) => '"${term.replaceAll('"', '""')}"')
        .join(' OR ');
    final rows = await store.database
        .customSelect(
          'SELECT chunk_id, object_id, content '
          'FROM ${AppDatabase.rag2ChunkSearchTable} '
          'WHERE ${AppDatabase.rag2ChunkSearchTable} MATCH ? '
          'AND project_identity = ? AND declaration_identity = ? '
          'AND generation = ? AND snapshot_hash = ? '
          'ORDER BY bm25(${AppDatabase.rag2ChunkSearchTable}), chunk_id LIMIT ?',
          variables: [
            Variable<String>(matchQuery),
            Variable<String>(store.projectIdentity),
            Variable<String>(declarationIdentity),
            Variable<int>(generation.generation),
            Variable<String>(generation.snapshot.snapshotHash),
            Variable<int>(limit * 8),
          ],
        )
        .get();
    final ranked = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      final chunkId = row.read<String>('chunk_id');
      final chunk = _chunks[chunkId];
      final externalId = externalChunkIds[chunkId];
      if (chunk == null || externalId == null || !seen.add(chunkId)) {
        throw StateError('Hosted lexical provenance validation failed.');
      }
      final expectedTerms = _documentTerms[chunkId]!;
      final expectedContent = expectedTerms.toList()..sort();
      final storedTokens = row.read<String>('content').split(' ')..sort();
      if (row.read<String>('object_id') != chunk.objectId ||
          storedTokens.join('\u0000') != expectedContent.join('\u0000')) {
        throw StateError('Hosted lexical index validation failed.');
      }
      final coverage =
          queryTerms
              .intersection(expectedTerms)
              .fold<double>(0, (sum, term) => sum + _idf(term)) /
          denominator;
      if (coverage < rag2HostedRetrievalThreshold) continue;
      ranked.add(externalId);
      if (ranked.length == limit) break;
    }
    watch.stop();
    return _LexicalRanking(
      chunkIds: List.unmodifiable(ranked),
      latencyMs: _elapsedMilliseconds(watch),
    );
  }

  double _idf(String term) =>
      math.log(
        (_documentTerms.length + 1) / ((_documentFrequency[term] ?? 0) + 1),
      ) +
      1;
}

final class _LexicalRanking {
  const _LexicalRanking({required this.chunkIds, required this.latencyMs});

  final List<String> chunkIds;
  final int latencyMs;
}

String _chunkContent(Rag3HybridFixture fixture, String chunkId) {
  final chunk = fixture.chunks[chunkId]!;
  final object = fixture.objects[chunk.objectId]!;
  return object.sourceLines
      .sublist(chunk.lineStart - 1, chunk.lineEnd)
      .join('\n');
}

Future<String> _queryForCase({
  required String fixturePath,
  required String caseId,
}) async {
  final json = (jsonDecode(await File(fixturePath).readAsString()) as Map)
      .cast<String, Object?>();
  final cases = (json['cases'] as List).cast<Map>();
  final item = cases.singleWhere((value) => value['id'] == caseId);
  return item['query'] as String;
}

int _uniformDimension(List<List<double>> vectors) {
  if (vectors.isEmpty || vectors.first.isEmpty) {
    throw StateError('Embedding corpus response is empty.');
  }
  final dimension = vectors.first.length;
  if (vectors.any((vector) => vector.length != dimension)) {
    throw StateError('Embedding corpus dimensions are inconsistent.');
  }
  return dimension;
}

Future<(String, bool)> _readGitState() async {
  final revision = await Process.run('git', const ['rev-parse', 'HEAD']);
  final status = await Process.run('git', const ['status', '--porcelain']);
  if (revision.exitCode != 0 || status.exitCode != 0) {
    throw StateError('Unable to capture Git build identity.');
  }
  return (
    (revision.stdout as String).trim(),
    (status.stdout as String).trim().isNotEmpty,
  );
}

Future<void> _writeJson(File file, Map<String, Object?> value) => file
    .writeAsString('${const JsonEncoder.withIndent('  ').convert(value)}\n');

int _elapsedMilliseconds(Stopwatch stopwatch) {
  if (stopwatch.elapsedMicroseconds == 0) return 0;
  return (stopwatch.elapsedMicroseconds / 1000).ceil();
}
