import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'rag_retrieval_eval.dart';

Future<void> main(List<String> args) async {
  final options = RagRetrievalBaselineOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag_retrieval_baseline.dart '
      '--fixture PATH --out-dir PATH [--run-id ID] '
      '[--warm-state cold|warm]',
    );
    exitCode = 64;
    return;
  }
  try {
    final metadata = await RagRetrievalBaselineMetadata.fromWorkspace();
    final report = await runRagRetrievalBaseline(options, metadata: metadata);
    stdout.writeln(report.toMarkdown());
    if (!report.passed) {
      exitCode = 1;
    }
  } on Object catch (error) {
    stderr.writeln('RAG retrieval baseline failed: $error');
    exitCode = 65;
  }
}

Future<RagRetrievalReport> runRagRetrievalBaseline(
  RagRetrievalBaselineOptions options, {
  required RagRetrievalBaselineMetadata metadata,
}) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await RagRetrievalFixture.load(fixtureFile);
  fixture.validate();
  final documents = await loadRagFixtureDocuments(fixture);
  final run = captureRagRetrievalBaseline(
    fixture: fixture,
    documents: documents,
    metadata: metadata,
    runId: options.runId,
    warmState: options.warmState,
  );
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

Map<String, Object?> captureRagRetrievalBaseline({
  required RagRetrievalFixture fixture,
  required List<RagFixtureDocument> documents,
  required RagRetrievalBaselineMetadata metadata,
  required String runId,
  required String warmState,
}) {
  final rssBefore = ProcessInfo.currentRss;
  final database = sqlite3.openInMemory();
  try {
    database.execute(
      'CREATE VIRTUAL TABLE knowledge USING fts5('
      'object_id UNINDEXED, chunk_id UNINDEXED, content, '
      "tokenize='unicode61')",
    );
    for (final document in documents) {
      database.execute(
        'INSERT INTO knowledge(object_id, chunk_id, content) VALUES (?, ?, ?)',
        [document.objectId, document.chunkId, document.content],
      );
    }
    final lexical = <Map<String, Object?>>[];
    final none = <Map<String, Object?>>[];
    final full = <Map<String, Object?>>[];
    final empty = <Map<String, Object?>>[];
    if (warmState == 'warm') {
      for (final fixtureCase in fixture.cases) {
        searchRagFixtureLexically(
          database,
          fixtureCase.query,
          limit: fixture.metricK,
        );
      }
    }
    for (final fixtureCase in fixture.cases) {
      final lexicalWatch = Stopwatch()..start();
      final hits = searchRagFixtureLexically(
        database,
        fixtureCase.query,
        limit: fixture.metricK,
      );
      lexicalWatch.stop();
      final relevantIds = fixtureCase.objectRelevance.keys.toSet();
      final hasRelevantHit = hits.any(
        (hit) => relevantIds.contains(hit['objectId']),
      );
      lexical.add(
        _caseResult(
          fixtureCase,
          hits: hits,
          latencyMs: _elapsedMilliseconds(lexicalWatch),
          context: _contentForHits(documents, hits),
          missReason:
              fixtureCase.category == 'japanese_query' && !hasRelevantHit
              ? (hits.isEmpty ? 'tokenization' : 'ranking')
              : null,
        ),
      );
      none.add(_caseResult(fixtureCase, hits: const [], context: ''));
      full.add(
        _caseResult(
          fixtureCase,
          hits: [for (final document in documents) document.toHit()],
          context: documents.map((document) => document.content).join('\n'),
        ),
      );
      empty.add(_caseResult(fixtureCase, hits: const [], context: ''));
    }
    final peakRss = ProcessInfo.currentRss > rssBefore
        ? ProcessInfo.currentRss
        : rssBefore;
    final resource = <String, Object?>{
      'peakRssBytes': peakRss,
      'peakVramBytes': null,
    };
    return {
      'schemaName': ragRetrievalRunSchema,
      'schemaVersion': ragRetrievalSchemaVersion,
      'runId': runId,
      'fixtureId': fixture.fixtureId,
      'metadata': {
        'buildCommit': metadata.buildCommit,
        'buildDirty': metadata.buildDirty,
        'embeddingFingerprint': 'not_available',
        'hardware': metadata.hardware,
        'warmState': warmState,
        'tokenEstimateMethod': 'unicode_code_points_div_4_v1',
        'lexicalTokenizer': 'unicode61',
        'lexicalQueryPolicy': 'quoted_whitespace_terms_and_v1',
      },
      'arms': [
        _availableArm('L', lexical, resource: resource),
        _unavailableArm('V', 'No embedding capture is configured for Task A.'),
        _unavailableArm('H', 'Vector rankings are unavailable.'),
        _unavailableArm('AK', 'agent-kb provenance gate is not satisfied.'),
        _unavailableArm('H+AK', 'Federated inputs are unavailable.'),
        _availableArm('NONE', none, resource: resource),
        _availableArm('FULL', full, resource: resource),
        _availableArm(
          'NEG-EMPTY',
          empty,
          resource: resource,
          negativeControl: true,
          minimumHitAtK: 0.05,
        ),
      ],
    };
  } finally {
    database.close();
  }
}

List<Map<String, Object?>> searchRagFixtureLexically(
  Database database,
  String query, {
  required int limit,
}) {
  final matchQuery = buildRagLexicalQuery(query);
  if (matchQuery.isEmpty) {
    return const [];
  }
  final rows = database.select(
    'SELECT object_id, chunk_id FROM knowledge '
    'WHERE knowledge MATCH ? ORDER BY bm25(knowledge), object_id LIMIT ?',
    [matchQuery, limit],
  );
  return [
    for (final row in rows)
      {
        'objectId': row['object_id'] as String,
        'chunkId': row['chunk_id'] as String,
      },
  ];
}

String buildRagLexicalQuery(String query) {
  return query
      .split(RegExp(r'\s+'))
      .where((term) => term.trim().isNotEmpty)
      .map((term) => '"${term.replaceAll('"', '""')}"')
      .join(' ');
}

Future<List<RagFixtureDocument>> loadRagFixtureDocuments(
  RagRetrievalFixture fixture,
) async {
  final root = Directory(
    '${fixture.sourceFile.parent.path}/${fixture.corpusRoot}',
  );
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      RagFixtureDocument(
        objectId: file.path.substring(root.path.length + 1),
        chunkId: '${file.path.substring(root.path.length + 1)}#1',
        content: await _readFixtureContent(file),
      ),
  ];
}

Future<String> _readFixtureContent(File file) async {
  final source = await file.readAsString();
  if (!file.path.endsWith('.json')) {
    return source;
  }
  final decoded = jsonDecode(source);
  return _flattenJsonStrings(decoded).join('\n');
}

Iterable<String> _flattenJsonStrings(Object? value) sync* {
  switch (value) {
    case String text:
      yield text;
    case Map values:
      for (final item in values.values) {
        yield* _flattenJsonStrings(item);
      }
    case List values:
      for (final item in values) {
        yield* _flattenJsonStrings(item);
      }
  }
}

Map<String, Object?> _caseResult(
  RagRetrievalFixtureCase fixtureCase, {
  required List<Map<String, Object?>> hits,
  required String context,
  int latencyMs = 0,
  String? missReason,
}) {
  final result = <String, Object?>{
    'caseId': fixtureCase.id,
    'hits': hits,
    'latencyMs': latencyMs,
    'promptTokens': estimateRagTokens(fixtureCase.query),
    'contextTokens': estimateRagTokens(context),
  };
  if (missReason != null) {
    result['missReason'] = missReason;
  }
  return result;
}

Map<String, Object?> _availableArm(
  String id,
  List<Map<String, Object?>> results, {
  required Map<String, Object?> resource,
  bool negativeControl = false,
  double minimumHitAtK = 0,
}) {
  return {
    'id': id,
    'status': 'available',
    'negativeControl': negativeControl,
    'minimumHitAtK': minimumHitAtK,
    'resource': resource,
    'results': results,
  };
}

Map<String, Object?> _unavailableArm(String id, String reason) {
  return {
    'id': id,
    'status': 'not_available',
    'unavailableReason': reason,
    'results': <Object?>[],
  };
}

String _contentForHits(
  List<RagFixtureDocument> documents,
  List<Map<String, Object?>> hits,
) {
  final byId = {for (final document in documents) document.objectId: document};
  return hits
      .map((hit) => byId[hit['objectId']]?.content)
      .whereType<String>()
      .join('\n');
}

int estimateRagTokens(String text) => (text.runes.length / 4).ceil();

int _elapsedMilliseconds(Stopwatch stopwatch) {
  if (stopwatch.elapsedMicroseconds == 0) {
    return 0;
  }
  return (stopwatch.elapsedMicroseconds / 1000).ceil();
}

final class RagFixtureDocument {
  const RagFixtureDocument({
    required this.objectId,
    required this.chunkId,
    required this.content,
  });

  final String objectId;
  final String chunkId;
  final String content;

  Map<String, Object?> toHit() => {'objectId': objectId, 'chunkId': chunkId};
}

final class RagRetrievalBaselineMetadata {
  const RagRetrievalBaselineMetadata({
    required this.buildCommit,
    required this.buildDirty,
    required this.hardware,
  });

  final String buildCommit;
  final bool buildDirty;
  final String hardware;

  static Future<RagRetrievalBaselineMetadata> fromWorkspace() async {
    final commit = await Process.run('git', ['rev-parse', 'HEAD']);
    final status = await Process.run('git', ['status', '--porcelain']);
    if (commit.exitCode != 0 || status.exitCode != 0) {
      throw StateError('Unable to capture Git build identity.');
    }
    return RagRetrievalBaselineMetadata(
      buildCommit: '${commit.stdout}'.trim(),
      buildDirty: '${status.stdout}'.trim().isNotEmpty,
      hardware:
          '${Platform.operatingSystem}/${Platform.numberOfProcessors}/'
          '${Platform.version.split(' ').first}',
    );
  }
}

final class RagRetrievalBaselineOptions {
  const RagRetrievalBaselineOptions({
    required this.fixturePath,
    required this.outDir,
    required this.runId,
    required this.warmState,
  });

  final String fixturePath;
  final String outDir;
  final String runId;
  final String warmState;

  static RagRetrievalBaselineOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length || !args[index].startsWith('--')) {
        return null;
      }
      values[args[index]] = args[index + 1];
    }
    const supported = {'--fixture', '--out-dir', '--run-id', '--warm-state'};
    if (!supported.containsAll(values.keys)) {
      return null;
    }
    final fixture = values['--fixture'];
    final output = values['--out-dir'];
    final warmState = values['--warm-state'] ?? 'cold';
    if (fixture == null ||
        output == null ||
        !{'cold', 'warm'}.contains(warmState)) {
      return null;
    }
    return RagRetrievalBaselineOptions(
      fixturePath: fixture,
      outDir: output,
      runId: values['--run-id'] ?? 'rag1-baseline-v1',
      warmState: warmState,
    );
  }
}
