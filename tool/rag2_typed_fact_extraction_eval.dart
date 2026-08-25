import 'dart:convert';
import 'dart:io';

import 'rag2_post_answer_claim_eval.dart';
import 'rag2_structured_claim_eval.dart';
import 'rag2_typed_fact_oracle_eval.dart';
import 'rag_retrieval_eval.dart';

const rag2TypedFactExtractionSchema = 'caverno_rag2_typed_fact_extraction_eval';
const rag2TypedFactExtractionSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2TypedFactExtractionOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_typed_fact_extraction_eval.dart '
      '--claims PATH --claim-atoms PATH --envelopes PATH '
      '--oracle-facts PATH --fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2TypedFactExtractionEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 typed-fact extraction evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2TypedFactExtractionReport> runRag2TypedFactExtractionEval(
  Rag2TypedFactExtractionOptions options,
) async {
  final claims = await Rag2ClaimCandidateSet.load(File(options.claimsPath));
  final claimAtoms = await Rag2TypedClaimAtomSet.load(
    File(options.claimAtomsPath),
  );
  final envelopes = await Rag2ClaimEnvelopeSet.load(
    File(options.envelopesPath),
  );
  final oracleFacts = await Rag2TypedEvidenceFactSet.load(
    File(options.oracleFactsPath),
  );
  final fixture = await RagRetrievalFixture.load(File(options.fixturePath));
  fixture.validate();
  final corpusHash = await fixture.computeCorpusHash();
  if (fixture.corpusHash != corpusHash) {
    throw StateError('Typed-fact extraction fixture corpus hash mismatch.');
  }
  envelopes.validate(claims);
  claimAtoms.validate(claims);
  await oracleFacts.validate(fixture, corpusHash);
  if (claims.datasetHashes[oracleFacts.datasetId] != corpusHash) {
    throw StateError('Typed-fact extraction candidate-set hash mismatch.');
  }

  final corpusRoot = Directory(
    '${fixture.sourceFile.parent.path}/${fixture.corpusRoot}',
  );
  final extractedFacts = await extractRag2TypedFacts(
    corpusRoot: corpusRoot,
    corpusHash: corpusHash,
  );
  final extractionMetrics = Rag2FactExtractionMetrics.compare(
    oracle: oracleFacts.facts,
    extracted: extractedFacts,
  );

  final cases = <Rag2ClaimVerificationCase>[];
  final decisions = <String, Rag2TypedFactDecision>{};
  for (final claim in claims.claims) {
    final decision = matchRag2TypedFact(
      claim: claimAtoms.byCandidateId[claim.id]!,
      envelope: envelopes.byCandidateId[claim.id]!,
      facts: extractedFacts,
    );
    decisions[claim.id] = decision;
    cases.add(
      Rag2ClaimVerificationCase(
        candidateId: claim.id,
        expected: claim.expectedVerdict,
        predicted: decision.verdict,
        coverage: decision.matchedFactIds.isEmpty ? 0 : 1,
        skeletonCoverage: decision.matchedFactIds.isEmpty ? 0 : 1,
        numericMismatch: false,
      ),
    );
  }
  final matcherResult = Rag2ClaimVerificationResult(
    fixtureId: fixture.fixtureId,
    corpusHash: corpusHash,
    policy: const Rag2ClaimVerifierPolicy(
      supportThreshold: 1,
      contradictionThreshold: 1,
    ),
    cases: cases,
  );
  final report = Rag2TypedFactExtractionReport(
    candidateSetId: claims.candidateSetId,
    atomSetId: claimAtoms.atomSetId,
    envelopeSetId: envelopes.envelopeSetId,
    oracleFactSetId: oracleFacts.factSetId,
    corpusHash: corpusHash,
    extractedFacts: extractedFacts,
    extraction: extractionMetrics,
    matcher: matcherResult,
    decisions: decisions,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<List<Rag2TypedEvidenceFact>> extractRag2TypedFacts({
  required Directory corpusRoot,
  required String corpusHash,
}) async {
  final files = corpusRoot.listSync(recursive: true).whereType<File>().toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final facts = <Rag2TypedEvidenceFact>[];
  for (final file in files) {
    final objectId = file.path.substring(corpusRoot.path.length + 1);
    final content = await file.readAsString();
    if (objectId.endsWith('.dart')) {
      facts.addAll(
        extractDartAssignmentFacts(
          content: content,
          objectId: objectId,
          corpusHash: corpusHash,
        ),
      );
    } else if (objectId.endsWith('.md')) {
      facts.addAll(
        extractMarkdownUriFacts(
          content: content,
          objectId: objectId,
          corpusHash: corpusHash,
        ),
      );
    }
  }
  return facts;
}

List<Rag2TypedEvidenceFact> extractDartAssignmentFacts({
  required String content,
  required String objectId,
  required String corpusHash,
}) {
  final assignment = RegExp(
    r'''^\s*const\s+([A-Za-z][A-Za-z0-9]*)\s*=\s*(.+);\s*$''',
  );
  final facts = <Rag2TypedEvidenceFact>[];
  final lines = const LineSplitter().convert(content);
  for (var index = 0; index < lines.length; index++) {
    final match = assignment.firstMatch(lines[index]);
    if (match == null) continue;
    final tokens = _identifierTokens(match.group(1)!);
    final value = _parseDartLiteral(match.group(2)!);
    if (tokens.length < 2 || value == null) continue;
    final relationName = tokens.removeLast();
    final subject = tokens.join('_');
    facts.add(
      Rag2TypedEvidenceFact(
        factId: 'extracted-dart-$subject-${index + 1}',
        atom: Rag2TypedAtom(
          subject: subject,
          relation: 'config.$relationName',
          value: value,
          scope: Rag2FactScope.current,
          polarity: Rag2FactPolarity.positive,
          modality: Rag2FactModality.asserted,
        ),
        source: Rag2FactSource(
          objectId: objectId,
          startLine: index + 1,
          endLine: index + 1,
        ),
        provenanceKind: 'deterministic_extractor',
        provenanceCorpusHash: corpusHash,
      ),
    );
  }
  return facts;
}

List<Rag2TypedEvidenceFact> extractMarkdownUriFacts({
  required String content,
  required String objectId,
  required String corpusHash,
}) {
  final uriPattern = RegExp(
    r'''https?://[A-Za-z0-9.-]+(?::[0-9]+)?(?:/[^\s`)]+)?''',
  );
  final labelPattern = RegExp(
    r'''([A-Za-z]+(?:\s+[A-Za-z]+){0,5})\s+(?:is\s+served\s+at|at|uses)\s*$''',
    caseSensitive: false,
  );
  final facts = <Rag2TypedEvidenceFact>[];
  for (final uriMatch in uriPattern.allMatches(content)) {
    final windowStart = uriMatch.start > 120 ? uriMatch.start - 120 : 0;
    final prefix = content
        .substring(windowStart, uriMatch.start)
        .replaceFirst(RegExp(r'''[`\s]+$'''), '');
    final matches = labelPattern.allMatches(prefix).toList();
    if (matches.isEmpty) continue;
    final labelMatch = matches.last;
    final rawLabel = labelMatch.group(1)!;
    final words = rawLabel.toLowerCase().split(RegExp(r'\s+'));
    final determiner = words.lastIndexOf('the');
    var subjectWords = determiner >= 0 ? words.sublist(determiner + 1) : words;
    if (subjectWords.length >= 2 &&
        subjectWords[subjectWords.length - 2] == 'is' &&
        subjectWords.last == 'served') {
      subjectWords = subjectWords.sublist(0, subjectWords.length - 2);
    }
    if (subjectWords.isEmpty) continue;
    final subject = subjectWords.join('_');
    final subjectText = subjectWords.join(' ');
    final subjectOffset = rawLabel.toLowerCase().lastIndexOf(subjectText);
    final rawLabelOffset = labelMatch.group(0)!.lastIndexOf(rawLabel);
    final labelOffset =
        windowStart + labelMatch.start + rawLabelOffset + subjectOffset;
    final uri = Uri.tryParse(uriMatch.group(0)!);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      continue;
    }
    final port = uri.port;
    facts.add(
      Rag2TypedEvidenceFact(
        factId: 'extracted-uri-$subject-${_lineAt(content, uriMatch.start)}',
        atom: Rag2TypedAtom(
          subject: subject,
          relation: 'network.port',
          value: Rag2TypedValue(type: Rag2FactValueType.integer, value: port),
          scope: Rag2FactScope.current,
          polarity: Rag2FactPolarity.positive,
          modality: Rag2FactModality.asserted,
        ),
        source: Rag2FactSource(
          objectId: objectId,
          startLine: _lineAt(content, labelOffset),
          endLine: _lineAt(content, uriMatch.end - 1),
        ),
        provenanceKind: 'deterministic_extractor',
        provenanceCorpusHash: corpusHash,
      ),
    );
  }
  return facts;
}

List<String> _identifierTokens(String identifier) => RegExp(
  r'[A-Z]?[a-z]+|[A-Z]+(?=[A-Z]|$)|[0-9]+',
).allMatches(identifier).map((match) => match.group(0)!.toLowerCase()).toList();

Rag2TypedValue? _parseDartLiteral(String source) {
  final value = source.trim();
  if ((value.startsWith("'") && value.endsWith("'")) ||
      (value.startsWith('"') && value.endsWith('"'))) {
    return Rag2TypedValue(
      type: Rag2FactValueType.string,
      value: value.substring(1, value.length - 1),
    );
  }
  final integer = int.tryParse(value);
  if (integer != null) {
    return Rag2TypedValue(type: Rag2FactValueType.integer, value: integer);
  }
  if (value == 'true' || value == 'false') {
    return Rag2TypedValue(
      type: Rag2FactValueType.boolean,
      value: value == 'true',
    );
  }
  return null;
}

int _lineAt(String content, int offset) =>
    '\n'.allMatches(content.substring(0, offset)).length + 1;

enum Rag2ExtractionSourceFamily { dartAssignment, markdownUri, proseState }

Rag2ExtractionSourceFamily rag2ExtractionSourceFamily(
  Rag2TypedEvidenceFact fact,
) {
  if (fact.source.objectId.endsWith('.dart')) {
    return Rag2ExtractionSourceFamily.dartAssignment;
  }
  if (fact.source.objectId.endsWith('.md') &&
      fact.atom.relation == 'network.port') {
    return Rag2ExtractionSourceFamily.markdownUri;
  }
  return Rag2ExtractionSourceFamily.proseState;
}

final class Rag2FactExtractionScore {
  const Rag2FactExtractionScore({
    required this.oracleCount,
    required this.extractedCount,
    required this.truePositiveCount,
  });

  final int oracleCount;
  final int extractedCount;
  final int truePositiveCount;

  double get precision =>
      extractedCount == 0 ? 0 : truePositiveCount / extractedCount;
  double get recall => oracleCount == 0 ? 0 : truePositiveCount / oracleCount;
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);
  bool get meetsGate => precision >= 0.95 && recall >= 0.90;

  Map<String, Object?> toJson() => {
    'oracleCount': oracleCount,
    'extractedCount': extractedCount,
    'truePositiveCount': truePositiveCount,
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'meetsGate': meetsGate,
  };
}

final class Rag2FactExtractionMetrics {
  const Rag2FactExtractionMetrics({
    required this.overall,
    required this.byFamily,
  });

  final Rag2FactExtractionScore overall;
  final Map<Rag2ExtractionSourceFamily, Rag2FactExtractionScore> byFamily;

  bool get meetsGate => byFamily.values.every((score) => score.meetsGate);

  static Rag2FactExtractionMetrics compare({
    required List<Rag2TypedEvidenceFact> oracle,
    required List<Rag2TypedEvidenceFact> extracted,
  }) {
    final oracleKeys = oracle.map(_factFingerprint).toSet();
    final extractedKeys = extracted.map(_factFingerprint).toSet();
    if (oracleKeys.length != oracle.length ||
        extractedKeys.length != extracted.length) {
      throw StateError('Typed-fact extraction inputs must be unique.');
    }
    Rag2FactExtractionScore score(
      List<Rag2TypedEvidenceFact> expected,
      List<Rag2TypedEvidenceFact> actual,
    ) {
      final expectedKeys = expected.map(_factFingerprint).toSet();
      final actualKeys = actual.map(_factFingerprint).toSet();
      return Rag2FactExtractionScore(
        oracleCount: expected.length,
        extractedCount: actual.length,
        truePositiveCount: actualKeys.intersection(expectedKeys).length,
      );
    }

    return Rag2FactExtractionMetrics(
      overall: score(oracle, extracted),
      byFamily: {
        for (final family in Rag2ExtractionSourceFamily.values)
          family: score(
            oracle
                .where((fact) => rag2ExtractionSourceFamily(fact) == family)
                .toList(),
            extracted
                .where((fact) => rag2ExtractionSourceFamily(fact) == family)
                .toList(),
          ),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'result': meetsGate ? 'go' : 'no_go',
    'overall': overall.toJson(),
    'bySourceFamily': {
      for (final entry in byFamily.entries)
        entry.key.name: entry.value.toJson(),
    },
  };
}

String _factFingerprint(Rag2TypedEvidenceFact fact) => jsonEncode({
  'subject': fact.atom.subject,
  'relation': fact.atom.relation,
  'valueType': fact.atom.value.type.name,
  'value': fact.atom.value.value,
  'scope': fact.atom.scope.name,
  'polarity': fact.atom.polarity.name,
  'modality': fact.atom.modality.name,
  'objectId': fact.source.objectId,
  'startLine': fact.source.startLine,
  'endLine': fact.source.endLine,
});

final class Rag2TypedFactExtractionReport {
  const Rag2TypedFactExtractionReport({
    required this.candidateSetId,
    required this.atomSetId,
    required this.envelopeSetId,
    required this.oracleFactSetId,
    required this.corpusHash,
    required this.extractedFacts,
    required this.extraction,
    required this.matcher,
    required this.decisions,
  });

  final String candidateSetId;
  final String atomSetId;
  final String envelopeSetId;
  final String oracleFactSetId;
  final String corpusHash;
  final List<Rag2TypedEvidenceFact> extractedFacts;
  final Rag2FactExtractionMetrics extraction;
  final Rag2ClaimVerificationResult matcher;
  final Map<String, Rag2TypedFactDecision> decisions;

  Map<String, Object?> toJson() => {
    'schemaName': rag2TypedFactExtractionSchema,
    'schemaVersion': rag2TypedFactExtractionSchemaVersion,
    'candidateSetId': candidateSetId,
    'atomSetId': atomSetId,
    'envelopeSetId': envelopeSetId,
    'oracleFactSetId': oracleFactSetId,
    'corpusHash': corpusHash,
    'result': 'no_go',
    'productionDecision': 'no_go',
    'extraction': extraction.toJson(),
    'downstreamMatcher': matcher.toJson(),
    'extractedFacts': [
      for (final fact in extractedFacts)
        {
          'factId': fact.factId,
          'subject': fact.atom.subject,
          'relation': fact.atom.relation,
          'valueType': fact.atom.value.type.name,
          'value': fact.atom.value.value,
          'scope': fact.atom.scope.name,
          'polarity': fact.atom.polarity.name,
          'modality': fact.atom.modality.name,
          'source': {
            'objectId': fact.source.objectId,
            'startLine': fact.source.startLine,
            'endLine': fact.source.endLine,
          },
          'provenance': {
            'kind': fact.provenanceKind,
            'corpusHash': fact.provenanceCorpusHash,
          },
        },
    ],
    'decisions': {
      for (final entry in decisions.entries) entry.key: entry.value.toJson(),
    },
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Typed Fact Extraction')
      ..writeln()
      ..writeln(
        '- Extraction result: `${extraction.meetsGate ? 'go' : 'no_go'}`',
      )
      ..writeln(
        '- Downstream matcher result: `${matcher.meetsGate ? 'go' : 'no_go'}`',
      )
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Source family | Precision | Recall | F1 | Extracted / Oracle | Gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | --- |');
    for (final entry in extraction.byFamily.entries) {
      final score = entry.value;
      buffer.writeln(
        '| `${entry.key.name}` | ${score.precision.toStringAsFixed(3)} | '
        '${score.recall.toStringAsFixed(3)} | ${score.f1.toStringAsFixed(3)} | '
        '${score.extractedCount} / ${score.oracleCount} | '
        '${score.meetsGate ? 'pass' : 'fail'} |',
      );
    }
    final overall = extraction.overall;
    buffer
      ..writeln(
        '| **Overall** | ${overall.precision.toStringAsFixed(3)} | '
        '${overall.recall.toStringAsFixed(3)} | '
        '${overall.f1.toStringAsFixed(3)} | '
        '${overall.extractedCount} / ${overall.oracleCount} | '
        '${extraction.meetsGate ? 'pass' : 'fail'} |',
      )
      ..writeln()
      ..writeln(
        '- Downstream claim macro F1: `${matcher.macroF1.toStringAsFixed(3)}`',
      );
    return buffer.toString();
  }
}

final class Rag2TypedFactExtractionOptions {
  const Rag2TypedFactExtractionOptions({
    required this.claimsPath,
    required this.claimAtomsPath,
    required this.envelopesPath,
    required this.oracleFactsPath,
    required this.fixturePath,
    required this.outDir,
  });

  final String claimsPath;
  final String claimAtomsPath;
  final String envelopesPath;
  final String oracleFactsPath;
  final String fixturePath;
  final String outDir;

  static Rag2TypedFactExtractionOptions? parse(List<String> args) {
    if (args.length != 12) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final required = [
      '--claims',
      '--claim-atoms',
      '--envelopes',
      '--oracle-facts',
      '--fixture',
      '--out-dir',
    ];
    if (required.any((key) => values[key] == null) || values.length != 6) {
      return null;
    }
    return Rag2TypedFactExtractionOptions(
      claimsPath: values['--claims']!,
      claimAtomsPath: values['--claim-atoms']!,
      envelopesPath: values['--envelopes']!,
      oracleFactsPath: values['--oracle-facts']!,
      fixturePath: values['--fixture']!,
      outDir: values['--out-dir']!,
    );
  }
}
