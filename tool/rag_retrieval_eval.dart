import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

const ragRetrievalFixtureSchema = 'caverno_rag_retrieval_fixture';
const ragRetrievalRunSchema = 'caverno_rag_retrieval_run';
const ragRetrievalReportSchema = 'caverno_rag_retrieval_report';
const ragRetrievalSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = RagRetrievalEvalOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag_retrieval_eval.dart '
      '--fixture PATH --run PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRagRetrievalEval(options);
    stdout.writeln(report.toMarkdown());
    if (!report.passed) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('RAG retrieval evaluation failed: $error');
    exitCode = 65;
  }
}

Future<RagRetrievalReport> runRagRetrievalEval(
  RagRetrievalEvalOptions options,
) async {
  final fixture = await RagRetrievalFixture.load(File(options.fixturePath));
  final run = RagRetrievalRun.fromJson(
    _decodeObject(await File(options.runPath).readAsString()),
  );
  final report = await evaluateRagRetrievalRun(fixture: fixture, run: run);
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File('${outputDirectory.path}/rag_retrieval_eval.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag_retrieval_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<RagRetrievalReport> evaluateRagRetrievalRun({
  required RagRetrievalFixture fixture,
  required RagRetrievalRun run,
}) async {
  fixture.validate();
  run.validate(fixture);
  final actualHash = await fixture.computeCorpusHash();
  if (actualHash != fixture.corpusHash) {
    throw StateError(
      'Fixture corpus hash mismatch: expected ${fixture.corpusHash}, '
      'found $actualHash.',
    );
  }
  final arms = run.arms.map((arm) => _evaluateArm(fixture, arm)).toList();
  final negativeControls = arms.where((arm) => arm['negativeControl'] == true);
  final negativeControlsPassed =
      negativeControls.isNotEmpty &&
      negativeControls.every((arm) => arm['meetsExpectation'] == false);
  final evaluatedArmsPassed = arms
      .where(
        (arm) => arm['status'] == 'available' && arm['negativeControl'] != true,
      )
      .every((arm) => arm['meetsExpectation'] == true);
  return RagRetrievalReport(
    fixtureId: fixture.fixtureId,
    corpusHash: actualHash,
    metricPolicyVersion: fixture.metricPolicyVersion,
    metricK: fixture.metricK,
    runId: run.runId,
    metadata: run.metadata,
    arms: arms,
    negativeControlsPassed: negativeControlsPassed,
    evaluatedArmsPassed: evaluatedArmsPassed,
  );
}

Map<String, Object?> _evaluateArm(
  RagRetrievalFixture fixture,
  Map<String, Object?> arm,
) {
  final status = _string(arm, 'status');
  if (status == 'not_available') {
    return {
      'id': _string(arm, 'id'),
      'status': status,
      'unavailableReason': _string(arm, 'unavailableReason'),
      'negativeControl': false,
      'meetsExpectation': false,
      'cases': <Object?>[],
      'resource': _object(arm, 'resource', fallback: const {}),
    };
  }
  final results = {
    for (final result in _objectList(arm, 'results'))
      _string(result, 'caseId'): result,
  };
  final caseReports = <Map<String, Object?>>[];
  for (final fixtureCase in fixture.cases) {
    final result = results[fixtureCase.id]!;
    final hits = _objectList(result, 'hits');
    final objectMetrics = RetrievalMetrics.compute(
      ranking: hits.map((hit) => _string(hit, 'objectId')).toList(),
      relevance: fixtureCase.objectRelevance,
      k: fixture.metricK,
    );
    final chunkMetrics = RetrievalMetrics.compute(
      ranking: hits.map((hit) => _string(hit, 'chunkId')).toList(),
      relevance: fixtureCase.chunkRelevance,
      k: fixture.metricK,
    );
    final answer = result['answerEvaluation'] is Map
        ? (result['answerEvaluation'] as Map).cast<String, Object?>()
        : null;
    final caseReport = <String, Object?>{
      'caseId': fixtureCase.id,
      'category': fixtureCase.category,
      'authority': fixtureCase.authority,
      'objectMetrics': objectMetrics.toJson(),
      'chunkMetrics': chunkMetrics.toJson(),
      'answerGrounding': answer == null
          ? null
          : _answerRatio(
              answer,
              'groundedClaims',
              'totalClaims',
              answerExpected: fixtureCase.objectRelevance.isNotEmpty,
            ),
      'citationPrecision': answer == null
          ? null
          : _answerRatio(
              answer,
              'validCitations',
              'totalCitations',
              answerExpected: fixtureCase.objectRelevance.isNotEmpty,
            ),
      'latencyMs': _integer(result, 'latencyMs', fallback: 0),
      'promptTokens': _integer(result, 'promptTokens', fallback: 0),
      'contextTokens': _integer(result, 'contextTokens', fallback: 0),
      'returnedHitCount': hits.length,
    };
    final missReason = _optionalString(result, 'missReason');
    if (missReason != null) {
      caseReport['missReason'] = missReason;
    }
    caseReports.add(caseReport);
  }
  final scorable = caseReports
      .where((item) => _metric(item, 'objectMetrics', 'scorable') == true)
      .toList();
  final unanswerable = caseReports
      .where((item) => _metric(item, 'objectMetrics', 'scorable') == false)
      .toList();
  bool isHit(Map<String, Object?> item) =>
      (_metric(item, 'objectMetrics', 'hitAtK') as num) > 0;
  final answerableHitCount = scorable.where(isHit).length;
  final unanswerableRetrievedCount = unanswerable
      .where((item) => (item['returnedHitCount'] as int) > 0)
      .length;
  double average(String group, String key) => scorable.isEmpty
      ? 0
      : scorable
                .map((item) => (_metric(item, group, key) as num).toDouble())
                .reduce((a, b) => a + b) /
            scorable.length;
  final aggregate = <String, Object?>{
    'scorableCaseCount': scorable.length,
    'answerableCaseCount': scorable.length,
    'answerableHitCount': answerableHitCount,
    'answerableMissCount': scorable.length - answerableHitCount,
    'unanswerableCaseCount': unanswerable.length,
    'unanswerableRetrievedCount': unanswerableRetrievedCount,
    'missReasonCounts': _countStrings(caseReports, 'missReason'),
    'categoryBreakdown': _breakdown(caseReports, 'category'),
    'authorityBreakdown': _breakdown(caseReports, 'authority'),
    'objectRecallAtK': average('objectMetrics', 'recallAtK'),
    'objectHitAtK': average('objectMetrics', 'hitAtK'),
    'objectMrrAtK': average('objectMetrics', 'mrrAtK'),
    'objectNdcgAtK': average('objectMetrics', 'ndcgAtK'),
    'chunkRecallAtK': average('chunkMetrics', 'recallAtK'),
    'groundedAnswerRate': _averageNullable(caseReports, 'answerGrounding'),
    'citationPrecision': _averageNullable(caseReports, 'citationPrecision'),
    'totalLatencyMs': _sum(caseReports, 'latencyMs'),
    'totalPromptTokens': _sum(caseReports, 'promptTokens'),
    'totalContextTokens': _sum(caseReports, 'contextTokens'),
    'unanswerableFalsePositiveRate': unanswerable.isEmpty
        ? 0
        : unanswerableRetrievedCount / unanswerable.length,
  };
  return {
    'id': _string(arm, 'id'),
    'status': status,
    'negativeControl': arm['negativeControl'] == true,
    'meetsExpectation':
        (aggregate['objectHitAtK'] as double) >=
        _number(arm, 'minimumHitAtK', fallback: 0),
    'aggregate': aggregate,
    'cases': caseReports,
    'resource': _object(arm, 'resource'),
  };
}

final class RetrievalMetrics {
  const RetrievalMetrics({
    required this.scorable,
    required this.recallAtK,
    required this.hitAtK,
    required this.mrrAtK,
    required this.ndcgAtK,
  });

  final bool scorable;
  final double recallAtK;
  final double hitAtK;
  final double mrrAtK;
  final double ndcgAtK;

  factory RetrievalMetrics.compute({
    required List<String> ranking,
    required Map<String, int> relevance,
    required int k,
  }) {
    if (relevance.isEmpty) {
      return const RetrievalMetrics(
        scorable: false,
        recallAtK: 0,
        hitAtK: 0,
        mrrAtK: 0,
        ndcgAtK: 0,
      );
    }
    final ranked = ranking.toSet().take(k).toList();
    final retrieved = ranked.where(relevance.containsKey).length;
    final firstRelevant = ranked.indexWhere(relevance.containsKey);
    double dcg(Iterable<int> gains) {
      var score = 0.0;
      var index = 0;
      for (final gain in gains.take(k)) {
        score += gain / (math.log(index + 2) / math.ln2);
        index++;
      }
      return score;
    }

    final actualDcg = dcg(ranked.map((id) => relevance[id] ?? 0));
    final ideal = relevance.values.toList()..sort((a, b) => b.compareTo(a));
    final idealDcg = dcg(ideal);
    return RetrievalMetrics(
      scorable: true,
      recallAtK: retrieved / relevance.length,
      hitAtK: retrieved == 0 ? 0 : 1,
      mrrAtK: firstRelevant < 0 ? 0 : 1 / (firstRelevant + 1),
      ndcgAtK: idealDcg == 0 ? 0 : actualDcg / idealDcg,
    );
  }

  Map<String, Object> toJson() => {
    'scorable': scorable,
    'recallAtK': recallAtK,
    'hitAtK': hitAtK,
    'mrrAtK': mrrAtK,
    'ndcgAtK': ndcgAtK,
  };
}

final class RagRetrievalFixture {
  const RagRetrievalFixture({
    required this.sourceFile,
    required this.fixtureId,
    required this.metricPolicyVersion,
    required this.metricK,
    required this.corpusRoot,
    required this.corpusHash,
    required this.cases,
  });

  final File sourceFile;
  final String fixtureId;
  final int metricPolicyVersion;
  final int metricK;
  final String corpusRoot;
  final String corpusHash;
  final List<RagRetrievalFixtureCase> cases;

  static Future<RagRetrievalFixture> load(File file) async {
    final json = _decodeObject(await file.readAsString());
    _requireSchema(json, ragRetrievalFixtureSchema);
    return RagRetrievalFixture(
      sourceFile: file,
      fixtureId: _string(json, 'fixtureId'),
      metricPolicyVersion: _integer(json, 'metricPolicyVersion'),
      metricK: _integer(json, 'metricK'),
      corpusRoot: _string(json, 'corpusRoot'),
      corpusHash: _string(json, 'corpusHash'),
      cases: _objectList(
        json,
        'cases',
      ).map(RagRetrievalFixtureCase.fromJson).toList(),
    );
  }

  void validate() {
    if (cases.length != 20) {
      throw StateError('RAG1 seed must contain exactly 20 cases.');
    }
    if (metricK <= 0 || cases.map((item) => item.id).toSet().length != 20) {
      throw StateError('Fixture metric K and case IDs must be valid.');
    }
    const categories = {
      'current_source',
      'historical_decision',
      'cross_source_conflict',
      'japanese_query',
      'unanswerable_adversarial',
    };
    if (!cases.map((item) => item.category).toSet().containsAll(categories)) {
      throw StateError('Fixture is missing a required case category.');
    }
    for (final item in cases) {
      item.validate();
    }
  }

  Future<String> computeCorpusHash() async {
    final root = Directory('${sourceFile.parent.path}/$corpusRoot');
    final files =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final bytes = <int>[];
    for (final file in files) {
      bytes
        ..addAll(utf8.encode(file.path.substring(root.path.length + 1)))
        ..add(0)
        ..addAll(await file.readAsBytes())
        ..add(0);
    }
    return sha256.convert(bytes).toString();
  }
}

final class RagRetrievalFixtureCase {
  const RagRetrievalFixtureCase({
    required this.id,
    required this.category,
    required this.query,
    required this.authority,
    required this.objectRelevance,
    required this.chunkRelevance,
    required this.answerFacts,
    required this.citations,
  });

  final String id;
  final String category;
  final String query;
  final String authority;
  final Map<String, int> objectRelevance;
  final Map<String, int> chunkRelevance;
  final List<String> answerFacts;
  final List<String> citations;

  factory RagRetrievalFixtureCase.fromJson(Map<String, Object?> json) {
    final qrels = _object(json, 'qrels');
    final answer = _object(json, 'answerKey');
    return RagRetrievalFixtureCase(
      id: _string(json, 'id'),
      category: _string(json, 'category'),
      query: _string(json, 'query'),
      authority: _string(json, 'authority'),
      objectRelevance: _integerMap(qrels, 'objects'),
      chunkRelevance: _integerMap(qrels, 'chunks'),
      answerFacts: _stringList(answer, 'facts'),
      citations: _stringList(answer, 'citations'),
    );
  }

  void validate() {
    if (!{'current', 'historical', 'conflict', 'none'}.contains(authority)) {
      throw StateError('Case $id has unsupported authority `$authority`.');
    }
    final answerable = authority != 'none';
    if (answerable != objectRelevance.isNotEmpty ||
        answerable != chunkRelevance.isNotEmpty) {
      throw StateError('Case $id has qrels inconsistent with its authority.');
    }
  }
}

final class RagRetrievalRun {
  const RagRetrievalRun._(this.json);

  final Map<String, Object?> json;
  String get runId => _string(json, 'runId');
  String get fixtureId => _string(json, 'fixtureId');
  Map<String, Object?> get metadata => _object(json, 'metadata');
  List<Map<String, Object?>> get arms => _objectList(json, 'arms');

  factory RagRetrievalRun.fromJson(Map<String, Object?> json) {
    _requireSchema(json, ragRetrievalRunSchema);
    return RagRetrievalRun._(json);
  }

  void validate(RagRetrievalFixture fixture) {
    if (fixtureId != fixture.fixtureId) {
      throw StateError('Run fixtureId does not match the fixture.');
    }
    const metadataFields = {
      'buildCommit',
      'buildDirty',
      'embeddingFingerprint',
      'hardware',
      'warmState',
      'tokenEstimateMethod',
    };
    if (!metadata.keys.toSet().containsAll(metadataFields)) {
      throw StateError('Run metadata is missing reproducibility fields.');
    }
    const requiredArms = {'L', 'V', 'H', 'AK', 'H+AK', 'NONE', 'FULL'};
    final ids = arms.map((arm) => _string(arm, 'id')).toList();
    if (ids.toSet().length != ids.length ||
        !ids.toSet().containsAll(requiredArms)) {
      throw StateError('Run must declare each required comparison arm once.');
    }
    for (final arm in arms) {
      _validateArm(fixture, arm);
    }
  }
}

void _validateArm(RagRetrievalFixture fixture, Map<String, Object?> arm) {
  final id = _string(arm, 'id');
  final status = _string(arm, 'status');
  if (status == 'not_available') {
    _string(arm, 'unavailableReason');
    if (_objectList(arm, 'results', fallback: const []).isNotEmpty) {
      throw StateError('Unavailable arm $id must not include results.');
    }
    return;
  }
  if (status != 'available') throw StateError('Arm $id has an invalid status.');
  if (!_object(
    arm,
    'resource',
  ).keys.toSet().containsAll({'peakRssBytes', 'peakVramBytes'})) {
    throw StateError('Available arm $id must record RSS and VRAM fields.');
  }
  final results = _objectList(arm, 'results');
  final ids = results.map((result) => _string(result, 'caseId')).toList();
  final fixtureIds = fixture.cases.map((item) => item.id).toSet();
  if (ids.length != fixtureIds.length ||
      ids.toSet().length != ids.length ||
      !ids.toSet().containsAll(fixtureIds)) {
    throw StateError('Available arm $id must include every fixture case once.');
  }
  if (id != 'L') return;
  final cases = {for (final item in fixture.cases) item.id: item};
  for (final result in results) {
    final item = cases[_string(result, 'caseId')]!;
    if (item.category != 'japanese_query') continue;
    final hit = _objectList(result, 'hits').any(
      (candidate) =>
          item.objectRelevance.containsKey(_string(candidate, 'objectId')),
    );
    if (!hit &&
        !{
          'tokenization',
          'ranking',
        }.contains(_optionalString(result, 'missReason'))) {
      throw StateError(
        'Japanese lexical miss ${item.id} must be attributed to '
        'tokenization or ranking.',
      );
    }
  }
}

final class RagRetrievalReport {
  const RagRetrievalReport({
    required this.fixtureId,
    required this.corpusHash,
    required this.metricPolicyVersion,
    required this.metricK,
    required this.runId,
    required this.metadata,
    required this.arms,
    required this.negativeControlsPassed,
    required this.evaluatedArmsPassed,
  });

  final String fixtureId;
  final String corpusHash;
  final int metricPolicyVersion;
  final int metricK;
  final String runId;
  final Map<String, Object?> metadata;
  final List<Map<String, Object?>> arms;
  final bool negativeControlsPassed;
  final bool evaluatedArmsPassed;
  bool get passed => negativeControlsPassed && evaluatedArmsPassed;

  Map<String, Object?> toJson() => {
    'schemaName': ragRetrievalReportSchema,
    'schemaVersion': ragRetrievalSchemaVersion,
    'result': passed ? 'passed' : 'failed',
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'metricPolicyVersion': metricPolicyVersion,
    'metricK': metricK,
    'runId': runId,
    'metadata': metadata,
    'negativeControlsPassed': negativeControlsPassed,
    'evaluatedArmsPassed': evaluatedArmsPassed,
    'arms': arms,
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG Retrieval Evaluation')
      ..writeln()
      ..writeln('- Result: `${passed ? 'passed' : 'failed'}`')
      ..writeln('- Fixture: `$fixtureId`')
      ..writeln('- Metric policy: `v$metricPolicyVersion`')
      ..writeln('- Corpus SHA-256: `$corpusHash`')
      ..writeln(
        '- Negative controls: '
        '`${negativeControlsPassed ? 'passed' : 'failed'}`',
      )
      ..writeln()
      ..writeln(
        '| Arm | Status | Hits/Cases | Recall@$metricK | Hit@$metricK | '
        'MRR@$metricK | nDCG@$metricK | No-answer retrieved | '
        'Latency ms | Context tokens |',
      )
      ..writeln(
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final arm in arms) {
      final aggregate = arm['aggregate'] is Map
          ? (arm['aggregate'] as Map).cast<String, Object?>()
          : null;
      buffer.writeln(
        '| ${arm['id']} | ${arm['status']} | '
        '${_formatCountPair(aggregate, 'answerableHitCount', 'answerableCaseCount')} | '
        '${_formatMetric(aggregate?['objectRecallAtK'])} | '
        '${_formatMetric(aggregate?['objectHitAtK'])} | '
        '${_formatMetric(aggregate?['objectMrrAtK'])} | '
        '${_formatMetric(aggregate?['objectNdcgAtK'])} | '
        '${_formatCountPair(aggregate, 'unanswerableRetrievedCount', 'unanswerableCaseCount')} | '
        '${aggregate?['totalLatencyMs'] ?? 'not_available'} | '
        '${aggregate?['totalContextTokens'] ?? 'not_available'} |',
      );
    }
    for (final arm in arms.where((item) => item['status'] == 'available')) {
      final aggregate = (arm['aggregate'] as Map).cast<String, Object?>();
      buffer
        ..writeln()
        ..writeln('## ${arm['id']} diagnostics')
        ..writeln()
        ..writeln('### Miss reasons')
        ..writeln()
        ..writeln('| Reason | Cases |')
        ..writeln('| --- | ---: |');
      _writeCountRows(
        buffer,
        (aggregate['missReasonCounts'] as Map).cast<String, Object?>(),
      );
      for (final entry in const [
        ('Category', 'categoryBreakdown'),
        ('Authority', 'authorityBreakdown'),
      ]) {
        buffer
          ..writeln()
          ..writeln('### ${entry.$1}')
          ..writeln()
          ..writeln('| ${entry.$1} | Hits/Cases |')
          ..writeln('| --- | ---: |');
        final rows = (aggregate[entry.$2] as Map).cast<String, Object?>();
        for (final row in rows.entries) {
          final counts = (row.value as Map).cast<String, Object?>();
          buffer.writeln(
            '| ${row.key} | ${counts['hitCount']}/${counts['caseCount']} |',
          );
        }
      }
    }
    return buffer.toString();
  }
}

final class RagRetrievalEvalOptions {
  const RagRetrievalEvalOptions({
    required this.fixturePath,
    required this.runPath,
    required this.outDir,
  });

  final String fixturePath;
  final String runPath;
  final String outDir;

  static RagRetrievalEvalOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length || !args[index].startsWith('--')) {
        return null;
      }
      values[args[index]] = args[index + 1];
    }
    final fixture = values['--fixture'];
    final run = values['--run'];
    final output = values['--out-dir'];
    if (fixture == null ||
        run == null ||
        output == null ||
        values.length != 3) {
      return null;
    }
    return RagRetrievalEvalOptions(
      fixturePath: fixture,
      runPath: run,
      outDir: output,
    );
  }
}

Map<String, Object?> _decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) throw const FormatException('Expected a JSON object.');
  return decoded.cast<String, Object?>();
}

void _requireSchema(Map<String, Object?> json, String name) {
  if (json['schemaName'] != name ||
      json['schemaVersion'] != ragRetrievalSchemaVersion) {
    throw FormatException(
      'Expected $name schema version $ragRetrievalSchemaVersion.',
    );
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected non-empty string `$key`.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value : null;
}

int _integer(Map<String, Object?> json, String key, {int? fallback}) {
  final value = json[key] ?? fallback;
  if (value is! int) throw FormatException('Expected integer `$key`.');
  return value;
}

double _number(
  Map<String, Object?> json,
  String key, {
  required double fallback,
}) {
  final value = json[key] ?? fallback;
  if (value is! num) throw FormatException('Expected number `$key`.');
  return value.toDouble();
}

Map<String, Object?> _object(
  Map<String, Object?> json,
  String key, {
  Map<String, Object?>? fallback,
}) {
  final value = json[key] ?? fallback;
  if (value is! Map) throw FormatException('Expected object `$key`.');
  return value.cast<String, Object?>();
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> json,
  String key, {
  List<Object?>? fallback,
}) {
  final value = json[key] ?? fallback;
  if (value is! List) throw FormatException('Expected list `$key`.');
  return value.map((item) {
    if (item is! Map) throw FormatException('Expected object items in `$key`.');
    return item.cast<String, Object?>();
  }).toList();
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Expected string list `$key`.');
  }
  return value.cast<String>();
}

Map<String, int> _integerMap(Map<String, Object?> json, String key) {
  return _object(json, key).map((id, value) {
    if (value is! int || value <= 0) {
      throw FormatException('Expected positive relevance for `$id`.');
    }
    return MapEntry(id, value);
  });
}

Object? _metric(Map<String, Object?> item, String group, String key) =>
    (item[group] as Map<String, Object?>)[key];

double _answerRatio(
  Map<String, Object?> json,
  String numerator,
  String denominator, {
  required bool answerExpected,
}) {
  final total = _integer(json, denominator);
  return total == 0
      ? (answerExpected ? 0 : 1)
      : _integer(json, numerator) / total;
}

double? _averageNullable(List<Map<String, Object?>> items, String key) {
  final values = items.map((item) => item[key]).whereType<num>().toList();
  return values.isEmpty
      ? null
      : values.map((value) => value.toDouble()).reduce((a, b) => a + b) /
            values.length;
}

int _sum(List<Map<String, Object?>> items, String key) =>
    items.fold(0, (sum, item) => sum + (item[key] as int));

Map<String, Object?> _countStrings(
  List<Map<String, Object?>> items,
  String key,
) {
  final counts = <String, Object?>{};
  for (final value in items.map((item) => item[key]).whereType<String>()) {
    counts[value] = ((counts[value] as int?) ?? 0) + 1;
  }
  return counts;
}

Map<String, Object?> _breakdown(List<Map<String, Object?>> items, String key) {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final item in items) {
    groups.putIfAbsent(item[key]! as String, () => []).add(item);
  }
  return {
    for (final entry in groups.entries)
      entry.key: {
        'caseCount': entry.value.length,
        'hitCount': entry.value
            .where(
              (item) => (_metric(item, 'objectMetrics', 'hitAtK') as num) > 0,
            )
            .length,
      },
  };
}

String _formatCountPair(
  Map<String, Object?>? values,
  String numerator,
  String denominator,
) => values == null
    ? 'not_available'
    : '${values[numerator]}/${values[denominator]}';

void _writeCountRows(StringBuffer buffer, Map<String, Object?> counts) {
  if (counts.isEmpty) {
    buffer.writeln('| none | 0 |');
    return;
  }
  for (final entry in counts.entries) {
    buffer.writeln('| ${entry.key} | ${entry.value} |');
  }
}

String _formatMetric(Object? value) =>
    value is num ? value.toStringAsFixed(3) : 'not_available';
