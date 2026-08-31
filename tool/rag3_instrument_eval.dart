import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'rag2_hosted_retrieval_eval.dart';
import 'rag2_passage_role_eval.dart';
import 'rag3_candidate_run_producer.dart';
import 'rag3_offline_hybrid_eval.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag3InstrumentReportSchema = 'caverno_rag3_instrument_eval_report';
const rag3InstrumentContract = 'rag3-instrument-eval-v1';
const rag3InstrumentVectorReason = 'instrument_vector_not_captured';

Future<void> main(List<String> args) async {
  final options = Rag3InstrumentEvalOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag3_instrument_eval.dart '
      '--rag1-fixture PATH --rag2-fixture PATH --rag2-fixture PATH '
      '--passage-role-oracle PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag3InstrumentEval(options);
    stdout.write(report.toMarkdown());
    if (!report.instrumentValidated) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('RAG3 instrument evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag3InstrumentReport> runRag3InstrumentEval(
  Rag3InstrumentEvalOptions options, {
  String? buildCommit,
  bool? buildDirty,
}) async {
  if (options.allFixturePaths.any(_isPromotionPath) ||
      _isPromotionPath(options.passageRoleOraclePath)) {
    throw StateError('RAG3 instrument inputs cannot use promotion artifacts.');
  }
  final gitState = buildCommit == null || buildDirty == null
      ? await _readGitState()
      : null;
  final resolvedCommit = buildCommit ?? gitState!.$1;
  final resolvedDirty = buildDirty ?? gitState!.$2;
  final output = Directory(options.outDir);
  await output.create(recursive: true);
  final passageRoleOracle = await Rag2PassageRoleOracle.load(
    File(options.passageRoleOraclePath),
  );
  final results = <Rag3InstrumentDatasetResult>[];
  for (final fixturePath in options.allFixturePaths) {
    final fixture = await RagRetrievalFixture.load(File(fixturePath));
    fixture.validate();
    final isRag1 = fixturePath == options.rag1FixturePath;
    final datasetOracle = isRag1
        ? null
        : passageRoleOracle.dataset(fixture.fixtureId);
    final datasetOutput = Directory('${output.path}/${fixture.fixtureId}');
    final hosted = await runRag2HostedRetrievalEval(
      Rag2HostedRetrievalEvalOptions(
        fixturePath: fixturePath,
        outDir: '${datasetOutput.path}/hosted',
        storeRoot: '${datasetOutput.path}/store',
      ),
      buildCommit: resolvedCommit,
      buildDirty: resolvedDirty,
    );
    final documents = await loadRagFixtureDocuments(fixture);
    if (datasetOracle != null) {
      datasetOracle.validate(
        fixture,
        hosted.corpusHash,
        documents.map((item) => item.objectId).toSet(),
      );
    }
    final rag3Fixture = adaptRag3InstrumentFixture(
      fixture: fixture,
      documents: documents,
      passageRoleOracle: datasetOracle,
    );
    final hostedCases = {
      for (final item in hosted.candidateCases) item.caseId: item,
    };
    final fingerprint = Rag3VectorFingerprint(
      schemaVersion: 1,
      endpointIdentity: Rag3VectorFingerprint.normalizeEndpointIdentity(
        'https://not-available.invalid/v1/embeddings',
      ),
      requestedModelId: 'not-available',
      responseModelId: 'not-available',
      dimension: 1,
    );
    final runJson = const Rag3CandidateRunProducer().produce(
      fixture: rag3Fixture,
      runId: 'rag3-instrument-${fixture.fixtureId}',
      metadata: {
        'buildCommit': resolvedCommit,
        'buildDirty': resolvedDirty,
        'hardware':
            '${Platform.operatingSystem}/${Platform.numberOfProcessors}',
        'warmState': 'cold',
        'tokenEstimateMethod': 'unicode_code_points_div_4_v1',
      },
      cases: [
        for (final fixtureCase in fixture.cases)
          Rag3CandidateCaseInput(
            caseId: fixtureCase.id,
            submitted: true,
            lexicalRankedChunkIds: [
              for (final hit in hostedCases[fixtureCase.id]!.hits) hit.chunkId,
            ],
            vector: Rag3VectorRankingInput.unavailable(
              fingerprint: fingerprint,
              reason: rag3InstrumentVectorReason,
            ),
            lexicalLatencyMs: hostedCases[fixtureCase.id]!.latencyMs,
            peakRssBytes: ProcessInfo.currentRss,
            peakVramBytes: 0,
          ),
      ],
    );
    final run = Rag3CandidateRun.fromJson(runJson);
    final report = evaluateRag3HybridRun(fixture: rag3Fixture, run: run);
    await datasetOutput.create(recursive: true);
    await _writeJson(
      File('${datasetOutput.path}/rag3_instrument_run.json'),
      runJson,
    );
    await _writeJson(
      File('${datasetOutput.path}/rag3_instrument_eval.json'),
      report.toJson(),
    );
    results.add(
      Rag3InstrumentDatasetResult(
        sourceFixtureId: fixture.fixtureId,
        sourceCorpusHash: hosted.corpusHash,
        passageRoleOracleApplied: datasetOracle != null,
        hostedProvenanceValidated: hosted.candidateCases.every(
          (item) => item.provenanceValidated,
        ),
        hostedAppDatabasePreserved: hosted.hostPreserved,
        report: report,
      ),
    );
  }
  final report = Rag3InstrumentReport(
    buildCommit: resolvedCommit,
    buildDirty: resolvedDirty,
    datasets: List.unmodifiable(results),
  );
  await _writeJson(
    File('${output.path}/rag3_instrument_eval.json'),
    report.toJson(),
  );
  await File(
    '${output.path}/rag3_instrument_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag3HybridFixture adaptRag3InstrumentFixture({
  required RagRetrievalFixture fixture,
  required List<RagFixtureDocument> documents,
  required Rag2PassageRoleDatasetOracle? passageRoleOracle,
}) {
  final objects = <String, Rag3KnowledgeObject>{};
  for (final document in documents) {
    final content = _normalizeText(document.content);
    final lines = content.split('\n');
    final contentHash = _sha256(content);
    objects[document.objectId] = Rag3KnowledgeObject(
      id: document.objectId,
      sourcePath: document.objectId,
      revision: 'fixture:${fixture.corpusHash}',
      objectContentHash: contentHash,
      sourceTrust: 'fixture_attested',
      authority: 'instrument',
      sourceLines: List.unmodifiable(lines),
      chunks: [
        Rag3Chunk(
          id: document.chunkId,
          objectId: document.objectId,
          lineStart: 1,
          lineEnd: lines.length,
          contentHash: contentHash,
        ),
      ],
    );
  }
  const budgetProbeId = 'instrument/budget_probe.txt';
  final budgetProbe = List.filled(25000, 'x').join();
  objects[budgetProbeId] = Rag3KnowledgeObject(
    id: budgetProbeId,
    sourcePath: budgetProbeId,
    revision: 'instrument:budget-negative-control-v1',
    objectContentHash: _sha256(budgetProbe),
    sourceTrust: 'synthetic_negative_control',
    authority: 'instrument',
    sourceLines: [budgetProbe],
    chunks: [
      Rag3Chunk(
        id: '$budgetProbeId#1',
        objectId: budgetProbeId,
        lineStart: 1,
        lineEnd: 1,
        contentHash: _sha256(budgetProbe),
      ),
    ],
  );
  final corpusHash = _sha256(
    '$rag3InstrumentContract\u0000${fixture.corpusHash}\u0000'
    '${_sha256(budgetProbe)}',
  );
  final fixtureCases = <Map<String, Object?>>[];
  final oracleCases = <Map<String, Object?>>[];
  for (final fixtureCase in fixture.cases) {
    final expectedRole = fixtureCase.answerFacts.isNotEmpty
        ? 'answer_support'
        : fixtureCase.citations.isNotEmpty
        ? 'abstention_support'
        : 'no_evidence';
    final strata = <String>{fixtureCase.category, fixtureCase.authority};
    if (fixtureCase.answerFacts.isNotEmpty) {
      strata.add('answerable');
    } else if (fixtureCase.citations.isNotEmpty) {
      strata.add('abstention');
    } else {
      strata.add('unavailable');
    }
    fixtureCases.add({
      'id': fixtureCase.id,
      'language': fixtureCase.category == 'japanese_query' ? 'ja' : 'en',
      'shouldSearch': true,
      'strata': strata.toList()..sort(),
    });
    final roles = <String, String>{};
    for (final document in documents) {
      final role = passageRoleOracle?.roleFor(
        fixtureCase.id,
        document.objectId,
      );
      final resolvedRole =
          role?.id ??
          (fixtureCase.objectRelevance.containsKey(document.objectId)
              ? expectedRole
              : 'irrelevant');
      if (resolvedRole != 'irrelevant') {
        roles[document.chunkId] = resolvedRole;
      }
    }
    oracleCases.add({
      'id': fixtureCase.id,
      'qrels': {
        'objects': fixtureCase.objectRelevance,
        'chunks': fixtureCase.chunkRelevance,
      },
      'expectedEvidenceRole': expectedRole,
      'passageRoles': roles,
    });
  }
  return Rag3HybridFixture.fromJson(
    fixtureJson: {
      'schemaName': rag3FixtureSchema,
      'schemaVersion': rag3SchemaVersion,
      'contractId': rag3ContractId,
      'fixtureId': 'instrument-${fixture.fixtureId}',
      'corpusHash': corpusHash,
      'selectionPolicy': {
        'contextBudgetTokens': rag3ContextBudgetTokens,
        'maxGroupsPerObject': rag3MaxGroupsPerObject,
        'estimatedRunesPerToken': 4,
        'citationFormatVersion': 'rag3-citation-v1',
      },
      'negativeControls': const [
        {
          'id': 'empty-shuffled-fusion',
          'expectedOutcome': 'fails_quality_gate',
        },
        {
          'id': 'budget-bypass',
          'expectedOutcome': 'fails_zero_budget_violation_gate',
        },
      ],
      'cases': fixtureCases,
    },
    oracleJson: {
      'schemaName': rag3OracleSchema,
      'schemaVersion': rag3SchemaVersion,
      'contractId': rag3ContractId,
      'fixtureId': 'instrument-${fixture.fixtureId}',
      'corpusHash': corpusHash,
      'defaultPassageRole': 'irrelevant',
      'cases': oracleCases,
    },
    objects: objects,
  );
}

final class Rag3InstrumentDatasetResult {
  const Rag3InstrumentDatasetResult({
    required this.sourceFixtureId,
    required this.sourceCorpusHash,
    required this.passageRoleOracleApplied,
    required this.hostedProvenanceValidated,
    required this.hostedAppDatabasePreserved,
    required this.report,
  });

  final String sourceFixtureId;
  final String sourceCorpusHash;
  final bool passageRoleOracleApplied;
  final bool hostedProvenanceValidated;
  final bool hostedAppDatabasePreserved;
  final Rag3HybridReport report;

  bool get instrumentValidated {
    final gates = report.core.gates;
    return report.deterministicReplayPassed &&
        hostedProvenanceValidated &&
        hostedAppDatabasePreserved &&
        gates['contextBudget']! &&
        gates['citationAndProvenance']! &&
        gates['emptyFusionNegativeControl']! &&
        gates['budgetBypassNegativeControl']! &&
        gates['vectorDegradation']! &&
        report.core.hybridMetrics.objectRecallAt10 ==
            report.core.lexicalMetrics.objectRecallAt10 &&
        report.core.hybridMetrics.objectHitAt5 ==
            report.core.lexicalMetrics.objectHitAt5 &&
        report.core.hybridMetrics.objectMrrAt10 ==
            report.core.lexicalMetrics.objectMrrAt10;
  }

  Map<String, Object?> toJson() => {
    'sourceFixtureId': sourceFixtureId,
    'sourceCorpusHash': sourceCorpusHash,
    'passageRoleOracleApplied': passageRoleOracleApplied,
    'instrumentValidated': instrumentValidated,
    'hostedProvenanceValidated': hostedProvenanceValidated,
    'hostedAppDatabasePreserved': hostedAppDatabasePreserved,
    'candidateGateResult': report.passed ? 'go' : 'no_go',
    'evaluation': report.toJson(),
  };
}

final class Rag3InstrumentReport {
  const Rag3InstrumentReport({
    required this.buildCommit,
    required this.buildDirty,
    required this.datasets,
  });

  final String buildCommit;
  final bool buildDirty;
  final List<Rag3InstrumentDatasetResult> datasets;

  bool get instrumentValidated =>
      datasets.isNotEmpty && datasets.every((item) => item.instrumentValidated);

  Map<String, Object?> toJson() => {
    'schemaName': rag3InstrumentReportSchema,
    'schemaVersion': 1,
    'contract': rag3InstrumentContract,
    'buildCommit': buildCommit,
    'buildDirty': buildDirty,
    'instrumentValidated': instrumentValidated,
    'promotionFixtureAccessed': false,
    'promotionDecision': 'not_run',
    'productionDecision': 'no_go',
    'vectorStatus': 'not_available',
    'vectorDegradedReason': rag3InstrumentVectorReason,
    'datasets': [for (final item in datasets) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG3 Instrument Evaluation')
      ..writeln()
      ..writeln('- Instrument validated: `$instrumentValidated`')
      ..writeln('- Promotion fixture accessed: `false`')
      ..writeln('- Promotion decision: `not_run`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Vector status: `not_available`')
      ..writeln('- Vector degradation: `$rag3InstrumentVectorReason`')
      ..writeln()
      ..writeln(
        '| Dataset | Instrument | Candidate gate | Recall@10 | Hit@5 | MRR@10 | Answer support | Abstention support |',
      )
      ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |');
    for (final item in datasets) {
      final core = item.report.core;
      buffer.writeln(
        '| ${item.sourceFixtureId} | '
        '${item.instrumentValidated ? 'pass' : 'fail'} | '
        '${item.report.passed ? 'go' : 'no_go'} | '
        '${core.hybridMetrics.objectRecallAt10.toStringAsFixed(4)} | '
        '${core.hybridMetrics.objectHitAt5.toStringAsFixed(4)} | '
        '${core.hybridMetrics.objectMrrAt10.toStringAsFixed(4)} | '
        '${core.answerSupportCount}/${core.answerSupportCases} | '
        '${core.abstentionSupportCount}/${core.abstentionSupportCases} |',
      );
    }
    return buffer.toString();
  }
}

final class Rag3InstrumentEvalOptions {
  const Rag3InstrumentEvalOptions({
    required this.rag1FixturePath,
    required this.rag2FixturePaths,
    required this.passageRoleOraclePath,
    required this.outDir,
  });

  final String rag1FixturePath;
  final List<String> rag2FixturePaths;
  final String passageRoleOraclePath;
  final String outDir;

  List<String> get allFixturePaths => [rag1FixturePath, ...rag2FixturePaths];

  static Rag3InstrumentEvalOptions? parse(List<String> args) {
    String? rag1FixturePath;
    String? passageRoleOraclePath;
    String? outDir;
    final rag2FixturePaths = <String>[];
    for (var index = 0; index < args.length; index++) {
      if (index + 1 >= args.length) return null;
      final flag = args[index];
      final value = args[++index];
      switch (flag) {
        case '--rag1-fixture':
          rag1FixturePath = value;
        case '--rag2-fixture':
          rag2FixturePaths.add(value);
        case '--passage-role-oracle':
          passageRoleOraclePath = value;
        case '--out-dir':
          outDir = value;
        default:
          return null;
      }
    }
    if (rag1FixturePath == null ||
        rag2FixturePaths.length != 2 ||
        passageRoleOraclePath == null ||
        outDir == null) {
      return null;
    }
    return Rag3InstrumentEvalOptions(
      rag1FixturePath: rag1FixturePath,
      rag2FixturePaths: List.unmodifiable(rag2FixturePaths),
      passageRoleOraclePath: passageRoleOraclePath,
      outDir: outDir,
    );
  }
}

bool _isPromotionPath(String path) =>
    path.toLowerCase().contains('rag3_offline_hybrid_holdout');

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

String _normalizeText(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();
