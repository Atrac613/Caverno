import 'dart:convert';
import 'dart:io';

import 'rag2_claim_support_eval.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2PassageRoleEvalSchema = 'caverno_rag2_passage_role_eval';
const rag2PassageRoleEvalSchemaVersion = 1;
const rag2PassageRoleOracleSchema = 'caverno_rag2_passage_role_oracle';

Future<void> main(List<String> args) async {
  final options = Rag2PassageRoleOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_passage_role_eval.dart '
      '--oracle PATH --fixture PATH --fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2PassageRoleEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 passage-role evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2PassageRoleReport> runRag2PassageRoleEval(
  Rag2PassageRoleOptions options,
) async {
  final oracle = await Rag2PassageRoleOracle.load(File(options.oraclePath));
  final datasets = <Rag2PassageRoleDataset>[];
  for (final fixturePath in options.fixturePaths) {
    final fixture = await RagRetrievalFixture.load(File(fixturePath));
    fixture.validate();
    final corpusHash = await fixture.computeCorpusHash();
    final datasetOracle = oracle.dataset(fixture.fixtureId);
    final documents = await loadRagFixtureDocuments(fixture);
    datasetOracle.validate(
      fixture,
      corpusHash,
      documents.map((item) => item.objectId).toSet(),
    );
    final scorer = Rag2LexicalScorer(
      policy: Rag2LexicalPolicy.trigram,
      documents: documents,
    );
    try {
      datasets.add(
        evaluateRag2PassageRoles(
          fixture: fixture,
          corpusHash: corpusHash,
          oracle: datasetOracle,
          rankedCases: [
            for (final fixtureCase in fixture.cases)
              scorer.rank(fixtureCase.query, limit: documents.length),
          ],
        ),
      );
    } finally {
      scorer.close();
    }
  }
  if (datasets.map((item) => item.fixtureId).toSet().length !=
      oracle.datasets.length) {
    throw StateError('Every oracle dataset must be evaluated exactly once.');
  }
  final report = Rag2PassageRoleReport(
    oracleId: oracle.oracleId,
    datasets: datasets,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_passage_role_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_passage_role_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag2PassageRoleDataset evaluateRag2PassageRoles({
  required RagRetrievalFixture fixture,
  required String corpusHash,
  required Rag2PassageRoleDatasetOracle oracle,
  required List<List<Rag2LexicalHit>> rankedCases,
}) {
  final cases = <Rag2PassageRoleCase>[];
  for (var index = 0; index < fixture.cases.length; index++) {
    final fixtureCase = fixture.cases[index];
    final hits = applyRag2FrozenSufficiencyPolicy(
      rankedCases[index],
      metricK: fixture.metricK,
    );
    final annotations = <Rag2PassageRoleAnnotation>[
      for (final hit in hits)
        Rag2PassageRoleAnnotation(
          objectId: hit.objectId,
          role: oracle.roleFor(fixtureCase.id, hit.objectId),
        ),
    ];
    final expectedRole = fixtureCase.answerFacts.isNotEmpty
        ? Rag2PassageRole.answerSupport
        : fixtureCase.citations.isNotEmpty
        ? Rag2PassageRole.abstentionSupport
        : null;
    cases.add(
      Rag2PassageRoleCase(
        caseId: fixtureCase.id,
        authority: fixtureCase.authority,
        expectedRole: expectedRole,
        annotations: annotations,
      ),
    );
  }
  return Rag2PassageRoleDataset(
    fixtureId: fixture.fixtureId,
    corpusHash: corpusHash,
    cases: cases,
  );
}

enum Rag2PassageRole {
  answerSupport('answer_support'),
  abstentionSupport('abstention_support'),
  topicalOnly('topical_only'),
  irrelevant('irrelevant');

  const Rag2PassageRole(this.id);
  final String id;

  static Rag2PassageRole parse(String value) => values.firstWhere(
    (item) => item.id == value,
    orElse: () => throw FormatException('Unsupported passage role: $value'),
  );
}

final class Rag2PassageRoleAnnotation {
  const Rag2PassageRoleAnnotation({required this.objectId, required this.role});
  final String objectId;
  final Rag2PassageRole role;

  Map<String, Object?> toJson() => {'objectId': objectId, 'role': role.id};
}

final class Rag2PassageRoleCase {
  const Rag2PassageRoleCase({
    required this.caseId,
    required this.authority,
    required this.expectedRole,
    required this.annotations,
  });
  final String caseId;
  final String authority;
  final Rag2PassageRole? expectedRole;
  final List<Rag2PassageRoleAnnotation> annotations;

  bool get expectedSupportRetrieved =>
      expectedRole != null &&
      annotations.any((item) => item.role == expectedRole);
  bool get abstentionSupportRetrieved =>
      annotations.any((item) => item.role == Rag2PassageRole.abstentionSupport);
  bool get topicalOnlyRetrieved =>
      annotations.any((item) => item.role == Rag2PassageRole.topicalOnly);

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'authority': authority,
    'expectedRole': expectedRole?.id ?? 'unavailable',
    'expectedSupportRetrieved': expectedSupportRetrieved,
    'annotations': [for (final item in annotations) item.toJson()],
  };
}

final class Rag2PassageRoleDataset {
  const Rag2PassageRoleDataset({
    required this.fixtureId,
    required this.corpusHash,
    required this.cases,
  });
  final String fixtureId;
  final String corpusHash;
  final List<Rag2PassageRoleCase> cases;

  int get answerCases => cases
      .where((item) => item.expectedRole == Rag2PassageRole.answerSupport)
      .length;
  int get abstentionCases => cases
      .where((item) => item.expectedRole == Rag2PassageRole.abstentionSupport)
      .length;
  int get unavailableCases =>
      cases.where((item) => item.expectedRole == null).length;
  int get answerSupportRetrieved => cases
      .where(
        (item) =>
            item.expectedRole == Rag2PassageRole.answerSupport &&
            item.expectedSupportRetrieved,
      )
      .length;
  int get abstentionSupportRetrieved => cases
      .where(
        (item) =>
            item.expectedRole == Rag2PassageRole.abstentionSupport &&
            item.expectedSupportRetrieved,
      )
      .length;
  int get unavailableWithAbstentionSupport => cases
      .where(
        (item) => item.expectedRole == null && item.abstentionSupportRetrieved,
      )
      .length;
  int get unavailableWithTopicalOnly => cases
      .where((item) => item.expectedRole == null && item.topicalOnlyRetrieved)
      .length;
  Map<String, int> get returnedRoleCounts {
    final counts = {for (final role in Rag2PassageRole.values) role.id: 0};
    for (final item in cases.expand((item) => item.annotations)) {
      counts[item.role.id] = counts[item.role.id]! + 1;
    }
    return counts;
  }

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'answerSupportRetrieved': answerSupportRetrieved,
    'answerCases': answerCases,
    'abstentionSupportRetrieved': abstentionSupportRetrieved,
    'abstentionCases': abstentionCases,
    'unavailableWithAbstentionSupport': unavailableWithAbstentionSupport,
    'unavailableWithTopicalOnly': unavailableWithTopicalOnly,
    'unavailableCases': unavailableCases,
    'returnedRoleCounts': returnedRoleCounts,
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag2PassageRoleReport {
  const Rag2PassageRoleReport({required this.oracleId, required this.datasets});
  final String oracleId;
  final List<Rag2PassageRoleDataset> datasets;

  Map<String, Object?> toJson() => {
    'schemaName': rag2PassageRoleEvalSchema,
    'schemaVersion': rag2PassageRoleEvalSchemaVersion,
    'oracleId': oracleId,
    'evaluationMode': 'frozen_retrieval_oracle_rescore',
    'rankingChanged': false,
    'retrievalDecision': 'diagnostic_complete',
    'runtimeRoleClassifier': 'not_available',
    'typedFactsDecision': 'close_as_diagnostic',
    'productionDecision': 'no_go',
    'datasets': [for (final item in datasets) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Passage-Role Evaluation')
      ..writeln()
      ..writeln('- Oracle: `$oracleId`')
      ..writeln('- Ranking changed: `false`')
      ..writeln('- Retrieval decision: `diagnostic_complete`')
      ..writeln('- Runtime role classifier: `not_available`')
      ..writeln('- Typed facts decision: `close_as_diagnostic`')
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Dataset | Answer support | Abstention support | Unavailable with abstention | Unavailable with topical only |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: |');
    for (final item in datasets) {
      buffer.writeln(
        '| ${item.fixtureId} | ${item.answerSupportRetrieved}/${item.answerCases} | '
        '${item.abstentionSupportRetrieved}/${item.abstentionCases} | '
        '${item.unavailableWithAbstentionSupport}/${item.unavailableCases} | '
        '${item.unavailableWithTopicalOnly}/${item.unavailableCases} |',
      );
    }
    return buffer.toString();
  }
}

final class Rag2PassageRoleOracle {
  const Rag2PassageRoleOracle({required this.oracleId, required this.datasets});
  final String oracleId;
  final List<Rag2PassageRoleDatasetOracle> datasets;

  static Future<Rag2PassageRoleOracle> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != rag2PassageRoleOracleSchema ||
        json['schemaVersion'] != 1 ||
        json['defaultRole'] != 'irrelevant') {
      throw const FormatException('Unsupported passage-role oracle contract.');
    }
    final datasets = (json['datasets'] as List)
        .map(
          (item) => Rag2PassageRoleDatasetOracle.fromJson(
            (item as Map).cast<String, Object?>(),
          ),
        )
        .toList();
    if (datasets.map((item) => item.fixtureId).toSet().length !=
        datasets.length) {
      throw const FormatException('Oracle fixture IDs must be unique.');
    }
    return Rag2PassageRoleOracle(
      oracleId: json['oracleId'] as String,
      datasets: datasets,
    );
  }

  Rag2PassageRoleDatasetOracle dataset(String fixtureId) => datasets.firstWhere(
    (item) => item.fixtureId == fixtureId,
    orElse: () => throw StateError('No passage-role oracle for $fixtureId.'),
  );
}

final class Rag2PassageRoleDatasetOracle {
  const Rag2PassageRoleDatasetOracle({
    required this.fixtureId,
    required this.corpusHash,
    required this.caseRoles,
  });
  final String fixtureId;
  final String corpusHash;
  final Map<String, Map<String, Rag2PassageRole>> caseRoles;

  factory Rag2PassageRoleDatasetOracle.fromJson(Map<String, Object?> json) {
    final caseRoles = <String, Map<String, Rag2PassageRole>>{};
    for (final rawCase in json['cases'] as List) {
      final item = (rawCase as Map).cast<String, Object?>();
      final caseId = item['caseId'] as String;
      if (caseRoles.containsKey(caseId)) {
        throw FormatException('Duplicate oracle case: $caseId');
      }
      final roles = (item['objectRoles'] as Map).cast<String, Object?>();
      caseRoles[caseId] = {
        for (final entry in roles.entries)
          entry.key: Rag2PassageRole.parse(entry.value as String),
      };
    }
    return Rag2PassageRoleDatasetOracle(
      fixtureId: json['fixtureId'] as String,
      corpusHash: json['corpusHash'] as String,
      caseRoles: caseRoles,
    );
  }

  void validate(
    RagRetrievalFixture fixture,
    String actualHash,
    Set<String> objectIds,
  ) {
    if (fixture.fixtureId != fixtureId || actualHash != corpusHash) {
      throw StateError('Passage-role oracle dataset identity mismatch.');
    }
    final fixtureCases = fixture.cases.map((item) => item.id).toSet();
    if (caseRoles.keys.toSet().length != fixtureCases.length ||
        !caseRoles.keys.toSet().containsAll(fixtureCases)) {
      throw StateError('Passage-role oracle must cover every fixture case.');
    }
    final annotatedObjects = caseRoles.values
        .expand((roles) => roles.keys)
        .toSet();
    if (!objectIds.containsAll(annotatedObjects)) {
      throw StateError('Passage-role oracle references an unknown object.');
    }
  }

  Rag2PassageRole roleFor(String caseId, String objectId) =>
      caseRoles[caseId]?[objectId] ?? Rag2PassageRole.irrelevant;
}

final class Rag2PassageRoleOptions {
  const Rag2PassageRoleOptions({
    required this.oraclePath,
    required this.fixturePaths,
    required this.outDir,
  });
  final String oraclePath;
  final List<String> fixturePaths;
  final String outDir;

  static Rag2PassageRoleOptions? parse(List<String> args) {
    String? oraclePath;
    String? outDir;
    final fixturePaths = <String>[];
    for (var index = 0; index < args.length; index++) {
      if (index + 1 >= args.length) return null;
      final value = args[++index];
      switch (args[index - 1]) {
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
    return oraclePath == null || outDir == null || fixturePaths.length != 2
        ? null
        : Rag2PassageRoleOptions(
            oraclePath: oraclePath,
            fixturePaths: fixturePaths,
            outDir: outDir,
          );
  }
}
