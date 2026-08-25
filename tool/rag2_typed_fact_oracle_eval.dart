import 'dart:convert';
import 'dart:io';

import 'rag2_post_answer_claim_eval.dart';
import 'rag2_structured_claim_eval.dart';
import 'rag_retrieval_eval.dart';

const rag2TypedFactOracleSchema = 'caverno_rag2_typed_fact_oracle_eval';
const rag2TypedFactOracleSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2TypedFactOracleOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_typed_fact_oracle_eval.dart '
      '--claims PATH --claim-atoms PATH --envelopes PATH '
      '--facts PATH --fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2TypedFactOracleEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 typed-fact oracle evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2TypedFactOracleReport> runRag2TypedFactOracleEval(
  Rag2TypedFactOracleOptions options,
) async {
  final claims = await Rag2ClaimCandidateSet.load(File(options.claimsPath));
  final claimAtoms = await Rag2TypedClaimAtomSet.load(
    File(options.claimAtomsPath),
  );
  final envelopes = await Rag2ClaimEnvelopeSet.load(
    File(options.envelopesPath),
  );
  final facts = await Rag2TypedEvidenceFactSet.load(File(options.factsPath));
  final fixture = await RagRetrievalFixture.load(File(options.fixturePath));
  fixture.validate();
  final corpusHash = await fixture.computeCorpusHash();
  if (fixture.corpusHash != corpusHash) {
    throw StateError('Typed-fact fixture corpus hash mismatch.');
  }
  envelopes.validate(claims);
  claimAtoms.validate(claims);
  await facts.validate(fixture, corpusHash);
  if (claims.datasetHashes[facts.datasetId] != corpusHash) {
    throw StateError('Typed-fact candidate-set hash mismatch.');
  }

  final cases = <Rag2ClaimVerificationCase>[];
  final decisions = <String, Rag2TypedFactDecision>{};
  for (final claim in claims.claims) {
    final decision = matchRag2TypedFact(
      claim: claimAtoms.byCandidateId[claim.id]!,
      envelope: envelopes.byCandidateId[claim.id]!,
      facts: facts.facts,
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
  final result = Rag2ClaimVerificationResult(
    fixtureId: fixture.fixtureId,
    corpusHash: corpusHash,
    policy: const Rag2ClaimVerifierPolicy(
      supportThreshold: 1,
      contradictionThreshold: 1,
    ),
    cases: cases,
  );
  final report = Rag2TypedFactOracleReport(
    candidateSetId: claims.candidateSetId,
    atomSetId: claimAtoms.atomSetId,
    envelopeSetId: envelopes.envelopeSetId,
    factSetId: facts.factSetId,
    result: result,
    decisions: decisions,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_typed_fact_oracle_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_typed_fact_oracle_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag2TypedFactDecision matchRag2TypedFact({
  required Rag2TypedClaimAtom claim,
  required Rag2ClaimEnvelope envelope,
  required List<Rag2TypedEvidenceFact> facts,
}) {
  final cited = facts.where(
    (fact) => envelope.citedSourceIds.contains(fact.source.objectId),
  );
  final sameRelation = cited.where(
    (fact) =>
        fact.atom.subject == claim.atom.subject &&
        fact.atom.relation == claim.atom.relation &&
        fact.atom.scope == claim.atom.scope,
  );
  final asserted = sameRelation
      .where((fact) => fact.atom.modality == Rag2FactModality.asserted)
      .toList();
  if (asserted.isEmpty) {
    return const Rag2TypedFactDecision(
      verdict: Rag2ClaimVerdict.absent,
      reason: 'no_asserted_typed_fact',
      matchedFactIds: [],
    );
  }
  final exact = asserted.where(
    (fact) =>
        fact.atom.value == claim.atom.value &&
        fact.atom.polarity == claim.atom.polarity,
  );
  if (exact.isNotEmpty) {
    return Rag2TypedFactDecision(
      verdict: Rag2ClaimVerdict.supported,
      reason: 'exact_typed_fact',
      matchedFactIds: exact.map((fact) => fact.factId).toList(),
    );
  }
  return Rag2TypedFactDecision(
    verdict: Rag2ClaimVerdict.contradicted,
    reason: 'conflicting_typed_fact',
    matchedFactIds: asserted.map((fact) => fact.factId).toList(),
  );
}

enum Rag2FactValueType { string, integer, boolean, uri }

enum Rag2FactScope { current, historical, unspecified }

enum Rag2FactPolarity { positive, negative }

enum Rag2FactModality { asserted, conditional, modal, normative }

final class Rag2TypedValue {
  const Rag2TypedValue({required this.type, required this.value});

  final Rag2FactValueType type;
  final Object value;

  static Rag2TypedValue fromJson(Map<String, Object?> json) {
    final type = Rag2FactValueType.values.byName(json['valueType']! as String);
    final value = json['value']!;
    final valid = switch (type) {
      Rag2FactValueType.string || Rag2FactValueType.uri => value is String,
      Rag2FactValueType.integer => value is int,
      Rag2FactValueType.boolean => value is bool,
    };
    if (!valid) throw StateError('Typed fact value does not match valueType.');
    return Rag2TypedValue(type: type, value: value);
  }

  @override
  bool operator ==(Object other) =>
      other is Rag2TypedValue && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);
}

final class Rag2TypedAtom {
  const Rag2TypedAtom({
    required this.subject,
    required this.relation,
    required this.value,
    required this.scope,
    required this.polarity,
    required this.modality,
  });

  final String subject;
  final String relation;
  final Rag2TypedValue value;
  final Rag2FactScope scope;
  final Rag2FactPolarity polarity;
  final Rag2FactModality modality;

  static Rag2TypedAtom fromJson(Map<String, Object?> json) => Rag2TypedAtom(
    subject: json['subject']! as String,
    relation: json['relation']! as String,
    value: Rag2TypedValue.fromJson(json),
    scope: Rag2FactScope.values.byName(json['scope']! as String),
    polarity: Rag2FactPolarity.values.byName(json['polarity']! as String),
    modality: Rag2FactModality.values.byName(json['modality']! as String),
  );
}

final class Rag2TypedClaimAtom {
  const Rag2TypedClaimAtom({
    required this.candidateId,
    required this.claimText,
    required this.atom,
  });

  final String candidateId;
  final String claimText;
  final Rag2TypedAtom atom;
}

final class Rag2TypedClaimAtomSet {
  const Rag2TypedClaimAtomSet({
    required this.atomSetId,
    required this.candidateSetId,
    required this.atoms,
  });

  final String atomSetId;
  final String candidateSetId;
  final List<Rag2TypedClaimAtom> atoms;

  Map<String, Rag2TypedClaimAtom> get byCandidateId => {
    for (final atom in atoms) atom.candidateId: atom,
  };

  static Future<Rag2TypedClaimAtomSet> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != 'caverno_rag2_typed_claim_atoms' ||
        json['schemaVersion'] != 1) {
      throw StateError('Unsupported RAG2 typed claim-atom schema.');
    }
    return Rag2TypedClaimAtomSet(
      atomSetId: json['atomSetId']! as String,
      candidateSetId: json['candidateSetId']! as String,
      atoms: [
        for (final row in (json['atoms'] as List).cast<Map>())
          _claimAtom(row.cast<String, Object?>()),
      ],
    );
  }

  static Rag2TypedClaimAtom _claimAtom(Map<String, Object?> json) =>
      Rag2TypedClaimAtom(
        candidateId: json['candidateId']! as String,
        claimText: json['claimText']! as String,
        atom: Rag2TypedAtom.fromJson(json),
      );

  void validate(Rag2ClaimCandidateSet claims) {
    if (candidateSetId != claims.candidateSetId ||
        atoms.length != claims.claims.length ||
        byCandidateId.length != atoms.length) {
      throw StateError('Typed claim atoms must cover the candidate set once.');
    }
    for (final claim in claims.claims) {
      final atom = byCandidateId[claim.id];
      if (atom == null || atom.claimText != claim.claim) {
        throw StateError('Typed claim atom text does not match its candidate.');
      }
    }
  }
}

final class Rag2FactSource {
  const Rag2FactSource({
    required this.objectId,
    required this.startLine,
    required this.endLine,
  });

  final String objectId;
  final int startLine;
  final int endLine;
}

final class Rag2TypedEvidenceFact {
  const Rag2TypedEvidenceFact({
    required this.factId,
    required this.atom,
    required this.source,
    required this.provenanceKind,
    required this.provenanceCorpusHash,
  });

  final String factId;
  final Rag2TypedAtom atom;
  final Rag2FactSource source;
  final String provenanceKind;
  final String provenanceCorpusHash;
}

final class Rag2TypedEvidenceFactSet {
  const Rag2TypedEvidenceFactSet({
    required this.factSetId,
    required this.datasetId,
    required this.corpusHash,
    required this.facts,
  });

  final String factSetId;
  final String datasetId;
  final String corpusHash;
  final List<Rag2TypedEvidenceFact> facts;

  static Future<Rag2TypedEvidenceFactSet> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != 'caverno_rag2_typed_evidence_facts' ||
        json['schemaVersion'] != 1) {
      throw StateError('Unsupported RAG2 typed evidence-fact schema.');
    }
    return Rag2TypedEvidenceFactSet(
      factSetId: json['factSetId']! as String,
      datasetId: json['datasetId']! as String,
      corpusHash: json['corpusHash']! as String,
      facts: [
        for (final row in (json['facts'] as List).cast<Map>())
          _fact(row.cast<String, Object?>()),
      ],
    );
  }

  static Rag2TypedEvidenceFact _fact(Map<String, Object?> json) {
    final source = (json['source'] as Map).cast<String, Object?>();
    final provenance = (json['provenance'] as Map).cast<String, Object?>();
    return Rag2TypedEvidenceFact(
      factId: json['factId']! as String,
      atom: Rag2TypedAtom.fromJson(json),
      source: Rag2FactSource(
        objectId: source['objectId']! as String,
        startLine: source['startLine']! as int,
        endLine: source['endLine']! as int,
      ),
      provenanceKind: provenance['kind']! as String,
      provenanceCorpusHash: provenance['corpusHash']! as String,
    );
  }

  Future<void> validate(RagRetrievalFixture fixture, String actualHash) async {
    if (datasetId != fixture.fixtureId ||
        corpusHash != actualHash ||
        facts.map((fact) => fact.factId).toSet().length != facts.length) {
      throw StateError('Typed evidence-fact identity is invalid.');
    }
    final root = Directory(
      '${fixture.sourceFile.parent.path}/${fixture.corpusRoot}',
    );
    for (final fact in facts) {
      if (fact.provenanceKind != 'oracle_annotation' ||
          fact.provenanceCorpusHash != actualHash ||
          fact.source.startLine < 1 ||
          fact.source.endLine < fact.source.startLine) {
        throw StateError('Typed evidence-fact provenance is invalid.');
      }
      final file = File('${root.path}/${fact.source.objectId}');
      if (!file.existsSync() ||
          fact.source.endLine >
              await file.readAsLines().then((lines) => lines.length)) {
        throw StateError('Typed evidence-fact source span is invalid.');
      }
    }
  }
}

final class Rag2TypedFactDecision {
  const Rag2TypedFactDecision({
    required this.verdict,
    required this.reason,
    required this.matchedFactIds,
  });

  final Rag2ClaimVerdict verdict;
  final String reason;
  final List<String> matchedFactIds;

  Map<String, Object?> toJson() => {
    'verdict': verdict.name,
    'reason': reason,
    'matchedFactIds': matchedFactIds,
  };
}

final class Rag2TypedFactOracleReport {
  const Rag2TypedFactOracleReport({
    required this.candidateSetId,
    required this.atomSetId,
    required this.envelopeSetId,
    required this.factSetId,
    required this.result,
    required this.decisions,
  });

  final String candidateSetId;
  final String atomSetId;
  final String envelopeSetId;
  final String factSetId;
  final Rag2ClaimVerificationResult result;
  final Map<String, Rag2TypedFactDecision> decisions;

  bool get passed => result.meetsGate;

  Map<String, Object?> toJson() => {
    'schemaName': rag2TypedFactOracleSchema,
    'schemaVersion': rag2TypedFactOracleSchemaVersion,
    'candidateSetId': candidateSetId,
    'atomSetId': atomSetId,
    'envelopeSetId': envelopeSetId,
    'factSetId': factSetId,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'extractionDecision': 'not_evaluated',
    'matcher': result.toJson(),
    'decisions': {
      for (final entry in decisions.entries) entry.key: entry.value.toJson(),
    },
  };

  String toMarkdown() {
    final metrics = result.metrics;
    final buffer = StringBuffer()
      ..writeln('# RAG2 Typed Evidence-Fact Oracle')
      ..writeln()
      ..writeln('- Matcher result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Extraction decision: `not_evaluated`')
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |',
      )
      ..writeln('| ---: | ---: | ---: | ---: | --- |')
      ..writeln(
        '| ${result.macroF1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.supported]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.contradicted]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.absent]!.f1.toStringAsFixed(3)} | '
        '${passed ? 'pass' : 'fail'} |',
      );
    return buffer.toString();
  }
}

final class Rag2TypedFactOracleOptions {
  const Rag2TypedFactOracleOptions({
    required this.claimsPath,
    required this.claimAtomsPath,
    required this.envelopesPath,
    required this.factsPath,
    required this.fixturePath,
    required this.outDir,
  });

  final String claimsPath;
  final String claimAtomsPath;
  final String envelopesPath;
  final String factsPath;
  final String fixturePath;
  final String outDir;

  static Rag2TypedFactOracleOptions? parse(List<String> args) {
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
      '--facts',
      '--fixture',
      '--out-dir',
    ];
    if (required.any((key) => values[key] == null) || values.length != 6) {
      return null;
    }
    return Rag2TypedFactOracleOptions(
      claimsPath: values['--claims']!,
      claimAtomsPath: values['--claim-atoms']!,
      envelopesPath: values['--envelopes']!,
      factsPath: values['--facts']!,
      fixturePath: values['--fixture']!,
      outDir: values['--out-dir']!,
    );
  }
}
