import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

const rag3ContractId = 'rag3-offline-hybrid-eval-contract-v2';
const rag3CandidateId = 'rrf-k60-l1-v1-budget6000-v1';
const rag3FixtureSchema = 'caverno_rag3_offline_hybrid_fixture';
const rag3OracleSchema = 'caverno_rag3_offline_hybrid_oracle';
const rag3RunSchema = 'caverno_rag3_offline_hybrid_run';
const rag3ReportSchema = 'caverno_rag3_offline_hybrid_report';
const rag3SchemaVersion = 1;
const rag3RrfConstant = 60;
const rag3MaxInputDepth = 32;
const rag3ContextBudgetTokens = 6000;
const rag3MaxGroupsPerObject = 2;

Future<void> main(List<String> args) async {
  final options = Rag3HybridEvalOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag3_offline_hybrid_eval.dart '
      '--fixture PATH --oracle PATH --run PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag3HybridEval(options);
    stdout.writeln(report.toMarkdown());
    if (!report.passed) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('RAG3 offline hybrid evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag3HybridReport> runRag3HybridEval(
  Rag3HybridEvalOptions options,
) async {
  final fixture = await Rag3HybridFixture.load(
    fixtureFile: File(options.fixturePath),
    oracleFile: File(options.oraclePath),
  );
  final run = Rag3CandidateRun.fromJson(
    _decodeObject(await File(options.runPath).readAsString()),
  );
  final report = evaluateRag3HybridRun(fixture: fixture, run: run);
  final output = Directory(options.outDir);
  await output.create(recursive: true);
  await File('${output.path}/rag3_offline_hybrid_eval.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${output.path}/rag3_offline_hybrid_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag3HybridEvalOptions {
  const Rag3HybridEvalOptions({
    required this.fixturePath,
    required this.oraclePath,
    required this.runPath,
    required this.outDir,
  });

  final String fixturePath;
  final String oraclePath;
  final String runPath;
  final String outDir;

  static Rag3HybridEvalOptions? parse(List<String> args) {
    String? value(String flag) {
      final index = args.indexOf(flag);
      if (index < 0 || index + 1 >= args.length) return null;
      return args[index + 1];
    }

    final fixture = value('--fixture');
    final oracle = value('--oracle');
    final run = value('--run');
    final out = value('--out-dir');
    if ([fixture, oracle, run, out].any((item) => item == null)) return null;
    return Rag3HybridEvalOptions(
      fixturePath: fixture!,
      oraclePath: oracle!,
      runPath: run!,
      outDir: out!,
    );
  }
}

final class Rag3HybridFixture {
  const Rag3HybridFixture({
    required this.contractId,
    required this.fixtureId,
    required this.corpusHash,
    required this.objects,
    required this.cases,
  });

  final String contractId;
  final String fixtureId;
  final String corpusHash;
  final Map<String, Rag3KnowledgeObject> objects;
  final Map<String, Rag3FixtureCase> cases;

  Map<String, Rag3Chunk> get chunks => {
    for (final object in objects.values)
      for (final chunk in object.chunks) chunk.id: chunk,
  };

  static Future<Rag3HybridFixture> load({
    required File fixtureFile,
    required File oracleFile,
  }) async {
    final fixtureJson = _decodeObject(await fixtureFile.readAsString());
    final oracleJson = _decodeObject(await oracleFile.readAsString());
    _requireSchema(fixtureJson, rag3FixtureSchema);
    _requireSchema(oracleJson, rag3OracleSchema);
    for (final key in const ['contractId', 'fixtureId', 'corpusHash']) {
      if (fixtureJson[key] != oracleJson[key]) {
        throw StateError('Fixture and oracle $key values do not match.');
      }
    }
    final corpusRoot = Directory(
      '${fixtureFile.parent.path}/${_string(fixtureJson, 'corpusRoot')}',
    );
    final actualCorpusHash = await computeRag3CorpusHash(corpusRoot);
    if (actualCorpusHash != _string(fixtureJson, 'corpusHash')) {
      throw StateError('RAG3 fixture corpus hash does not match its files.');
    }

    final objects = <String, Rag3KnowledgeObject>{};
    for (final objectJson in _objectList(fixtureJson, 'objects')) {
      final sourcePath = _string(objectJson, 'sourcePath');
      final sourceFile = File('${corpusRoot.path}/$sourcePath');
      if (!sourceFile.existsSync()) {
        throw StateError('RAG3 fixture source is missing: $sourcePath');
      }
      final bytes = await sourceFile.readAsBytes();
      if (sha256.convert(bytes).toString() !=
          _string(objectJson, 'objectContentHash')) {
        throw StateError('RAG3 object hash mismatch: $sourcePath');
      }
      final lines = await sourceFile.readAsLines();
      final object = Rag3KnowledgeObject.fromJson(objectJson, lines);
      if (objects.putIfAbsent(object.id, () => object) != object) {
        throw StateError('Duplicate RAG3 object ID: ${object.id}');
      }
    }
    return Rag3HybridFixture.fromJson(
      fixtureJson: fixtureJson,
      oracleJson: oracleJson,
      objects: objects,
    );
  }

  factory Rag3HybridFixture.fromJson({
    required Map<String, Object?> fixtureJson,
    required Map<String, Object?> oracleJson,
    required Map<String, Rag3KnowledgeObject> objects,
  }) {
    _requireSchema(fixtureJson, rag3FixtureSchema);
    _requireSchema(oracleJson, rag3OracleSchema);
    final contractId = _string(fixtureJson, 'contractId');
    final fixtureId = _string(fixtureJson, 'fixtureId');
    final corpusHash = _string(fixtureJson, 'corpusHash');
    if (contractId != rag3ContractId ||
        oracleJson['contractId'] != contractId ||
        oracleJson['fixtureId'] != fixtureId ||
        oracleJson['corpusHash'] != corpusHash) {
      throw StateError('RAG3 fixture and oracle identities are invalid.');
    }
    final selection = _object(fixtureJson, 'selectionPolicy');
    if (_integer(selection, 'contextBudgetTokens') != rag3ContextBudgetTokens ||
        _integer(selection, 'maxGroupsPerObject') != rag3MaxGroupsPerObject ||
        _integer(selection, 'estimatedRunesPerToken') != 4 ||
        _string(selection, 'citationFormatVersion') != 'rag3-citation-v1') {
      throw StateError('RAG3 fixture selection policy is not frozen v1.');
    }
    final controls = {
      for (final item in _objectList(fixtureJson, 'negativeControls'))
        _string(item, 'id'): _string(item, 'expectedOutcome'),
    };
    if (controls['empty-shuffled-fusion'] != 'fails_quality_gate' ||
        controls['budget-bypass'] != 'fails_zero_budget_violation_gate' ||
        controls.length != 2) {
      throw StateError('RAG3 fixture negative controls are incomplete.');
    }
    if (_string(oracleJson, 'defaultPassageRole') != 'irrelevant') {
      throw StateError('RAG3 oracle default passage role must be irrelevant.');
    }
    final caseInputs = {
      for (final item in _objectList(fixtureJson, 'cases'))
        _string(item, 'id'): item,
    };
    final oracleInputs = {
      for (final item in _objectList(oracleJson, 'cases'))
        _string(item, 'id'): item,
    };
    if (caseInputs.length != _objectList(fixtureJson, 'cases').length ||
        oracleInputs.length != _objectList(oracleJson, 'cases').length ||
        caseInputs.keys
            .toSet()
            .difference(oracleInputs.keys.toSet())
            .isNotEmpty ||
        oracleInputs.keys
            .toSet()
            .difference(caseInputs.keys.toSet())
            .isNotEmpty) {
      throw StateError(
        'RAG3 oracle must cover every fixture case exactly once.',
      );
    }
    final knownObjects = objects.keys.toSet();
    final knownChunks = {
      for (final object in objects.values)
        for (final chunk in object.chunks) chunk.id,
    };
    final chunkCount = objects.values.fold<int>(
      0,
      (count, object) => count + object.chunks.length,
    );
    if (knownChunks.length != chunkCount) {
      throw StateError('RAG3 chunk IDs must be globally unique.');
    }
    final cases = <String, Rag3FixtureCase>{};
    for (final entry in caseInputs.entries) {
      final item = Rag3FixtureCase.fromJson(
        entry.value,
        oracleInputs[entry.key]!,
      );
      if (!knownObjects.containsAll(item.objectQrels.keys) ||
          !knownChunks.containsAll(item.chunkQrels.keys) ||
          !knownChunks.containsAll(item.passageRoles.keys)) {
        throw StateError('RAG3 oracle references an unknown ID: ${item.id}');
      }
      const expectedRoles = {
        'answer_support',
        'abstention_support',
        'topical_only',
        'no_evidence',
        'not_applicable',
      };
      const passageRoles = {
        'answer_support',
        'abstention_support',
        'topical_only',
        'irrelevant',
      };
      if (!expectedRoles.contains(item.expectedEvidenceRole) ||
          !item.passageRoles.values.every(passageRoles.contains)) {
        throw StateError('RAG3 oracle contains an unsupported passage role.');
      }
      cases[item.id] = item;
    }
    return Rag3HybridFixture(
      contractId: contractId,
      fixtureId: fixtureId,
      corpusHash: corpusHash,
      objects: Map.unmodifiable(objects),
      cases: Map.unmodifiable(cases),
    );
  }
}

final class Rag3KnowledgeObject {
  const Rag3KnowledgeObject({
    required this.id,
    required this.sourcePath,
    required this.revision,
    required this.objectContentHash,
    required this.sourceTrust,
    required this.authority,
    required this.sourceLines,
    required this.chunks,
  });

  final String id;
  final String sourcePath;
  final String revision;
  final String objectContentHash;
  final String sourceTrust;
  final String authority;
  final List<String> sourceLines;
  final List<Rag3Chunk> chunks;

  factory Rag3KnowledgeObject.fromJson(
    Map<String, Object?> json,
    List<String> sourceLines,
  ) {
    final id = _string(json, 'id');
    final sourcePath = _string(json, 'sourcePath');
    if (sourcePath != id || !_isSafeRelativePath(sourcePath)) {
      throw StateError('RAG3 source paths must be safe object-relative IDs.');
    }
    final chunks = <Rag3Chunk>[];
    for (final chunkJson in _objectList(json, 'chunks')) {
      final start = _integer(chunkJson, 'lineStart');
      final end = _integer(chunkJson, 'lineEnd');
      if (start <= 0 || end < start || end > sourceLines.length) {
        throw StateError('Invalid line span for ${_string(chunkJson, 'id')}.');
      }
      final content = sourceLines.sublist(start - 1, end).join('\n');
      if (sha256.convert(utf8.encode(content)).toString() !=
          _string(chunkJson, 'contentHash')) {
        throw StateError('RAG3 chunk hash mismatch: ${chunkJson['id']}');
      }
      final chunkId = _string(chunkJson, 'id');
      if (!chunkId.startsWith('$id#')) {
        throw StateError('RAG3 chunk ID does not belong to object $id.');
      }
      chunks.add(
        Rag3Chunk(
          id: chunkId,
          objectId: id,
          lineStart: start,
          lineEnd: end,
          contentHash: _string(chunkJson, 'contentHash'),
        ),
      );
    }
    if (chunks.map((item) => item.id).toSet().length != chunks.length) {
      throw StateError('RAG3 object $id contains duplicate chunk IDs.');
    }
    return Rag3KnowledgeObject(
      id: id,
      sourcePath: sourcePath,
      revision: _string(json, 'revision'),
      objectContentHash: _string(json, 'objectContentHash'),
      sourceTrust: _string(json, 'sourceTrust'),
      authority: _string(json, 'authority'),
      sourceLines: List.unmodifiable(sourceLines),
      chunks: List.unmodifiable(chunks),
    );
  }
}

final class Rag3Chunk {
  const Rag3Chunk({
    required this.id,
    required this.objectId,
    required this.lineStart,
    required this.lineEnd,
    required this.contentHash,
  });

  final String id;
  final String objectId;
  final int lineStart;
  final int lineEnd;
  final String contentHash;
}

final class Rag3FixtureCase {
  const Rag3FixtureCase({
    required this.id,
    required this.language,
    required this.shouldSearch,
    required this.strata,
    required this.objectQrels,
    required this.chunkQrels,
    required this.expectedEvidenceRole,
    required this.passageRoles,
  });

  final String id;
  final String language;
  final bool shouldSearch;
  final Set<String> strata;
  final Map<String, int> objectQrels;
  final Map<String, int> chunkQrels;
  final String expectedEvidenceRole;
  final Map<String, String> passageRoles;

  bool get answerable => strata.contains('answerable');
  bool get unavailable => strata.contains('unavailable');

  factory Rag3FixtureCase.fromJson(
    Map<String, Object?> fixture,
    Map<String, Object?> oracle,
  ) {
    final qrels = _object(oracle, 'qrels');
    return Rag3FixtureCase(
      id: _string(fixture, 'id'),
      language: _string(fixture, 'language'),
      shouldSearch: _boolean(fixture, 'shouldSearch'),
      strata: _stringList(fixture, 'strata').toSet(),
      objectQrels: _intMap(qrels, 'objects'),
      chunkQrels: _intMap(qrels, 'chunks'),
      expectedEvidenceRole: _string(oracle, 'expectedEvidenceRole'),
      passageRoles: _stringMap(oracle, 'passageRoles'),
    );
  }

  String roleFor(String chunkId) => passageRoles[chunkId] ?? 'irrelevant';
}

final class Rag3CandidateRun {
  const Rag3CandidateRun._(this.json);

  final Map<String, Object?> json;
  String get runId => _string(json, 'runId');
  Map<String, Object?> get metadata => _object(json, 'metadata');
  List<Map<String, Object?>> get cases => _objectList(json, 'cases');

  factory Rag3CandidateRun.fromJson(Map<String, Object?> json) {
    _requireSchema(json, rag3RunSchema);
    return Rag3CandidateRun._(json);
  }

  void validate(Rag3HybridFixture fixture) {
    if (_string(json, 'contractId') != fixture.contractId ||
        _string(json, 'candidateId') != rag3CandidateId ||
        _string(json, 'fixtureId') != fixture.fixtureId ||
        _string(json, 'corpusHash') != fixture.corpusHash) {
      throw StateError(
        'RAG3 run identity does not match the frozen candidate.',
      );
    }
    const metadataFields = {
      'buildCommit',
      'buildDirty',
      'hardware',
      'warmState',
      'tokenEstimateMethod',
    };
    if (!metadata.keys.toSet().containsAll(metadataFields)) {
      throw StateError('RAG3 run metadata is incomplete.');
    }
    _string(metadata, 'buildCommit');
    _boolean(metadata, 'buildDirty');
    _string(metadata, 'hardware');
    _string(metadata, 'warmState');
    _string(metadata, 'tokenEstimateMethod');
    final byId = <String, Map<String, Object?>>{};
    for (final item in cases) {
      final id = _string(item, 'caseId');
      if (byId.putIfAbsent(id, () => item) != item) {
        throw StateError('Duplicate RAG3 run case: $id');
      }
    }
    if (byId.keys.toSet().difference(fixture.cases.keys.toSet()).isNotEmpty ||
        fixture.cases.keys.toSet().difference(byId.keys.toSet()).isNotEmpty) {
      throw StateError('RAG3 run must cover every fixture case exactly once.');
    }
    final knownChunks = fixture.chunks.keys.toSet();
    for (final entry in byId.entries) {
      _validateRunCase(fixture.cases[entry.key]!, entry.value, knownChunks);
    }
  }
}

void _validateRunCase(
  Rag3FixtureCase fixtureCase,
  Map<String, Object?> runCase,
  Set<String> knownChunks,
) {
  final submitted = _boolean(runCase, 'submitted');
  final lexical = _stringList(runCase, 'lexicalRankedChunkIds');
  final vector = _object(runCase, 'vector');
  final vectorRanking = _stringList(vector, 'rankedChunkIds');
  if (lexical.length > rag3MaxInputDepth ||
      vectorRanking.length > rag3MaxInputDepth) {
    throw StateError('RAG3 ranking exceeds the frozen input depth.');
  }
  if (!knownChunks.containsAll(lexical) ||
      !knownChunks.containsAll(vectorRanking)) {
    throw StateError('RAG3 run ranking contains an unknown chunk ID.');
  }
  if (!fixtureCase.shouldSearch) {
    if (submitted || lexical.isNotEmpty || vectorRanking.isNotEmpty) {
      throw StateError('No-search RAG3 cases must remain unsubmitted.');
    }
  } else if (!submitted) {
    throw StateError('Search-eligible RAG3 cases must be submitted.');
  }
  final resource = _object(runCase, 'resource');
  if (_integer(resource, 'peakRssBytes') < 0 ||
      _integer(resource, 'peakVramBytes') < 0) {
    throw StateError('RAG3 resource measurements cannot be negative.');
  }
  _integer(runCase, 'lexicalLatencyMs');
  _integer(vector, 'latencyMs');
  final status = _string(vector, 'status');
  final receipt = _object(vector, 'validationReceipt');
  for (final field in const [
    'finiteValues',
    'nonZeroMagnitude',
    'uniformDimensions',
    'fingerprintMatch',
  ]) {
    _boolean(receipt, field);
  }
  final fingerprint = _object(vector, 'fingerprint');
  _integer(fingerprint, 'schemaVersion');
  final endpointIdentity = _string(fingerprint, 'endpointIdentity');
  if (normalizeRag3EndpointIdentity(endpointIdentity) != endpointIdentity) {
    throw StateError(
      'RAG3 endpoint identity must be normalized and sanitized.',
    );
  }
  _string(fingerprint, 'requestedModelId');
  _string(fingerprint, 'responseModelId');
  if (_integer(fingerprint, 'dimension') <= 0) {
    throw StateError('RAG3 vector dimension must be positive.');
  }
  final receiptValid = const [
    'finiteValues',
    'nonZeroMagnitude',
    'uniformDimensions',
    'fingerprintMatch',
  ].every((field) => receipt[field] == true);
  if (status == 'available') {
    if (!receiptValid || _optionalString(vector, 'degradedReason') != null) {
      throw StateError('Available RAG3 vectors require a valid receipt.');
    }
  } else if (status == 'not_available' || status == 'invalid') {
    if (vectorRanking.isNotEmpty ||
        _optionalString(vector, 'degradedReason') == null) {
      throw StateError(
        'Degraded RAG3 vectors require an empty ranking and reason.',
      );
    }
    if (status == 'invalid' && receiptValid) {
      throw StateError('Invalid RAG3 vectors must fail receipt validation.');
    }
  } else {
    throw StateError('Unsupported RAG3 vector status: $status');
  }
}

Future<String> computeRag3CorpusHash(Directory root) async {
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
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

Rag3HybridReport evaluateRag3HybridRun({
  required Rag3HybridFixture fixture,
  required Rag3CandidateRun run,
}) {
  run.validate(fixture);
  final first = _evaluateRag3Core(fixture, run);
  final second = _evaluateRag3Core(fixture, run);
  final deterministic =
      jsonEncode(first.toJson()) == jsonEncode(second.toJson());
  return Rag3HybridReport(
    core: first,
    deterministicReplayPassed: deterministic,
  );
}

Rag3HybridReportCore _evaluateRag3Core(
  Rag3HybridFixture fixture,
  Rag3CandidateRun run,
) {
  final runCases = {
    for (final item in run.cases) _string(item, 'caseId'): item,
  };
  final hybridCases = <Rag3CaseEvaluation>[];
  final lexicalCases = <Rag3CaseEvaluation>[];
  final vectorCases = <Rag3CaseEvaluation>[];
  for (final fixtureCase in fixture.cases.values) {
    final runCase = runCases[fixtureCase.id]!;
    hybridCases.add(
      _evaluateCase(fixture, fixtureCase, runCase, Rag3EvaluationArm.hybrid),
    );
    lexicalCases.add(
      _evaluateCase(fixture, fixtureCase, runCase, Rag3EvaluationArm.lexical),
    );
    vectorCases.add(
      _evaluateCase(fixture, fixtureCase, runCase, Rag3EvaluationArm.vector),
    );
  }
  final hybridMetrics = Rag3ArmMetrics.compute(fixture.cases, hybridCases);
  final lexicalMetrics = Rag3ArmMetrics.compute(fixture.cases, lexicalCases);
  final vectorMetrics = Rag3ArmMetrics.compute(fixture.cases, vectorCases);

  var betterArmMissCount = 0;
  for (final fixtureCase in fixture.cases.values.where(
    (item) => item.answerable,
  )) {
    final hybrid = hybridCases.singleWhere(
      (item) => item.caseId == fixtureCase.id,
    );
    final lexical = lexicalCases.singleWhere(
      (item) => item.caseId == fixtureCase.id,
    );
    final vector = vectorCases.singleWhere(
      (item) => item.caseId == fixtureCase.id,
    );
    if (!hybrid.hitAt5 && (lexical.hitAt5 || vector.hitAt5)) {
      betterArmMissCount++;
    }
  }

  final answerCases = fixture.cases.values.where((item) => item.answerable);
  final japaneseCases = answerCases.where((item) => item.language == 'ja');
  final abstentionCases = fixture.cases.values.where(
    (item) => item.expectedEvidenceRole == 'abstention_support',
  );
  bool expectedSupportRetrieved(Rag3FixtureCase item) {
    final result = hybridCases.singleWhere(
      (caseItem) => caseItem.caseId == item.id,
    );
    return result.selectedRoles.contains(item.expectedEvidenceRole);
  }

  final answerSupportCount = answerCases.where(expectedSupportRetrieved).length;
  final japaneseSupportCount = japaneseCases
      .where(expectedSupportRetrieved)
      .length;
  final abstentionSupportCount = abstentionCases
      .where(expectedSupportRetrieved)
      .length;
  final unavailableIrrelevantOnlyCount = fixture.cases.values
      .where((item) => item.unavailable)
      .where((item) {
        final result = hybridCases.singleWhere(
          (caseItem) => caseItem.caseId == item.id,
        );
        return result.selectedRoles.isNotEmpty &&
            result.selectedRoles.every((role) => role == 'irrelevant');
      })
      .length;
  final noSearchRetrievalCount = hybridCases
      .where((item) => !fixture.cases[item.caseId]!.shouldSearch)
      .where((item) => item.fusedRanking.isNotEmpty || item.groups.isNotEmpty)
      .length;
  final contextBudgetViolationCount = hybridCases
      .where((item) => item.totalContextTokens > rag3ContextBudgetTokens)
      .length;
  final provenanceViolationCount = hybridCases
      .expand((item) => item.groups)
      .where((item) => !item.provenanceValid)
      .length;

  final negativeControls = _evaluateNegativeControls(fixture);
  final gates = <String, bool>{
    'objectRecallAt10': hybridMetrics.objectRecallAt10 >= 0.85,
    'objectHitAt5': hybridMetrics.objectHitAt5 >= 0.85,
    'objectMrrAt10': hybridMetrics.objectMrrAt10 >= 0.65,
    'hybridBetterArmMisses': betterArmMissCount <= 1,
    'answerSupport': answerSupportCount >= 13 && answerCases.length == 14,
    'japaneseAnswerSupport':
        japaneseSupportCount == 4 && japaneseCases.length == 4,
    'abstentionSupport':
        abstentionSupportCount == 2 && abstentionCases.length == 2,
    'unavailableIrrelevantOnly': unavailableIrrelevantOnlyCount == 0,
    'contextBudget': contextBudgetViolationCount == 0,
    'noSearch': noSearchRetrievalCount == 0,
    'citationAndProvenance': provenanceViolationCount == 0,
    'emptyFusionNegativeControl': negativeControls.emptyFusionDetected,
    'budgetBypassNegativeControl': negativeControls.budgetBypassDetected,
    'vectorDegradation': hybridCases.every((item) => item.degradationValid),
  };
  return Rag3HybridReportCore(
    fixtureId: fixture.fixtureId,
    corpusHash: fixture.corpusHash,
    runId: run.runId,
    metadata: {
      for (final key in const [
        'buildCommit',
        'buildDirty',
        'hardware',
        'warmState',
        'tokenEstimateMethod',
      ])
        key: run.metadata[key],
    },
    hybridMetrics: hybridMetrics,
    lexicalMetrics: lexicalMetrics,
    vectorMetrics: vectorMetrics,
    cases: hybridCases,
    answerSupportCount: answerSupportCount,
    answerSupportCases: answerCases.length,
    japaneseSupportCount: japaneseSupportCount,
    japaneseSupportCases: japaneseCases.length,
    abstentionSupportCount: abstentionSupportCount,
    abstentionSupportCases: abstentionCases.length,
    unavailableIrrelevantOnlyCount: unavailableIrrelevantOnlyCount,
    betterArmMissCount: betterArmMissCount,
    noSearchRetrievalCount: noSearchRetrievalCount,
    contextBudgetViolationCount: contextBudgetViolationCount,
    provenanceViolationCount: provenanceViolationCount,
    negativeControls: negativeControls,
    gates: gates,
  );
}

enum Rag3EvaluationArm { lexical, vector, hybrid }

Rag3CaseEvaluation _evaluateCase(
  Rag3HybridFixture fixture,
  Rag3FixtureCase fixtureCase,
  Map<String, Object?> runCase,
  Rag3EvaluationArm arm,
) {
  if (!_boolean(runCase, 'submitted')) {
    return Rag3CaseEvaluation.empty(fixtureCase.id);
  }
  final lexical = _deduplicateRanking(
    _stringList(runCase, 'lexicalRankedChunkIds'),
  );
  final vectorJson = _object(runCase, 'vector');
  final vectorStatus = _string(vectorJson, 'status');
  final vector = vectorStatus == 'available'
      ? _deduplicateRanking(_stringList(vectorJson, 'rankedChunkIds'))
      : const <String>[];
  final ranking = switch (arm) {
    Rag3EvaluationArm.lexical => _singleArmRanking(lexical),
    Rag3EvaluationArm.vector => _singleArmRanking(vector),
    Rag3EvaluationArm.hybrid => _fuseRankings(lexical, vector),
  };
  final selection = _selectContext(fixture, ranking);
  final fingerprintDigest = _fingerprintDigest(
    _object(vectorJson, 'fingerprint'),
  );
  final status = arm == Rag3EvaluationArm.hybrid && vectorStatus != 'available'
      ? 'degraded'
      : 'available';
  final degradedReason = status == 'degraded'
      ? _string(vectorJson, 'degradedReason')
      : null;
  final selectedObjectIds = <String>[];
  for (final group in selection.groups) {
    if (!selectedObjectIds.contains(group.objectId)) {
      selectedObjectIds.add(group.objectId);
    }
  }
  final roles = <String>[
    for (final group in selection.groups)
      for (final chunkId in group.chunkIds) fixtureCase.roleFor(chunkId),
  ];
  final firstRelevant = selectedObjectIds
      .take(10)
      .toList()
      .indexWhere(fixtureCase.objectQrels.containsKey);
  final relevantAt10 = selectedObjectIds
      .take(10)
      .where(fixtureCase.objectQrels.containsKey)
      .toSet()
      .length;
  return Rag3CaseEvaluation(
    caseId: fixtureCase.id,
    status: status,
    degradedReason: degradedReason,
    fingerprintDigest: fingerprintDigest,
    fusedRanking: ranking,
    groups: selection.groups,
    exclusions: selection.exclusions,
    totalContextTokens: selection.totalTokens,
    objectRecallAt10: fixtureCase.objectQrels.isEmpty
        ? null
        : relevantAt10 / fixtureCase.objectQrels.length,
    hitAt5: selectedObjectIds.take(5).any(fixtureCase.objectQrels.containsKey),
    reciprocalRankAt10: firstRelevant < 0 ? 0 : 1 / (firstRelevant + 1),
    selectedRoles: roles,
    degradationValid: vectorStatus == 'available'
        ? status == 'available'
        : status == 'degraded' && degradedReason != null && vector.isEmpty,
    latencyMs: switch (arm) {
      Rag3EvaluationArm.lexical => _integer(runCase, 'lexicalLatencyMs'),
      Rag3EvaluationArm.vector => _integer(vectorJson, 'latencyMs'),
      Rag3EvaluationArm.hybrid => math.max(
        _integer(runCase, 'lexicalLatencyMs'),
        _integer(vectorJson, 'latencyMs'),
      ),
    },
    peakRssBytes: _integer(_object(runCase, 'resource'), 'peakRssBytes'),
    peakVramBytes: _integer(_object(runCase, 'resource'), 'peakVramBytes'),
  );
}

String _fingerprintDigest(Map<String, Object?> fingerprint) {
  final canonical = <String, Object?>{
    'schemaVersion': _integer(fingerprint, 'schemaVersion'),
    'endpointIdentity': _string(fingerprint, 'endpointIdentity'),
    'requestedModelId': _string(fingerprint, 'requestedModelId'),
    'responseModelId': _string(fingerprint, 'responseModelId'),
    'dimension': _integer(fingerprint, 'dimension'),
  };
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

String normalizeRag3EndpointIdentity(String raw) {
  final uri = Uri.parse(raw);
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('Embedding endpoint identity must be absolute.');
  }
  final scheme = uri.scheme.toLowerCase();
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final defaultPort =
      (scheme == 'http' && uri.port == 80) ||
      (scheme == 'https' && uri.port == 443);
  return Uri(
    scheme: scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort && !defaultPort ? uri.port : null,
    path: path,
  ).toString();
}

bool _isSafeRelativePath(String path) =>
    !path.startsWith('/') &&
    !path.contains('\\') &&
    !path.split('/').contains('..') &&
    !Uri.parse(path).hasScheme;

List<Rag3RankedChunk> _singleArmRanking(List<String> ranking) => [
  for (var index = 0; index < ranking.length; index++)
    Rag3RankedChunk(
      chunkId: ranking[index],
      rank: index + 1,
      score: 1 / (rag3RrfConstant + index + 1),
    ),
];

List<Rag3RankedChunk> _fuseRankings(List<String> lexical, List<String> vector) {
  final lexicalRanks = _rankMap(lexical);
  final vectorRanks = _rankMap(vector);
  final ids = {...lexicalRanks.keys, ...vectorRanks.keys};
  final ranked = <({String id, double score, int bestRank})>[];
  for (final id in ids) {
    final lexicalRank = lexicalRanks[id];
    final vectorRank = vectorRanks[id];
    final score =
        (lexicalRank == null ? 0.0 : 1 / (rag3RrfConstant + lexicalRank)) +
        (vectorRank == null ? 0.0 : 1 / (rag3RrfConstant + vectorRank));
    ranked.add((
      id: id,
      score: score,
      bestRank: math.min(
        lexicalRank ?? rag3MaxInputDepth + 1,
        vectorRank ?? rag3MaxInputDepth + 1,
      ),
    ));
  }
  ranked.sort((left, right) {
    final scoreOrder = right.score.compareTo(left.score);
    if (scoreOrder != 0) return scoreOrder;
    final rankOrder = left.bestRank.compareTo(right.bestRank);
    if (rankOrder != 0) return rankOrder;
    return left.id.compareTo(right.id);
  });
  return [
    for (var index = 0; index < ranked.length; index++)
      Rag3RankedChunk(
        chunkId: ranked[index].id,
        rank: index + 1,
        score: ranked[index].score,
      ),
  ];
}

Map<String, int> _rankMap(List<String> ranking) => {
  for (var index = 0; index < ranking.length; index++)
    ranking[index]: index + 1,
};

List<String> _deduplicateRanking(List<String> ranking) {
  final seen = <String>{};
  return [
    for (final id in ranking)
      if (seen.add(id)) id,
  ];
}

final class _SelectionResult {
  const _SelectionResult({
    required this.groups,
    required this.exclusions,
    required this.totalTokens,
  });

  final List<Rag3SelectedGroup> groups;
  final List<Map<String, Object?>> exclusions;
  final int totalTokens;
}

_SelectionResult _selectContext(
  Rag3HybridFixture fixture,
  List<Rag3RankedChunk> ranking, {
  bool enforceBudget = true,
  bool enforceDiversity = true,
}) {
  final rankByChunk = {for (final item in ranking) item.chunkId: item.rank};
  final chunksByObject = <String, List<Rag3Chunk>>{};
  for (final item in ranking) {
    final chunk = fixture.chunks[item.chunkId]!;
    chunksByObject.putIfAbsent(chunk.objectId, () => []).add(chunk);
  }
  final groups = <Rag3SelectedGroup>[];
  for (final entry in chunksByObject.entries) {
    final object = fixture.objects[entry.key]!;
    final sorted = [...entry.value]
      ..sort((left, right) {
        final start = left.lineStart.compareTo(right.lineStart);
        return start != 0 ? start : left.lineEnd.compareTo(right.lineEnd);
      });
    var component = <Rag3Chunk>[];
    void flush() {
      if (component.isEmpty) return;
      groups.add(_buildGroup(object, component, rankByChunk));
      component = <Rag3Chunk>[];
    }

    for (final chunk in sorted) {
      if (component.isNotEmpty &&
          chunk.lineStart >
              component.map((item) => item.lineEnd).reduce(math.max) + 1) {
        flush();
      }
      component.add(chunk);
    }
    flush();
  }
  groups.sort((left, right) {
    final rank = left.rank.compareTo(right.rank);
    if (rank != 0) return rank;
    final object = left.objectId.compareTo(right.objectId);
    if (object != 0) return object;
    return left.lineStart.compareTo(right.lineStart);
  });

  final selected = <Rag3SelectedGroup>[];
  final exclusions = <Map<String, Object?>>[];
  final countByObject = <String, int>{};
  var totalTokens = 0;
  for (final group in groups) {
    final objectCount = countByObject[group.objectId] ?? 0;
    if (enforceDiversity && objectCount >= rag3MaxGroupsPerObject) {
      exclusions.add({
        'groupId': group.groupId,
        'reason': 'object_diversity_cap',
      });
      continue;
    }
    if (enforceBudget &&
        totalTokens + group.estimatedTokens > rag3ContextBudgetTokens) {
      exclusions.add({'groupId': group.groupId, 'reason': 'context_budget'});
      continue;
    }
    selected.add(group);
    totalTokens += group.estimatedTokens;
    countByObject[group.objectId] = objectCount + 1;
  }
  return _SelectionResult(
    groups: List.unmodifiable(selected),
    exclusions: List.unmodifiable(exclusions),
    totalTokens: totalTokens,
  );
}

Rag3SelectedGroup _buildGroup(
  Rag3KnowledgeObject object,
  List<Rag3Chunk> chunks,
  Map<String, int> rankByChunk,
) {
  final start = chunks.map((item) => item.lineStart).reduce(math.min);
  final end = chunks.map((item) => item.lineEnd).reduce(math.max);
  final content = object.sourceLines.sublist(start - 1, end).join('\n');
  final contentHash = sha256.convert(utf8.encode(content)).toString();
  final citation =
      '[source=${object.sourcePath}; revision=${object.revision}; '
      'lines=$start-$end; object_sha256=${object.objectContentHash}; '
      'chunk_sha256=$contentHash]';
  return Rag3SelectedGroup(
    groupId: '${object.id}:$start-$end',
    objectId: object.id,
    sourcePath: object.sourcePath,
    lineStart: start,
    lineEnd: end,
    rank: chunks.map((item) => rankByChunk[item.id]!).reduce(math.min),
    chunkIds: List.unmodifiable(chunks.map((item) => item.id).toList()),
    contentHash: contentHash,
    citation: citation,
    estimatedTokens: (content.runes.length + citation.runes.length + 3) ~/ 4,
    provenanceValid:
        object.sourcePath.isNotEmpty &&
        !object.sourcePath.startsWith('/') &&
        object.revision.isNotEmpty &&
        object.objectContentHash.length == 64 &&
        contentHash.length == 64,
  );
}

final class Rag3RankedChunk {
  const Rag3RankedChunk({
    required this.chunkId,
    required this.rank,
    required this.score,
  });

  final String chunkId;
  final int rank;
  final double score;

  Map<String, Object?> toJson() => {
    'chunkId': chunkId,
    'rank': rank,
    'score': double.parse(score.toStringAsFixed(12)),
  };
}

final class Rag3SelectedGroup {
  const Rag3SelectedGroup({
    required this.groupId,
    required this.objectId,
    required this.sourcePath,
    required this.lineStart,
    required this.lineEnd,
    required this.rank,
    required this.chunkIds,
    required this.contentHash,
    required this.citation,
    required this.estimatedTokens,
    required this.provenanceValid,
  });

  final String groupId;
  final String objectId;
  final String sourcePath;
  final int lineStart;
  final int lineEnd;
  final int rank;
  final List<String> chunkIds;
  final String contentHash;
  final String citation;
  final int estimatedTokens;
  final bool provenanceValid;

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'objectId': objectId,
    'sourcePath': sourcePath,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
    'rank': rank,
    'chunkIds': chunkIds,
    'groupContentHash': contentHash,
    'citation': citation,
    'estimatedTokens': estimatedTokens,
    'provenanceValid': provenanceValid,
  };
}

final class Rag3CaseEvaluation {
  const Rag3CaseEvaluation({
    required this.caseId,
    required this.status,
    required this.degradedReason,
    required this.fingerprintDigest,
    required this.fusedRanking,
    required this.groups,
    required this.exclusions,
    required this.totalContextTokens,
    required this.objectRecallAt10,
    required this.hitAt5,
    required this.reciprocalRankAt10,
    required this.selectedRoles,
    required this.degradationValid,
    required this.latencyMs,
    required this.peakRssBytes,
    required this.peakVramBytes,
  });

  factory Rag3CaseEvaluation.empty(String caseId) => Rag3CaseEvaluation(
    caseId: caseId,
    status: 'not_submitted',
    degradedReason: null,
    fingerprintDigest: null,
    fusedRanking: const [],
    groups: const [],
    exclusions: const [],
    totalContextTokens: 0,
    objectRecallAt10: null,
    hitAt5: false,
    reciprocalRankAt10: 0,
    selectedRoles: const [],
    degradationValid: true,
    latencyMs: 0,
    peakRssBytes: 0,
    peakVramBytes: 0,
  );

  final String caseId;
  final String status;
  final String? degradedReason;
  final String? fingerprintDigest;
  final List<Rag3RankedChunk> fusedRanking;
  final List<Rag3SelectedGroup> groups;
  final List<Map<String, Object?>> exclusions;
  final int totalContextTokens;
  final double? objectRecallAt10;
  final bool hitAt5;
  final double reciprocalRankAt10;
  final List<String> selectedRoles;
  final bool degradationValid;
  final int latencyMs;
  final int peakRssBytes;
  final int peakVramBytes;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'status': status,
    if (degradedReason != null) 'degradedReason': degradedReason,
    if (fingerprintDigest != null)
      'embeddingFingerprintDigest': fingerprintDigest,
    'fusedRanking': [for (final item in fusedRanking) item.toJson()],
    'selectedGroups': [for (final item in groups) item.toJson()],
    'exclusions': exclusions,
    'totalContextTokens': totalContextTokens,
    'objectRecallAt10': objectRecallAt10,
    'hitAt5': hitAt5,
    'reciprocalRankAt10': reciprocalRankAt10,
    'selectedRoles': selectedRoles,
    'degradationValid': degradationValid,
    'latencyMs': latencyMs,
    'peakRssBytes': peakRssBytes,
    'peakVramBytes': peakVramBytes,
  };
}

final class Rag3ArmMetrics {
  const Rag3ArmMetrics({
    required this.objectRecallAt10,
    required this.objectHitAt5,
    required this.objectMrrAt10,
    required this.answerableCases,
    required this.totalLatencyMs,
    required this.peakRssBytes,
    required this.peakVramBytes,
  });

  final double objectRecallAt10;
  final double objectHitAt5;
  final double objectMrrAt10;
  final int answerableCases;
  final int totalLatencyMs;
  final int peakRssBytes;
  final int peakVramBytes;

  factory Rag3ArmMetrics.compute(
    Map<String, Rag3FixtureCase> fixtureCases,
    List<Rag3CaseEvaluation> evaluations,
  ) {
    final answerable = evaluations
        .where((item) => fixtureCases[item.caseId]!.answerable)
        .toList();
    if (answerable.isEmpty) {
      return Rag3ArmMetrics(
        objectRecallAt10: 0,
        objectHitAt5: 0,
        objectMrrAt10: 0,
        answerableCases: 0,
        totalLatencyMs: evaluations.fold(
          0,
          (sum, item) => sum + item.latencyMs,
        ),
        peakRssBytes: evaluations.fold(
          0,
          (peak, item) => math.max(peak, item.peakRssBytes),
        ),
        peakVramBytes: evaluations.fold(
          0,
          (peak, item) => math.max(peak, item.peakVramBytes),
        ),
      );
    }
    return Rag3ArmMetrics(
      objectRecallAt10:
          answerable.fold<double>(
            0,
            (sum, item) => sum + (item.objectRecallAt10 ?? 0),
          ) /
          answerable.length,
      objectHitAt5:
          answerable.where((item) => item.hitAt5).length / answerable.length,
      objectMrrAt10:
          answerable.fold<double>(
            0,
            (sum, item) => sum + item.reciprocalRankAt10,
          ) /
          answerable.length,
      answerableCases: answerable.length,
      totalLatencyMs: evaluations.fold(0, (sum, item) => sum + item.latencyMs),
      peakRssBytes: evaluations.fold(
        0,
        (peak, item) => math.max(peak, item.peakRssBytes),
      ),
      peakVramBytes: evaluations.fold(
        0,
        (peak, item) => math.max(peak, item.peakVramBytes),
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'objectRecallAt10': objectRecallAt10,
    'objectHitAt5': objectHitAt5,
    'objectMrrAt10': objectMrrAt10,
    'answerableCases': answerableCases,
    'totalLatencyMs': totalLatencyMs,
    'peakRssBytes': peakRssBytes,
    'peakVramBytes': peakVramBytes,
  };
}

final class Rag3NegativeControlResult {
  const Rag3NegativeControlResult({
    required this.emptyFusionDetected,
    required this.budgetBypassDetected,
    required this.budgetBypassTokens,
  });

  final bool emptyFusionDetected;
  final bool budgetBypassDetected;
  final int budgetBypassTokens;

  Map<String, Object?> toJson() => {
    'emptyFusion': {
      'expectedOutcome': 'fails_quality_gate',
      'detected': emptyFusionDetected,
    },
    'budgetBypass': {
      'expectedOutcome': 'fails_zero_budget_violation_gate',
      'detected': budgetBypassDetected,
      'contextTokens': budgetBypassTokens,
    },
  };
}

Rag3NegativeControlResult _evaluateNegativeControls(Rag3HybridFixture fixture) {
  final answerableCount = fixture.cases.values
      .where((item) => item.answerable)
      .length;
  final emptyFusionHitRate = answerableCount == 0 ? 1.0 : 0.0;
  final fullRanking = [
    for (var index = 0; index < fixture.chunks.length; index++)
      Rag3RankedChunk(
        chunkId: fixture.chunks.keys.elementAt(index),
        rank: index + 1,
        score: 1 / (rag3RrfConstant + index + 1),
      ),
  ];
  final bypass = _selectContext(
    fixture,
    fullRanking,
    enforceBudget: false,
    enforceDiversity: false,
  );
  return Rag3NegativeControlResult(
    emptyFusionDetected: emptyFusionHitRate < 0.85,
    budgetBypassDetected: bypass.totalTokens > rag3ContextBudgetTokens,
    budgetBypassTokens: bypass.totalTokens,
  );
}

final class Rag3HybridReportCore {
  const Rag3HybridReportCore({
    required this.fixtureId,
    required this.corpusHash,
    required this.runId,
    required this.metadata,
    required this.hybridMetrics,
    required this.lexicalMetrics,
    required this.vectorMetrics,
    required this.cases,
    required this.answerSupportCount,
    required this.answerSupportCases,
    required this.japaneseSupportCount,
    required this.japaneseSupportCases,
    required this.abstentionSupportCount,
    required this.abstentionSupportCases,
    required this.unavailableIrrelevantOnlyCount,
    required this.betterArmMissCount,
    required this.noSearchRetrievalCount,
    required this.contextBudgetViolationCount,
    required this.provenanceViolationCount,
    required this.negativeControls,
    required this.gates,
  });

  final String fixtureId;
  final String corpusHash;
  final String runId;
  final Map<String, Object?> metadata;
  final Rag3ArmMetrics hybridMetrics;
  final Rag3ArmMetrics lexicalMetrics;
  final Rag3ArmMetrics vectorMetrics;
  final List<Rag3CaseEvaluation> cases;
  final int answerSupportCount;
  final int answerSupportCases;
  final int japaneseSupportCount;
  final int japaneseSupportCases;
  final int abstentionSupportCount;
  final int abstentionSupportCases;
  final int unavailableIrrelevantOnlyCount;
  final int betterArmMissCount;
  final int noSearchRetrievalCount;
  final int contextBudgetViolationCount;
  final int provenanceViolationCount;
  final Rag3NegativeControlResult negativeControls;
  final Map<String, bool> gates;

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'runId': runId,
    'metadata': metadata,
    'arms': {
      'lexical': lexicalMetrics.toJson(),
      'vector': vectorMetrics.toJson(),
      'hybrid': hybridMetrics.toJson(),
    },
    'support': {
      'answer': {'retrieved': answerSupportCount, 'cases': answerSupportCases},
      'japaneseAnswer': {
        'retrieved': japaneseSupportCount,
        'cases': japaneseSupportCases,
      },
      'abstention': {
        'retrieved': abstentionSupportCount,
        'cases': abstentionSupportCases,
      },
      'unavailableIrrelevantOnly': unavailableIrrelevantOnlyCount,
    },
    'betterArmMissCount': betterArmMissCount,
    'noSearchRetrievalCount': noSearchRetrievalCount,
    'contextBudgetViolationCount': contextBudgetViolationCount,
    'provenanceViolationCount': provenanceViolationCount,
    'negativeControls': negativeControls.toJson(),
    'gates': gates,
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag3HybridReport {
  const Rag3HybridReport({
    required this.core,
    required this.deterministicReplayPassed,
  });

  final Rag3HybridReportCore core;
  final bool deterministicReplayPassed;
  bool get passed =>
      deterministicReplayPassed && core.gates.values.every((value) => value);

  Map<String, Object?> toJson() => {
    'schemaName': rag3ReportSchema,
    'schemaVersion': rag3SchemaVersion,
    'contractId': rag3ContractId,
    'candidateId': rag3CandidateId,
    'result': passed ? 'go' : 'no_go',
    ...core.toJson(),
    'deterministicReplayPassed': deterministicReplayPassed,
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG3 Offline Hybrid Evaluation')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Fixture: `${core.fixtureId}`')
      ..writeln('- Candidate: `$rag3CandidateId`')
      ..writeln('- Corpus SHA-256: `${core.corpusHash}`')
      ..writeln('- Deterministic replay: `$deterministicReplayPassed`')
      ..writeln()
      ..writeln('| Arm | Recall@10 | Hit@5 | MRR@10 |')
      ..writeln('| --- | ---: | ---: | ---: |');
    for (final entry in {
      'lexical': core.lexicalMetrics,
      'vector': core.vectorMetrics,
      'hybrid': core.hybridMetrics,
    }.entries) {
      buffer.writeln(
        '| ${entry.key} | ${entry.value.objectRecallAt10.toStringAsFixed(4)} | '
        '${entry.value.objectHitAt5.toStringAsFixed(4)} | '
        '${entry.value.objectMrrAt10.toStringAsFixed(4)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Gates')
      ..writeln();
    for (final entry in core.gates.entries) {
      buffer.writeln('- ${entry.key}: `${entry.value ? 'passed' : 'failed'}`');
    }
    return buffer.toString();
  }
}

void _requireSchema(Map<String, Object?> json, String expected) {
  if (_string(json, 'schemaName') != expected ||
      _integer(json, 'schemaVersion') != rag3SchemaVersion) {
    throw FormatException('Expected $expected schema v$rag3SchemaVersion.');
  }
}

Map<String, Object?> _decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) throw const FormatException('Expected a JSON object.');
  return decoded.cast<String, Object?>();
}

Map<String, Object?> _object(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! Map) throw FormatException('Expected object field $key.');
  return value.cast<String, Object?>();
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> source,
  String key,
) {
  final value = source[key];
  if (value is! List) throw FormatException('Expected list field $key.');
  return [
    for (final item in value)
      if (item is Map)
        item.cast<String, Object?>()
      else
        throw FormatException('Expected objects in $key.'),
  ];
}

List<String> _stringList(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Expected string list field $key.');
  }
  return value.cast<String>();
}

Map<String, int> _intMap(Map<String, Object?> source, String key) {
  final value = _object(source, key);
  if (value.values.any((item) => item is! int)) {
    throw FormatException('Expected integer values in $key.');
  }
  return value.cast<String, int>();
}

Map<String, String> _stringMap(Map<String, Object?> source, String key) {
  final value = _object(source, key);
  if (value.values.any((item) => item is! String)) {
    throw FormatException('Expected string values in $key.');
  }
  return value.cast<String, String>();
}

String _string(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected non-empty string field $key.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected optional string field $key.');
  }
  return value;
}

int _integer(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! int) throw FormatException('Expected integer field $key.');
  return value;
}

bool _boolean(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! bool) throw FormatException('Expected boolean field $key.');
  return value;
}
