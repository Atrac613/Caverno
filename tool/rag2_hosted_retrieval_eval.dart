import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'rag2_drift_additive_schema_replay.dart';
import 'rag2_drift_dao_generation_store.dart';
import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_knowledge_object_replay.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag2_storage_replay.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2HostedRetrievalEvalContract =
    'rag2-hosted-retrieval-eval-contract-v1';
const rag2HostedRetrievalEvalReportSchema =
    'caverno_rag2_hosted_retrieval_eval_report';
const rag2HostedRetrievalEvalProjectId = 'rag2-hosted-retrieval-eval-project';
const rag2HostedRetrievalCandidate = 'trigram_or_idf';
const rag2HostedRetrievalThreshold = 0.15;
const rag2HostedRetrievalMinimumAnswerableHits = 15;
const rag2HostedRetrievalRequiredJapaneseHits = 4;
const rag2HostedRetrievalMaximumNoAnswerRetrieved = 1;

Future<void> main(List<String> args) async {
  final options = Rag2HostedRetrievalEvalOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_hosted_retrieval_eval.dart '
      '--fixture PATH --out-dir PATH [--store-root PATH]',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2HostedRetrievalEval(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 hosted retrieval evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2HostedRetrievalEvalReport> runRag2HostedRetrievalEval(
  Rag2HostedRetrievalEvalOptions options, {
  String? buildCommit,
  bool? buildDirty,
}) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await RagRetrievalFixture.load(fixtureFile);
  fixture.validate();
  final corpusHash = await fixture.computeCorpusHash();
  if (corpusHash != fixture.corpusHash) {
    throw StateError(
      'Fixture corpus hash mismatch: expected ${fixture.corpusHash}, '
      'found $corpusHash.',
    );
  }
  final gitState = buildCommit == null || buildDirty == null
      ? await _readGitState()
      : null;
  final resolvedCommit = buildCommit ?? gitState!.$1;
  final resolvedDirty = buildDirty ?? gitState!.$2;
  final snapshot = await buildRag2HostedRetrievalSnapshot(fixture);
  final declarationIdentity = rag2ExplicitSourceRootsDeclarationIdentity(const [
    'docs',
    'lib',
  ]);
  final storeDirectory = _freshDirectory(options.storeRoot);
  final databasePath = '${storeDirectory.path}/caverno.sqlite';
  await prepareRag2DriftHost(databasePath: databasePath, seedEmbedding: true);
  final store = Rag2DriftDaoGenerationStore.open(
    databasePath: databasePath,
    projectId: rag2HostedRetrievalEvalProjectId,
  );
  try {
    final applyResult = await store.apply(
      declarationIdentity: declarationIdentity,
      snapshot: snapshot,
      indexSearch: true,
    );
    if (applyResult.decision != 'applied') {
      throw StateError(
        'Hosted retrieval fixture expected an applied generation, got '
        '${applyResult.decision}.',
      );
    }
    final generation = await store.read(declarationIdentity);
    if (generation == null) {
      throw StateError('Hosted retrieval generation did not reopen.');
    }
    final scorer = _Rag2HostedCandidateScorer(
      store: store,
      fixture: fixture,
      generation: generation,
      declarationIdentity: declarationIdentity,
    );
    final candidateCases = <Rag2HostedRetrievalCaseResult>[];
    var provenanceValidated = true;
    for (final fixtureCase in fixture.cases) {
      final result = await scorer.evaluate(fixtureCase);
      candidateCases.add(result);
      provenanceValidated = provenanceValidated && result.provenanceValidated;
    }
    final resource = <String, Object?>{
      'peakRssBytes': ProcessInfo.currentRss,
      'peakVramBytes': null,
    };
    final run = RagRetrievalRun.fromJson({
      'schemaName': ragRetrievalRunSchema,
      'schemaVersion': ragRetrievalSchemaVersion,
      'runId': 'rag2-hosted-retrieval-${_shortRevision(resolvedCommit)}',
      'fixtureId': fixture.fixtureId,
      'metadata': {
        'buildCommit': resolvedCommit,
        'buildDirty': resolvedDirty,
        'embeddingFingerprint': 'not_available',
        'hardware':
            '${Platform.operatingSystem}/${Platform.numberOfProcessors}',
        'warmState': 'cold',
        'tokenEstimateMethod': 'unicode_code_points_div_4_v1',
        'lexicalTokenizer': 'dart_trigram_pretokenized_unicode61',
        'lexicalQueryPolicy': rag2HostedRetrievalCandidate,
        'lexicalThreshold': rag2HostedRetrievalThreshold,
      },
      'arms': [
        _availableArm('L', [
          for (final item in candidateCases) item.toRag1Result(),
        ], resource: resource),
        _unavailableArm('V', 'Vector retrieval is outside this slice.'),
        _unavailableArm('H', 'Vector retrieval is outside this slice.'),
        _unavailableArm('AK', 'agent-kb provenance gates remain unsatisfied.'),
        _unavailableArm('H+AK', 'Federated retrieval is outside this slice.'),
        _availableArm('NONE', [
          for (final item in fixture.cases) _emptyResult(item),
        ], resource: resource),
        _availableArm('FULL', [
          for (final item in fixture.cases)
            _fullContextResult(item, snapshot.objects),
        ], resource: resource),
        _availableArm(
          'NEG-EMPTY',
          [for (final item in fixture.cases) _emptyResult(item)],
          resource: resource,
          negativeControl: true,
          minimumHitAtK: 0.05,
        ),
      ],
    });
    final rag1Report = await evaluateRagRetrievalRun(
      fixture: fixture,
      run: run,
    );
    final lexical = rag1Report.arms.singleWhere((item) => item['id'] == 'L');
    final aggregate = (lexical['aggregate'] as Map).cast<String, Object?>();
    final category = (aggregate['categoryBreakdown'] as Map)
        .cast<String, Object?>();
    final japanese = (category['japanese_query'] as Map)
        .cast<String, Object?>();
    final schemaVersion = await store.database
        .customSelect('PRAGMA user_version')
        .getSingle();
    final conversationSearch = await store.database
        .customSelect('SELECT count(*) AS count FROM conversation_search')
        .getSingle();
    final embeddings = await store.database
        .select(store.database.embeddings)
        .get();
    final hostPreserved =
        schemaVersion.read<int>('user_version') == 5 &&
        conversationSearch.read<int>('count') == 1 &&
        embeddings.length == 1;
    final gate = Rag2HostedRetrievalGate.evaluate(
      answerableHits: aggregate['answerableHitCount'] as int,
      japaneseHits: japanese['hitCount'] as int,
      noAnswerRetrieved: aggregate['unanswerableRetrievedCount'] as int,
      provenanceValidated: provenanceValidated,
      negativeControlPassed: rag1Report.negativeControlsPassed,
      hostPreserved: hostPreserved,
    );
    final report = Rag2HostedRetrievalEvalReport(
      fixtureId: fixture.fixtureId,
      corpusHash: corpusHash,
      declarationIdentity: declarationIdentity,
      generation: generation.generation,
      snapshotHash: generation.snapshot.snapshotHash,
      buildCommit: resolvedCommit,
      buildDirty: resolvedDirty,
      candidateCases: candidateCases,
      rag1Report: rag1Report,
      gate: gate,
      appDatabaseSchemaVersion: schemaVersion.read<int>('user_version'),
      hostPreserved: hostPreserved,
    );
    final output = Directory(options.outDir);
    await output.create(recursive: true);
    await File('${output.path}/rag2_hosted_retrieval_eval.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
    );
    await File(
      '${output.path}/rag2_hosted_retrieval_eval.md',
    ).writeAsString(report.toMarkdown());
    return report;
  } finally {
    await store.close();
  }
}

Future<Rag2KnowledgeSnapshot> buildRag2HostedRetrievalSnapshot(
  RagRetrievalFixture fixture,
) async {
  final documents = await loadRagFixtureDocuments(fixture);
  final objects = <Rag2KnowledgeObject>[];
  for (final document in documents) {
    final path = document.objectId;
    validateRag2RepoRelativePath(path);
    final content = _normalizeText(document.content);
    final contentHash = _sha256(content);
    final objectId = rag2KnowledgeObjectId(
      projectId: rag2HostedRetrievalEvalProjectId,
      repoRelativePath: path,
    );
    final locator = 'rag1:$path';
    final chunkId = rag2KnowledgeChunkId(
      objectId: objectId,
      locator: locator,
      contentHash: contentHash,
    );
    final lineCount = content.isEmpty ? 1 : '\n'.allMatches(content).length + 1;
    final provenance = Rag2KnowledgeProvenance(
      projectId: rag2HostedRetrievalEvalProjectId,
      repoRelativePath: path,
      revision: 'fixture:${fixture.corpusHash}',
      objectContentHash: contentHash,
      lineStart: 1,
      lineEnd: lineCount,
      sourceTrust: 'fixture_attested',
    );
    final chunk = Rag2KnowledgeChunk(
      chunkId: chunkId,
      objectId: objectId,
      locator: locator,
      contentHash: contentHash,
      content: content,
      passageRole: 'unknown',
      provenance: provenance,
    );
    objects.add(
      Rag2KnowledgeObject(
        objectId: objectId,
        projectId: rag2HostedRetrievalEvalProjectId,
        repoRelativePath: path,
        sourceKind: path.endsWith('.dart') ? 'dart' : 'document',
        sourceTrust: provenance.sourceTrust,
        revision: provenance.revision,
        contentHash: contentHash,
        chunkIds: [chunkId],
        chunks: [chunk],
      ),
    );
  }
  return Rag2KnowledgeSnapshot(
    snapshotId: '${fixture.fixtureId}-hosted-v1',
    snapshotHash: rag2KnowledgeSnapshotHash(objects),
    objects: List.unmodifiable(objects),
  );
}

final class _Rag2HostedCandidateScorer {
  _Rag2HostedCandidateScorer({
    required this.store,
    required this.fixture,
    required this.generation,
    required this.declarationIdentity,
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
  final RagRetrievalFixture fixture;
  final Rag2StoredGeneration generation;
  final String declarationIdentity;
  final Map<String, Rag2KnowledgeChunk> _chunks;
  final Map<String, Set<String>> _documentTerms;
  final Map<String, int> _documentFrequency = {};

  Future<Rag2HostedRetrievalCaseResult> evaluate(
    RagRetrievalFixtureCase fixtureCase,
  ) async {
    final queryTerms = tokenizeRag2Lexical(
      fixtureCase.query,
      Rag2LexicalPolicy.trigram,
    );
    if (queryTerms.isEmpty) {
      return Rag2HostedRetrievalCaseResult(
        caseId: fixtureCase.id,
        hits: const [],
        topCoverage: null,
        relevantRank: null,
        contextTokens: 0,
        missReason: fixtureCase.category == 'japanese_query'
            ? 'tokenization'
            : null,
        provenanceValidated: true,
      );
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
          'SELECT chunk_id, object_id, content, '
          'bm25(${AppDatabase.rag2ChunkSearchTable}) AS rank '
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
            Variable<int>(fixture.metricK * 8),
          ],
        )
        .get();
    final seen = <String>{};
    final retained = <Rag2HostedRetrievalHit>[];
    var provenanceValidated = true;
    for (final row in rows) {
      final chunkId = row.read<String>('chunk_id');
      final chunk = _chunks[chunkId];
      if (chunk == null || !seen.add(chunkId)) {
        provenanceValidated = false;
        break;
      }
      final expectedTerms = _documentTerms[chunkId]!;
      final expectedContent = expectedTerms.toList()..sort();
      final storedTokens = row.read<String>('content').split(' ');
      final normalizedStored = [...storedTokens]..sort();
      final valid =
          row.read<String>('object_id') == chunk.objectId &&
          normalizedStored.join('\u0000') == expectedContent.join('\u0000') &&
          chunk.provenance.projectId == rag2HostedRetrievalEvalProjectId &&
          chunk.provenance.repoRelativePath.isNotEmpty;
      if (!valid) {
        provenanceValidated = false;
        break;
      }
      final overlap = queryTerms.intersection(expectedTerms);
      final coverage =
          overlap.fold<double>(0, (sum, term) => sum + _idf(term)) /
          denominator;
      if (coverage < rag2HostedRetrievalThreshold) {
        continue;
      }
      retained.add(
        Rag2HostedRetrievalHit(
          objectId: chunk.provenance.repoRelativePath,
          chunkId: '${chunk.provenance.repoRelativePath}#1',
          coverage: coverage,
          content: chunk.content,
        ),
      );
      if (retained.length == fixture.metricK) {
        break;
      }
    }
    if (!provenanceValidated) {
      retained.clear();
    }
    final relevantRank = retained.indexWhere(
      (hit) => fixtureCase.objectRelevance.containsKey(hit.objectId),
    );
    final context = retained.map((item) => item.content).join('\n');
    return Rag2HostedRetrievalCaseResult(
      caseId: fixtureCase.id,
      hits: List.unmodifiable(retained),
      topCoverage: retained.isEmpty ? null : retained.first.coverage,
      relevantRank: relevantRank < 0 ? null : relevantRank + 1,
      contextTokens: _estimateTokens(context),
      missReason: fixtureCase.category == 'japanese_query' && relevantRank < 0
          ? (retained.isEmpty ? 'tokenization' : 'ranking')
          : null,
      provenanceValidated: provenanceValidated,
    );
  }

  double _idf(String term) =>
      math.log(
        (_documentTerms.length + 1) / ((_documentFrequency[term] ?? 0) + 1),
      ) +
      1;
}

final class Rag2HostedRetrievalHit {
  const Rag2HostedRetrievalHit({
    required this.objectId,
    required this.chunkId,
    required this.coverage,
    required this.content,
  });

  final String objectId;
  final String chunkId;
  final double coverage;
  final String content;

  Map<String, Object?> toRag1Hit() => {
    'objectId': objectId,
    'chunkId': chunkId,
  };
}

final class Rag2HostedRetrievalCaseResult {
  const Rag2HostedRetrievalCaseResult({
    required this.caseId,
    required this.hits,
    required this.topCoverage,
    required this.relevantRank,
    required this.contextTokens,
    required this.missReason,
    required this.provenanceValidated,
  });

  final String caseId;
  final List<Rag2HostedRetrievalHit> hits;
  final double? topCoverage;
  final int? relevantRank;
  final int contextTokens;
  final String? missReason;
  final bool provenanceValidated;

  Map<String, Object?> toRag1Result() {
    final result = <String, Object?>{
      'caseId': caseId,
      'hits': [for (final hit in hits) hit.toRag1Hit()],
      'latencyMs': 0,
      'promptTokens': 0,
      'completionTokens': 0,
      'contextTokens': contextTokens,
    };
    if (missReason != null) {
      result['missReason'] = missReason;
    }
    return result;
  }

  Map<String, Object?> toAggregateJson() => {
    'caseId': caseId,
    'returnedHitCount': hits.length,
    'topCoverage': topCoverage,
    'relevantRank': relevantRank,
    'contextTokens': contextTokens,
    'provenanceValidated': provenanceValidated,
  };
}

final class Rag2HostedRetrievalGate {
  const Rag2HostedRetrievalGate({
    required this.answerableHits,
    required this.japaneseHits,
    required this.noAnswerRetrieved,
    required this.provenanceValidated,
    required this.negativeControlPassed,
    required this.hostPreserved,
  });

  final int answerableHits;
  final int japaneseHits;
  final int noAnswerRetrieved;
  final bool provenanceValidated;
  final bool negativeControlPassed;
  final bool hostPreserved;

  factory Rag2HostedRetrievalGate.evaluate({
    required int answerableHits,
    required int japaneseHits,
    required int noAnswerRetrieved,
    required bool provenanceValidated,
    required bool negativeControlPassed,
    required bool hostPreserved,
  }) => Rag2HostedRetrievalGate(
    answerableHits: answerableHits,
    japaneseHits: japaneseHits,
    noAnswerRetrieved: noAnswerRetrieved,
    provenanceValidated: provenanceValidated,
    negativeControlPassed: negativeControlPassed,
    hostPreserved: hostPreserved,
  );

  bool get passed =>
      answerableHits >= rag2HostedRetrievalMinimumAnswerableHits &&
      japaneseHits == rag2HostedRetrievalRequiredJapaneseHits &&
      noAnswerRetrieved <= rag2HostedRetrievalMaximumNoAnswerRetrieved &&
      provenanceValidated &&
      negativeControlPassed &&
      hostPreserved;

  Map<String, Object?> toJson() => {
    'decision': passed ? 'go' : 'no_go',
    'answerableHits': answerableHits,
    'answerableCases': 16,
    'minimumAnswerableHits': rag2HostedRetrievalMinimumAnswerableHits,
    'japaneseHits': japaneseHits,
    'japaneseCases': 4,
    'requiredJapaneseHits': rag2HostedRetrievalRequiredJapaneseHits,
    'noAnswerRetrieved': noAnswerRetrieved,
    'noAnswerCases': 4,
    'maximumNoAnswerRetrieved': rag2HostedRetrievalMaximumNoAnswerRetrieved,
    'provenanceValidated': provenanceValidated,
    'negativeControlPassed': negativeControlPassed,
    'hostPreserved': hostPreserved,
  };
}

final class Rag2HostedRetrievalEvalReport {
  const Rag2HostedRetrievalEvalReport({
    required this.fixtureId,
    required this.corpusHash,
    required this.declarationIdentity,
    required this.generation,
    required this.snapshotHash,
    required this.buildCommit,
    required this.buildDirty,
    required this.candidateCases,
    required this.rag1Report,
    required this.gate,
    required this.appDatabaseSchemaVersion,
    required this.hostPreserved,
  });

  final String fixtureId;
  final String corpusHash;
  final String declarationIdentity;
  final int generation;
  final String snapshotHash;
  final String buildCommit;
  final bool buildDirty;
  final List<Rag2HostedRetrievalCaseResult> candidateCases;
  final RagRetrievalReport rag1Report;
  final Rag2HostedRetrievalGate gate;
  final int appDatabaseSchemaVersion;
  final bool hostPreserved;

  Map<String, Object?> toJson() => {
    'schemaName': rag2HostedRetrievalEvalReportSchema,
    'schemaVersion': 1,
    'contract': rag2HostedRetrievalEvalContract,
    'evaluationMode': 'appdatabase_hosted_offline_retrieval',
    'contractDecision': 'go',
    'candidateDecision': gate.passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'rag3Decision': 'no_go',
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'candidate': rag2HostedRetrievalCandidate,
    'threshold': rag2HostedRetrievalThreshold,
    'declarationIdentity': declarationIdentity,
    'generation': generation,
    'snapshotHash': snapshotHash,
    'buildCommit': buildCommit,
    'buildDirty': buildDirty,
    'appDatabaseSchemaVersion': appDatabaseSchemaVersion,
    'hostPreserved': hostPreserved,
    'gate': gate.toJson(),
    'cases': [for (final item in candidateCases) item.toAggregateJson()],
    'rag1Evaluation': rag1Report.toJson(),
  };

  String toMarkdown() {
    final lexical = rag1Report.arms.singleWhere((item) => item['id'] == 'L');
    final aggregate = (lexical['aggregate'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# RAG2 Hosted Retrieval Evaluation')
      ..writeln()
      ..writeln('- Contract: `$rag2HostedRetrievalEvalContract`')
      ..writeln('- Contract decision: `go`')
      ..writeln('- Candidate decision: `${gate.passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Fixture: `$fixtureId`')
      ..writeln('- Corpus SHA-256: `$corpusHash`')
      ..writeln('- Candidate: `$rag2HostedRetrievalCandidate`')
      ..writeln('- Threshold: `$rag2HostedRetrievalThreshold`')
      ..writeln('- AppDatabase schema version: `$appDatabaseSchemaVersion`')
      ..writeln()
      ..writeln('| Gate | Result | Required |')
      ..writeln('| --- | ---: | ---: |')
      ..writeln(
        '| Answerable hits | ${gate.answerableHits}/16 | '
        '>=$rag2HostedRetrievalMinimumAnswerableHits/16 |',
      )
      ..writeln(
        '| Japanese hits | ${gate.japaneseHits}/4 | '
        '$rag2HostedRetrievalRequiredJapaneseHits/4 |',
      )
      ..writeln(
        '| No-answer retrieved | ${gate.noAnswerRetrieved}/4 | '
        '<=$rag2HostedRetrievalMaximumNoAnswerRetrieved/4 |',
      )
      ..writeln(
        '| Provenance validation | ${gate.provenanceValidated} | true |',
      )
      ..writeln(
        '| Empty negative control | ${gate.negativeControlPassed} | true |',
      )
      ..writeln('| Existing host preserved | $hostPreserved | true |')
      ..writeln()
      ..writeln('## Retrieval metrics')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('| --- | ---: |')
      ..writeln('| MRR@5 | ${aggregate['objectMrrAtK']} |')
      ..writeln('| nDCG@5 | ${aggregate['objectNdcgAtK']} |')
      ..writeln('| Context tokens | ${aggregate['totalContextTokens']} |')
      ..writeln()
      ..writeln(
        gate.passed
            ? 'The frozen candidate clears the offline retrieval gate. '
                  'Production remains No-Go pending the separately roadmapped '
                  'answerability and application-wiring gates.'
            : 'The frozen candidate does not clear the offline retrieval gate. '
                  'Do not add production retrieval, prompt injection, or RAG3 '
                  'wiring from this result.',
      );
    return buffer.toString();
  }
}

final class Rag2HostedRetrievalEvalOptions {
  const Rag2HostedRetrievalEvalOptions({
    required this.fixturePath,
    required this.outDir,
    required this.storeRoot,
  });

  final String fixturePath;
  final String outDir;
  final String storeRoot;

  static Rag2HostedRetrievalEvalOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length ||
          !{'--fixture', '--out-dir', '--store-root'}.contains(args[index])) {
        return null;
      }
      values[args[index]] = args[index + 1];
    }
    final fixturePath = values['--fixture'];
    final outDir = values['--out-dir'];
    final storeRoot = values['--store-root'];
    if (fixturePath == null || outDir == null) {
      return null;
    }
    return Rag2HostedRetrievalEvalOptions(
      fixturePath: fixturePath,
      outDir: outDir,
      storeRoot: storeRoot ?? '$outDir/store',
    );
  }
}

Map<String, Object?> _availableArm(
  String id,
  List<Map<String, Object?>> results, {
  required Map<String, Object?> resource,
  bool negativeControl = false,
  double minimumHitAtK = 0,
}) => {
  'id': id,
  'status': 'available',
  'negativeControl': negativeControl,
  'minimumHitAtK': minimumHitAtK,
  'resource': resource,
  'results': results,
};

Map<String, Object?> _unavailableArm(String id, String reason) => {
  'id': id,
  'status': 'not_available',
  'unavailableReason': reason,
  'results': <Object?>[],
};

Map<String, Object?> _emptyResult(RagRetrievalFixtureCase fixtureCase) => {
  'caseId': fixtureCase.id,
  'hits': <Object?>[],
  'latencyMs': 0,
  'promptTokens': 0,
  'completionTokens': 0,
  'contextTokens': 0,
};

Map<String, Object?> _fullContextResult(
  RagRetrievalFixtureCase fixtureCase,
  List<Rag2KnowledgeObject> objects,
) {
  final context = objects.map((item) => item.chunks.single.content).join('\n');
  return {
    'caseId': fixtureCase.id,
    'hits': [
      for (final object in objects)
        {
          'objectId': object.repoRelativePath,
          'chunkId': '${object.repoRelativePath}#1',
        },
    ],
    'latencyMs': 0,
    'promptTokens': 0,
    'completionTokens': 0,
    'contextTokens': _estimateTokens(context),
  };
}

Future<(String, bool)> _readGitState() async {
  final revision = await Process.run('git', const ['rev-parse', 'HEAD']);
  final status = await Process.run('git', const ['status', '--porcelain']);
  if (revision.exitCode != 0 || status.exitCode != 0) {
    throw StateError('Unable to capture Git build identity.');
  }
  return (
    (revision.stdout as String).trim(),
    (status.stdout as String).isNotEmpty,
  );
}

Directory _freshDirectory(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
  directory.createSync(recursive: true);
  return directory;
}

String _normalizeText(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

String _shortRevision(String value) =>
    value.length <= 12 ? value : value.substring(0, 12);

int _estimateTokens(String value) => (value.runes.length / 4).ceil();
