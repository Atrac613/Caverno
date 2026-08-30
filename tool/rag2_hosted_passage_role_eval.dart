import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'rag2_hosted_retrieval_eval.dart';
import 'rag2_passage_role_eval.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2HostedPassageRoleContract =
    'rag2-hosted-passage-role-eval-contract-v2';
const rag2HostedPassageRoleReportSchema =
    'caverno_rag2_hosted_passage_role_eval_report';
const rag2HostedPassageRoleMinimumAnswerSupport = 13;
const rag2HostedPassageRoleRequiredJapaneseSupport = 4;
const rag2HostedPassageRoleRequiredAbstentionSupport = 2;
const rag2HostedPassageRoleMaximumOnlyIrrelevantUnavailable = 0;
const rag2HostedPassageRoleMaximumContextTokens = 6000;

Future<void> main(List<String> args) async {
  final options = Rag2HostedPassageRoleOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_hosted_passage_role_eval.dart '
      '--mode instrument|promotion --oracle PATH --fixture PATH '
      '[--fixture PATH] --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2HostedPassageRoleEval(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 hosted passage-role evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2HostedPassageRoleReport> runRag2HostedPassageRoleEval(
  Rag2HostedPassageRoleOptions options, {
  String? buildCommit,
  bool? buildDirty,
}) async {
  final oracle = await Rag2PassageRoleOracle.load(File(options.oraclePath));
  final datasets = <Rag2HostedPassageRoleDataset>[];
  String? resolvedCommit;
  bool? resolvedDirty;
  for (final fixturePath in options.fixturePaths) {
    final fixture = await RagRetrievalFixture.load(File(fixturePath));
    fixture.validate();
    final corpusHash = await fixture.computeCorpusHash();
    final documents = await loadRagFixtureDocuments(fixture);
    final datasetOracle = oracle.dataset(fixture.fixtureId);
    datasetOracle.validate(
      fixture,
      corpusHash,
      documents.map((item) => item.objectId).toSet(),
    );
    final datasetOut = '${options.outDir}/datasets/${fixture.fixtureId}';
    final hosted = await runRag2HostedRetrievalEval(
      Rag2HostedRetrievalEvalOptions(
        fixturePath: fixturePath,
        outDir: datasetOut,
        storeRoot: '$datasetOut/store',
      ),
      buildCommit: buildCommit,
      buildDirty: buildDirty,
    );
    resolvedCommit ??= hosted.buildCommit;
    resolvedDirty ??= hosted.buildDirty;
    if (resolvedCommit != hosted.buildCommit ||
        resolvedDirty != hosted.buildDirty) {
      throw StateError('Hosted dataset build identities must match.');
    }
    datasets.add(
      _scoreHostedDataset(
        fixture: fixture,
        corpusHash: corpusHash,
        oracle: datasetOracle,
        hosted: hosted,
      ),
    );
  }
  if (datasets.map((item) => item.fixtureId).toSet().length !=
      oracle.datasets.length) {
    throw StateError('Every oracle dataset must be evaluated exactly once.');
  }
  final gate = options.mode == Rag2HostedPassageRoleMode.promotion
      ? Rag2HostedPassageRoleGate.evaluate(datasets.single)
      : null;
  final report = Rag2HostedPassageRoleReport(
    mode: options.mode,
    oracleId: oracle.oracleId,
    buildCommit: resolvedCommit!,
    buildDirty: resolvedDirty!,
    datasets: List.unmodifiable(datasets),
    gate: gate,
  );
  final output = Directory(options.outDir);
  await output.create(recursive: true);
  await File('${output.path}/rag2_hosted_passage_role_eval.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${output.path}/rag2_hosted_passage_role_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag2HostedPassageRoleDataset _scoreHostedDataset({
  required RagRetrievalFixture fixture,
  required String corpusHash,
  required Rag2PassageRoleDatasetOracle oracle,
  required Rag2HostedRetrievalEvalReport hosted,
}) {
  final cases = <Rag2HostedPassageRoleCase>[];
  for (final fixtureCase in fixture.cases) {
    final candidate = hosted.candidateCases.singleWhere(
      (item) => item.caseId == fixtureCase.id,
    );
    final expectedRole = fixtureCase.answerFacts.isNotEmpty
        ? Rag2PassageRole.answerSupport
        : fixtureCase.citations.isNotEmpty
        ? Rag2PassageRole.abstentionSupport
        : null;
    cases.add(
      Rag2HostedPassageRoleCase(
        caseId: fixtureCase.id,
        category: fixtureCase.category,
        expectedRole: expectedRole,
        expectedRoleObjectCount: expectedRole == null
            ? 0
            : oracle.caseRoles[fixtureCase.id]!.values
                  .where((item) => item == expectedRole)
                  .length,
        annotations: [
          for (final hit in candidate.hits)
            Rag2PassageRoleAnnotation(
              objectId: hit.objectId,
              role: oracle.roleFor(fixtureCase.id, hit.objectId),
            ),
        ],
        contextTokens: candidate.contextTokens,
        provenanceValidated: candidate.provenanceValidated,
      ),
    );
  }
  final lexical = hosted.rag1Report.arms.singleWhere(
    (item) => item['id'] == 'L',
  );
  final aggregate = (lexical['aggregate'] as Map).cast<String, Object?>();
  return Rag2HostedPassageRoleDataset(
    fixtureId: fixture.fixtureId,
    corpusHash: corpusHash,
    generation: hosted.generation,
    snapshotHash: hosted.snapshotHash,
    appDatabaseSchemaVersion: hosted.appDatabaseSchemaVersion,
    hostPreserved: hosted.hostPreserved,
    negativeControlPassed: hosted.rag1Report.negativeControlsPassed,
    rawNoAnswerRetrieved: aggregate['unanswerableRetrievedCount'] as int,
    cases: List.unmodifiable(cases),
  );
}

enum Rag2HostedPassageRoleMode {
  instrument('instrument'),
  promotion('promotion');

  const Rag2HostedPassageRoleMode(this.id);
  final String id;

  static Rag2HostedPassageRoleMode parse(String value) => values.firstWhere(
    (item) => item.id == value,
    orElse: () => throw FormatException('Unsupported evaluation mode: $value'),
  );
}

final class Rag2HostedPassageRoleCase {
  const Rag2HostedPassageRoleCase({
    required this.caseId,
    required this.category,
    required this.expectedRole,
    required this.expectedRoleObjectCount,
    required this.annotations,
    required this.contextTokens,
    required this.provenanceValidated,
  });

  final String caseId;
  final String category;
  final Rag2PassageRole? expectedRole;
  final int expectedRoleObjectCount;
  final List<Rag2PassageRoleAnnotation> annotations;
  final int contextTokens;
  final bool provenanceValidated;

  bool get expectedSupportRetrieved =>
      expectedRole != null &&
      annotations.any((item) => item.role == expectedRole);
  bool get hasAbstentionSupport =>
      annotations.any((item) => item.role == Rag2PassageRole.abstentionSupport);
  bool get hasTopicalOnly =>
      annotations.any((item) => item.role == Rag2PassageRole.topicalOnly);
  bool get onlyIrrelevant =>
      annotations.isNotEmpty &&
      annotations.every((item) => item.role == Rag2PassageRole.irrelevant);
  int? get firstExpectedSupportRank {
    if (expectedRole == null) return null;
    final index = annotations.indexWhere((item) => item.role == expectedRole);
    return index < 0 ? null : index + 1;
  }

  double get supportDcg {
    if (expectedRole == null) return 0;
    var value = 0.0;
    for (var index = 0; index < annotations.length; index++) {
      if (annotations[index].role == expectedRole) {
        value += 1 / (math.log(index + 2) / math.ln2);
      }
    }
    return value;
  }

  double get idealSupportDcg {
    var value = 0.0;
    for (var index = 0; index < expectedRoleObjectCount; index++) {
      value += 1 / (math.log(index + 2) / math.ln2);
    }
    return value;
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'category': category,
    'expectedRole': expectedRole?.id ?? 'unavailable',
    'expectedSupportRetrieved': expectedSupportRetrieved,
    'contextTokens': contextTokens,
    'provenanceValidated': provenanceValidated,
    'annotations': [for (final item in annotations) item.toJson()],
  };
}

final class Rag2HostedPassageRoleDataset {
  const Rag2HostedPassageRoleDataset({
    required this.fixtureId,
    required this.corpusHash,
    required this.generation,
    required this.snapshotHash,
    required this.appDatabaseSchemaVersion,
    required this.hostPreserved,
    required this.negativeControlPassed,
    required this.rawNoAnswerRetrieved,
    required this.cases,
  });

  final String fixtureId;
  final String corpusHash;
  final int generation;
  final String snapshotHash;
  final int appDatabaseSchemaVersion;
  final bool hostPreserved;
  final bool negativeControlPassed;
  final int rawNoAnswerRetrieved;
  final List<Rag2HostedPassageRoleCase> cases;

  Iterable<Rag2HostedPassageRoleCase> get answerCases =>
      cases.where((item) => item.expectedRole == Rag2PassageRole.answerSupport);
  Iterable<Rag2HostedPassageRoleCase> get abstentionCases => cases.where(
    (item) => item.expectedRole == Rag2PassageRole.abstentionSupport,
  );
  Iterable<Rag2HostedPassageRoleCase> get unavailableCases =>
      cases.where((item) => item.expectedRole == null);
  Iterable<Rag2HostedPassageRoleCase> get japaneseCases =>
      cases.where((item) => item.category == 'japanese_query');
  int get answerSupportRetrieved =>
      answerCases.where((item) => item.expectedSupportRetrieved).length;
  int get abstentionSupportRetrieved =>
      abstentionCases.where((item) => item.expectedSupportRetrieved).length;
  int get japaneseSupportRetrieved =>
      japaneseCases.where((item) => item.expectedSupportRetrieved).length;
  int get unavailableWithAbstentionSupport =>
      unavailableCases.where((item) => item.hasAbstentionSupport).length;
  int get unavailableWithTopicalOnly =>
      unavailableCases.where((item) => item.hasTopicalOnly).length;
  int get unavailableOnlyIrrelevant =>
      unavailableCases.where((item) => item.onlyIrrelevant).length;
  int get unavailableWithoutEvidence =>
      unavailableCases.where((item) => item.annotations.isEmpty).length;
  int get totalContextTokens =>
      cases.fold(0, (sum, item) => sum + item.contextTokens);
  bool get provenanceValidated =>
      cases.every((item) => item.provenanceValidated);

  double get supportMrrAtK {
    final expected = cases.where((item) => item.expectedRole != null).toList();
    return expected.fold<double>(0, (sum, item) {
          final rank = item.firstExpectedSupportRank;
          return sum + (rank == null ? 0 : 1 / rank);
        }) /
        expected.length;
  }

  double get supportNdcgAtK {
    final expected = cases.where((item) => item.expectedRole != null).toList();
    return expected.fold<double>(0, (sum, item) {
          final ideal = item.idealSupportDcg;
          return sum + (ideal == 0 ? 0 : item.supportDcg / ideal);
        }) /
        expected.length;
  }

  Map<String, int> get returnedRoleCounts {
    final counts = {for (final role in Rag2PassageRole.values) role.id: 0};
    for (final annotation in cases.expand((item) => item.annotations)) {
      counts[annotation.role.id] = counts[annotation.role.id]! + 1;
    }
    return counts;
  }

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'generation': generation,
    'snapshotHash': snapshotHash,
    'appDatabaseSchemaVersion': appDatabaseSchemaVersion,
    'answerSupportRetrieved': answerSupportRetrieved,
    'answerCases': answerCases.length,
    'japaneseSupportRetrieved': japaneseSupportRetrieved,
    'japaneseCases': japaneseCases.length,
    'abstentionSupportRetrieved': abstentionSupportRetrieved,
    'abstentionCases': abstentionCases.length,
    'unavailableWithAbstentionSupport': unavailableWithAbstentionSupport,
    'unavailableWithTopicalOnly': unavailableWithTopicalOnly,
    'unavailableOnlyIrrelevant': unavailableOnlyIrrelevant,
    'unavailableWithoutEvidence': unavailableWithoutEvidence,
    'unavailableCases': unavailableCases.length,
    'rawNoAnswerRetrievedDiagnostic': rawNoAnswerRetrieved,
    'returnedRoleCounts': returnedRoleCounts,
    'supportMrrAtK': supportMrrAtK,
    'supportNdcgAtK': supportNdcgAtK,
    'totalContextTokens': totalContextTokens,
    'provenanceValidated': provenanceValidated,
    'negativeControlPassed': negativeControlPassed,
    'hostPreserved': hostPreserved,
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag2HostedPassageRoleGate {
  const Rag2HostedPassageRoleGate({
    required this.holdoutShapeValid,
    required this.answerSupportRetrieved,
    required this.japaneseSupportRetrieved,
    required this.abstentionSupportRetrieved,
    required this.unavailableOnlyIrrelevant,
    required this.provenanceValidated,
    required this.negativeControlPassed,
    required this.hostPreserved,
    required this.totalContextTokens,
  });

  final bool holdoutShapeValid;
  final int answerSupportRetrieved;
  final int japaneseSupportRetrieved;
  final int abstentionSupportRetrieved;
  final int unavailableOnlyIrrelevant;
  final bool provenanceValidated;
  final bool negativeControlPassed;
  final bool hostPreserved;
  final int totalContextTokens;

  factory Rag2HostedPassageRoleGate.evaluate(
    Rag2HostedPassageRoleDataset dataset,
  ) => Rag2HostedPassageRoleGate(
    holdoutShapeValid:
        dataset.answerCases.length == 14 &&
        dataset.abstentionCases.length == 2 &&
        dataset.unavailableCases.length == 4 &&
        dataset.japaneseCases.length == 4,
    answerSupportRetrieved: dataset.answerSupportRetrieved,
    japaneseSupportRetrieved: dataset.japaneseSupportRetrieved,
    abstentionSupportRetrieved: dataset.abstentionSupportRetrieved,
    unavailableOnlyIrrelevant: dataset.unavailableOnlyIrrelevant,
    provenanceValidated: dataset.provenanceValidated,
    negativeControlPassed: dataset.negativeControlPassed,
    hostPreserved: dataset.hostPreserved,
    totalContextTokens: dataset.totalContextTokens,
  );

  bool get passed =>
      holdoutShapeValid &&
      answerSupportRetrieved >= rag2HostedPassageRoleMinimumAnswerSupport &&
      japaneseSupportRetrieved ==
          rag2HostedPassageRoleRequiredJapaneseSupport &&
      abstentionSupportRetrieved ==
          rag2HostedPassageRoleRequiredAbstentionSupport &&
      unavailableOnlyIrrelevant <=
          rag2HostedPassageRoleMaximumOnlyIrrelevantUnavailable &&
      provenanceValidated &&
      negativeControlPassed &&
      hostPreserved &&
      totalContextTokens <= rag2HostedPassageRoleMaximumContextTokens;

  Map<String, Object?> toJson() => {
    'decision': passed ? 'go' : 'no_go',
    'holdoutShapeValid': holdoutShapeValid,
    'answerSupportRetrieved': answerSupportRetrieved,
    'minimumAnswerSupport': rag2HostedPassageRoleMinimumAnswerSupport,
    'japaneseSupportRetrieved': japaneseSupportRetrieved,
    'requiredJapaneseSupport': rag2HostedPassageRoleRequiredJapaneseSupport,
    'abstentionSupportRetrieved': abstentionSupportRetrieved,
    'requiredAbstentionSupport': rag2HostedPassageRoleRequiredAbstentionSupport,
    'unavailableOnlyIrrelevant': unavailableOnlyIrrelevant,
    'maximumOnlyIrrelevantUnavailable':
        rag2HostedPassageRoleMaximumOnlyIrrelevantUnavailable,
    'provenanceValidated': provenanceValidated,
    'negativeControlPassed': negativeControlPassed,
    'hostPreserved': hostPreserved,
    'totalContextTokens': totalContextTokens,
    'maximumContextTokens': rag2HostedPassageRoleMaximumContextTokens,
  };
}

final class Rag2HostedPassageRoleReport {
  const Rag2HostedPassageRoleReport({
    required this.mode,
    required this.oracleId,
    required this.buildCommit,
    required this.buildDirty,
    required this.datasets,
    required this.gate,
  });

  final Rag2HostedPassageRoleMode mode;
  final String oracleId;
  final String buildCommit;
  final bool buildDirty;
  final List<Rag2HostedPassageRoleDataset> datasets;
  final Rag2HostedPassageRoleGate? gate;

  String get candidateDecision => mode == Rag2HostedPassageRoleMode.instrument
      ? 'diagnostic_complete'
      : gate!.passed
      ? 'go'
      : 'no_go';

  Map<String, Object?> toJson() => {
    'schemaName': rag2HostedPassageRoleReportSchema,
    'schemaVersion': 1,
    'contract': rag2HostedPassageRoleContract,
    'evaluationMode': mode.id,
    'oracleId': oracleId,
    'candidate': rag2HostedRetrievalCandidate,
    'threshold': rag2HostedRetrievalThreshold,
    'buildCommit': buildCommit,
    'buildDirty': buildDirty,
    'rawNoAnswerGate': 'withdrawn',
    'runtimePassageRole': 'unknown',
    'runtimeRoleClassifier': 'not_available',
    'candidateDecision': candidateDecision,
    'productionDecision': 'no_go',
    'rag3Decision': 'no_go',
    if (gate != null) 'gate': gate!.toJson(),
    'datasets': [for (final item in datasets) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Hosted Passage-Role Evaluation')
      ..writeln()
      ..writeln('- Contract: `$rag2HostedPassageRoleContract`')
      ..writeln('- Mode: `${mode.id}`')
      ..writeln('- Oracle: `$oracleId`')
      ..writeln('- Candidate: `$rag2HostedRetrievalCandidate`')
      ..writeln('- Threshold: `$rag2HostedRetrievalThreshold`')
      ..writeln('- Raw no-answer gate: `withdrawn`')
      ..writeln('- Runtime passage role: `unknown`')
      ..writeln('- Candidate decision: `$candidateDecision`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- RAG3 decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Dataset | Answer support | Japanese support | Expected abstention | Only-irrelevant unavailable | Context tokens |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
    for (final dataset in datasets) {
      buffer.writeln(
        '| ${dataset.fixtureId} | '
        '${dataset.answerSupportRetrieved}/${dataset.answerCases.length} | '
        '${dataset.japaneseSupportRetrieved}/${dataset.japaneseCases.length} | '
        '${dataset.abstentionSupportRetrieved}/${dataset.abstentionCases.length} | '
        '${dataset.unavailableOnlyIrrelevant}/${dataset.unavailableCases.length} | '
        '${dataset.totalContextTokens} |',
      );
    }
    if (gate != null) {
      buffer
        ..writeln()
        ..writeln('## Promotion gate')
        ..writeln()
        ..writeln('- Decision: `${gate!.passed ? 'go' : 'no_go'}`')
        ..writeln('- Holdout shape valid: `${gate!.holdoutShapeValid}`')
        ..writeln('- Provenance validated: `${gate!.provenanceValidated}`')
        ..writeln('- Negative control passed: `${gate!.negativeControlPassed}`')
        ..writeln('- Existing host preserved: `${gate!.hostPreserved}`');
    }
    return buffer.toString();
  }
}

final class Rag2HostedPassageRoleOptions {
  const Rag2HostedPassageRoleOptions({
    required this.mode,
    required this.oraclePath,
    required this.fixturePaths,
    required this.outDir,
  });

  final Rag2HostedPassageRoleMode mode;
  final String oraclePath;
  final List<String> fixturePaths;
  final String outDir;

  static Rag2HostedPassageRoleOptions? parse(List<String> args) {
    String? mode;
    String? oraclePath;
    String? outDir;
    final fixturePaths = <String>[];
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length) return null;
      final value = args[index + 1];
      switch (args[index]) {
        case '--mode':
          mode = value;
        case '--oracle':
          oraclePath = value;
        case '--fixture':
          fixturePaths.add(value);
        case '--out-dir':
          outDir = value;
        default:
          return null;
      }
    }
    if (mode == null ||
        oraclePath == null ||
        outDir == null ||
        fixturePaths.isEmpty) {
      return null;
    }
    try {
      final parsedMode = Rag2HostedPassageRoleMode.parse(mode);
      if ((parsedMode == Rag2HostedPassageRoleMode.instrument &&
              fixturePaths.length != 2) ||
          (parsedMode == Rag2HostedPassageRoleMode.promotion &&
              fixturePaths.length != 1)) {
        return null;
      }
      return Rag2HostedPassageRoleOptions(
        mode: parsedMode,
        oraclePath: oraclePath,
        fixturePaths: List.unmodifiable(fixturePaths),
        outDir: outDir,
      );
    } on FormatException {
      return null;
    }
  }
}
