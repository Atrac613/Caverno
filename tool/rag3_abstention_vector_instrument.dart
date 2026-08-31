import 'dart:convert';
import 'dart:io';

import 'rag2_hosted_retrieval_eval.dart';
import 'rag2_passage_role_eval.dart';
import 'rag3_abstention_policy_instrument.dart';
import 'rag3_candidate_run_producer.dart';
import 'rag3_instrument_eval.dart';
import 'rag3_offline_hybrid_eval.dart';
import 'rag3_promotion_run.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag3AbstentionVectorInstrumentSchema =
    'caverno_rag3_abstention_vector_instrument';
const rag3AbstentionVectorInstrumentContract =
    'rag3-abstention-vector-instrument-v1';

Future<void> main(List<String> args) async {
  final options = Rag3AbstentionVectorInstrumentOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag3_abstention_vector_instrument.dart '
      '--rag1-fixture PATH --rag2-fixture PATH --rag2-fixture PATH '
      '--passage-role-oracle PATH --out-dir PATH --base-url URL '
      '--model ID [--api-key KEY]',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag3AbstentionVectorInstrument(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG3 abstention vector instrument failed: $error');
    exitCode = 65;
  }
}

Future<Rag3AbstentionVectorInstrumentReport> runRag3AbstentionVectorInstrument(
  Rag3AbstentionVectorInstrumentOptions options, {
  Rag3EmbeddingProvider? embeddingProvider,
  String? buildCommit,
  bool? buildDirty,
}) async {
  if ([
    ...options.allFixturePaths,
    options.passageRoleOraclePath,
  ].any(_isPromotionPath)) {
    throw StateError(
      'RAG3 abstention vector inputs cannot use promotion artifacts.',
    );
  }
  final output = Directory(options.outDir);
  if (output.existsSync() && output.listSync().isNotEmpty) {
    throw StateError(
      'RAG3 abstention vector output already exists; refusing rerun.',
    );
  }
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
  final passageRoleOracle = await Rag2PassageRoleOracle.load(
    File(options.passageRoleOraclePath),
  );
  final datasets = <Rag3AbstentionVectorDatasetResult>[];
  for (
    var datasetIndex = 0;
    datasetIndex < options.allFixturePaths.length;
    datasetIndex++
  ) {
    final fixturePath = options.allFixturePaths[datasetIndex];
    final fixture = await RagRetrievalFixture.load(File(fixturePath));
    fixture.validate();
    final datasetOracle = datasetIndex == 0
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
    final corpusChunkIds = rag3Fixture.chunks.keys.toList();
    final corpusEmbedding = await provider.embed(
      model: options.model,
      inputs: [
        for (final chunkId in corpusChunkIds)
          _chunkContent(rag3Fixture, chunkId),
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
    final hostedCases = {
      for (final item in hosted.candidateCases) item.caseId: item,
    };
    final cases = <Rag3CandidateCaseInput>[];
    for (final fixtureCase in fixture.cases) {
      final queryEmbedding = await provider.embed(
        model: options.model,
        inputs: [fixtureCase.query],
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
      final hostedCase = hostedCases[fixtureCase.id]!;
      cases.add(
        Rag3CandidateCaseInput(
          caseId: fixtureCase.id,
          submitted: true,
          lexicalRankedChunkIds: [
            for (final hit in hostedCase.hits) hit.chunkId,
          ],
          vector: Rag3VectorRankingInput.available(
            queryFingerprint: queryFingerprint,
            corpusFingerprint: corpusFingerprint,
            queryVector: queryEmbedding.vectors.single,
            corpusVectors: corpusVectors,
            latencyMs: queryEmbedding.latencyMs,
          ),
          lexicalLatencyMs: hostedCase.latencyMs,
          peakRssBytes: ProcessInfo.currentRss,
          peakVramBytes: 0,
        ),
      );
    }
    final runJson = const Rag3CandidateRunProducer().produce(
      fixture: rag3Fixture,
      runId: 'rag3-abstention-vector-${fixture.fixtureId}',
      metadata: {
        'buildCommit': resolvedCommit,
        'buildDirty': resolvedDirty,
        'hardware':
            '${Platform.operatingSystem}/${Platform.numberOfProcessors}',
        'warmState': 'cold',
        'tokenEstimateMethod': 'unicode_code_points_div_4_v1',
        'corpusEmbeddingLatencyMs': corpusEmbedding.latencyMs,
        'instrumentContract': rag3AbstentionVectorInstrumentContract,
      },
      cases: cases,
    );
    final run = Rag3CandidateRun.fromJson(runJson);
    final sweep = evaluateRag3AbstentionPolicySweep(
      fixture: rag3Fixture,
      run: run,
    );
    await datasetOutput.create(recursive: true);
    await _writeJson(
      File('${datasetOutput.path}/rag3_abstention_vector_run.json'),
      runJson,
    );
    await _writeJson(
      File('${datasetOutput.path}/rag3_abstention_policy_sweep.json'),
      sweep.toJson(),
    );
    datasets.add(
      Rag3AbstentionVectorDatasetResult(
        sourceFixtureId: fixture.fixtureId,
        split: datasetIndex < 2 ? 'development' : 'validation',
        hostedProvenanceValidated: hosted.candidateCases.every(
          (item) => item.provenanceValidated,
        ),
        hostedAppDatabasePreserved: hosted.hostPreserved,
        sweep: sweep,
      ),
    );
  }
  final selection = selectRag3AbstentionCandidate(
    datasets.where((item) => item.split == 'development').toList(),
  );
  final report = Rag3AbstentionVectorInstrumentReport(
    buildCommit: resolvedCommit,
    buildDirty: resolvedDirty,
    datasets: List.unmodifiable(datasets),
    selection: selection,
  );
  await output.create(recursive: true);
  await _writeJson(
    File('${output.path}/rag3_abstention_vector_instrument.json'),
    report.toJson(),
  );
  await File(
    '${output.path}/rag3_abstention_vector_instrument.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag3AbstentionCandidateSelection selectRag3AbstentionCandidate(
  List<Rag3AbstentionVectorDatasetResult> development,
) {
  if (development.isEmpty ||
      development.any((item) => item.split != 'development')) {
    throw StateError('Candidate selection requires development datasets.');
  }
  final candidates = <Rag3AbstentionCandidateScore>[];
  for (final depth in rag3AbstentionPolicyDepths) {
    final reports = [
      for (final dataset in development)
        dataset.sweep.reports.singleWhere((item) => item.policy.depth == depth),
    ];
    candidates.add(
      Rag3AbstentionCandidateScore(
        depth: depth,
        answerSupportCount: reports.fold(
          0,
          (sum, item) => sum + item.answerSupportCount,
        ),
        abstentionSupportCount: reports.fold(
          0,
          (sum, item) => sum + item.abstentionSupportCount,
        ),
        unavailableIrrelevantOnlyCount: reports.fold(
          0,
          (sum, item) => sum + item.unavailableIrrelevantOnlyCount,
        ),
        answerableAbstainedCount: reports.fold(
          0,
          (sum, item) => sum + item.answerableAbstainedCount,
        ),
      ),
    );
  }
  final eligible =
      candidates
          .where((item) => item.unavailableIrrelevantOnlyCount == 0)
          .toList()
        ..sort((left, right) {
          var order = right.answerSupportCount.compareTo(
            left.answerSupportCount,
          );
          if (order != 0) return order;
          order = right.abstentionSupportCount.compareTo(
            left.abstentionSupportCount,
          );
          if (order != 0) return order;
          order = left.answerableAbstainedCount.compareTo(
            right.answerableAbstainedCount,
          );
          if (order != 0) return order;
          return left.depth.compareTo(right.depth);
        });
  return Rag3AbstentionCandidateSelection(
    selectedDepth: eligible.isEmpty ? null : eligible.first.depth,
    scores: List.unmodifiable(candidates),
  );
}

final class Rag3AbstentionVectorDatasetResult {
  const Rag3AbstentionVectorDatasetResult({
    required this.sourceFixtureId,
    required this.split,
    required this.hostedProvenanceValidated,
    required this.hostedAppDatabasePreserved,
    required this.sweep,
  });

  final String sourceFixtureId;
  final String split;
  final bool hostedProvenanceValidated;
  final bool hostedAppDatabasePreserved;
  final Rag3AbstentionPolicySweepReport sweep;

  bool get instrumentValidated =>
      hostedProvenanceValidated &&
      hostedAppDatabasePreserved &&
      sweep.reports.length == rag3AbstentionPolicyDepths.length;

  Map<String, Object?> toJson() => {
    'sourceFixtureId': sourceFixtureId,
    'split': split,
    'instrumentValidated': instrumentValidated,
    'hostedProvenanceValidated': hostedProvenanceValidated,
    'hostedAppDatabasePreserved': hostedAppDatabasePreserved,
    'sweep': sweep.toJson(),
  };
}

final class Rag3AbstentionCandidateScore {
  const Rag3AbstentionCandidateScore({
    required this.depth,
    required this.answerSupportCount,
    required this.abstentionSupportCount,
    required this.unavailableIrrelevantOnlyCount,
    required this.answerableAbstainedCount,
  });

  final int depth;
  final int answerSupportCount;
  final int abstentionSupportCount;
  final int unavailableIrrelevantOnlyCount;
  final int answerableAbstainedCount;

  Map<String, Object?> toJson() => {
    'depth': depth,
    'answerSupportCount': answerSupportCount,
    'abstentionSupportCount': abstentionSupportCount,
    'unavailableIrrelevantOnlyCount': unavailableIrrelevantOnlyCount,
    'answerableAbstainedCount': answerableAbstainedCount,
  };
}

final class Rag3AbstentionCandidateSelection {
  const Rag3AbstentionCandidateSelection({
    required this.selectedDepth,
    required this.scores,
  });

  final int? selectedDepth;
  final List<Rag3AbstentionCandidateScore> scores;

  Map<String, Object?> toJson() => {
    'selectionRule': [
      'require_zero_unavailable_irrelevant_only',
      'maximize_answer_support',
      'maximize_abstention_support',
      'minimize_answerable_abstention',
      'prefer_shallower_depth',
    ],
    'selectedDepth': selectedDepth,
    'scores': [for (final item in scores) item.toJson()],
  };
}

final class Rag3AbstentionVectorInstrumentReport {
  const Rag3AbstentionVectorInstrumentReport({
    required this.buildCommit,
    required this.buildDirty,
    required this.datasets,
    required this.selection,
  });

  final String buildCommit;
  final bool buildDirty;
  final List<Rag3AbstentionVectorDatasetResult> datasets;
  final Rag3AbstentionCandidateSelection selection;

  bool get instrumentValidated =>
      datasets.length == 3 &&
      datasets.every((item) => item.instrumentValidated);

  Map<String, Object?> toJson() => {
    'schemaName': rag3AbstentionVectorInstrumentSchema,
    'schemaVersion': 1,
    'contract': rag3AbstentionVectorInstrumentContract,
    'buildCommit': buildCommit,
    'buildDirty': buildDirty,
    'instrumentValidated': instrumentValidated,
    'promotionFixtureAccessed': false,
    'promotionDecision': 'not_run',
    'productionDecision': 'no_go',
    'selection': selection.toJson(),
    'datasets': [for (final item in datasets) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG3 Abstention Vector Instrument')
      ..writeln()
      ..writeln('- Instrument validated: `$instrumentValidated`')
      ..writeln('- Promotion fixture accessed: `false`')
      ..writeln('- Promotion decision: `not_run`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Selected development depth: `${selection.selectedDepth}`')
      ..writeln();
    for (final dataset in datasets) {
      buffer
        ..writeln('## ${dataset.sourceFixtureId} (${dataset.split})')
        ..writeln()
        ..write(dataset.sweep.toMarkdown())
        ..writeln();
    }
    return buffer.toString();
  }
}

final class Rag3AbstentionVectorInstrumentOptions {
  const Rag3AbstentionVectorInstrumentOptions({
    required this.rag1FixturePath,
    required this.rag2FixturePaths,
    required this.passageRoleOraclePath,
    required this.outDir,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String rag1FixturePath;
  final List<String> rag2FixturePaths;
  final String passageRoleOraclePath;
  final String outDir;
  final String baseUrl;
  final String model;
  final String apiKey;

  List<String> get allFixturePaths => [rag1FixturePath, ...rag2FixturePaths];

  static Rag3AbstentionVectorInstrumentOptions? parse(List<String> args) {
    String? rag1FixturePath;
    String? passageRoleOraclePath;
    String? outDir;
    String? baseUrl;
    String? model;
    var apiKey = 'no-key';
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
        case '--base-url':
          baseUrl = value;
        case '--model':
          model = value;
        case '--api-key':
          apiKey = value;
        default:
          return null;
      }
    }
    if (rag1FixturePath == null ||
        rag2FixturePaths.length != 2 ||
        passageRoleOraclePath == null ||
        outDir == null ||
        baseUrl == null ||
        model == null) {
      return null;
    }
    return Rag3AbstentionVectorInstrumentOptions(
      rag1FixturePath: rag1FixturePath,
      rag2FixturePaths: List.unmodifiable(rag2FixturePaths),
      passageRoleOraclePath: passageRoleOraclePath,
      outDir: outDir,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
  }
}

String _chunkContent(Rag3HybridFixture fixture, String chunkId) {
  final chunk = fixture.chunks[chunkId]!;
  final object = fixture.objects[chunk.objectId]!;
  return object.sourceLines
      .sublist(chunk.lineStart - 1, chunk.lineEnd)
      .join('\n');
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

bool _isPromotionPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.contains('rag3_offline_hybrid_holdout') ||
      normalized.contains('rag3_promotion');
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
