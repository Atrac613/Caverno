import 'dart:convert';
import 'dart:io';

import 'rag2_authority_claim_eval.dart';
import 'rag2_post_answer_claim_eval.dart';

const rag2StructuredClaimSchema = 'caverno_rag2_structured_claim_eval';
const rag2StructuredClaimSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2StructuredClaimOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_structured_claim_eval.dart '
      '--claims PATH --envelopes PATH --authority PATH '
      '--seed-fixture PATH --holdout-fixture PATH '
      '--audit-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2StructuredClaimEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 structured claim evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2StructuredClaimReport> runRag2StructuredClaimEval(
  Rag2StructuredClaimOptions options,
) async {
  final claimSet = await Rag2ClaimCandidateSet.load(File(options.claimsPath));
  final envelopes = await Rag2ClaimEnvelopeSet.load(
    File(options.envelopesPath),
  );
  final metadata = await Rag2EvidenceAuthoritySet.load(
    File(options.authorityPath),
  );
  envelopes.validate(claimSet);
  final results = <Rag2StructuredDatasetResult>[];
  for (final path in [
    options.seedFixturePath,
    options.holdoutFixturePath,
    options.auditFixturePath,
  ]) {
    final dataset = await loadRag2AuthorityDataset(path, claimSet, metadata);
    results.add(evaluateRag2StructuredDataset(dataset, envelopes));
  }
  final report = Rag2StructuredClaimReport(
    candidateSetId: claimSet.candidateSetId,
    envelopeSetId: envelopes.envelopeSetId,
    metadataId: metadata.metadataId,
    results: results,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_structured_claim_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_structured_claim_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag2StructuredDatasetResult evaluateRag2StructuredDataset(
  Rag2AuthorityDataset dataset,
  Rag2ClaimEnvelopeSet envelopes,
) {
  final cases = <Rag2ClaimVerificationCase>[];
  final reasons = <String, Rag2StructuredClaimDecision>{};
  for (final claim in dataset.claims) {
    final envelope = envelopes.byCandidateId[claim.id]!;
    final decision = verifyRag2StructuredClaim(
      claim: claim.claim,
      envelope: envelope,
      retrievedEvidence: dataset.evidenceByCase[claim.caseId] ?? const [],
    );
    reasons[claim.id] = decision;
    cases.add(
      Rag2ClaimVerificationCase(
        candidateId: claim.id,
        expected: claim.expectedVerdict,
        predicted: decision.verifierDecision.verdict,
        coverage: decision.verifierDecision.coverage,
        skeletonCoverage: decision.verifierDecision.skeletonCoverage,
        numericMismatch: decision.verifierDecision.numericMismatch,
      ),
    );
  }
  return Rag2StructuredDatasetResult(
    result: Rag2ClaimVerificationResult(
      fixtureId: dataset.fixture.fixtureId,
      corpusHash: dataset.corpusHash,
      policy: rag2FrozenClaimVerifierPolicy,
      cases: cases,
    ),
    decisions: reasons,
  );
}

Rag2StructuredClaimDecision verifyRag2StructuredClaim({
  required String claim,
  required Rag2ClaimEnvelope envelope,
  required List<Rag2AuthorityEvidence> retrievedEvidence,
}) {
  if (envelope.citedSourceIds.isEmpty) {
    return Rag2StructuredClaimDecision.absent('missing_citation');
  }
  final byId = {for (final item in retrievedEvidence) item.objectId: item};
  final cited = <Rag2AuthorityEvidence>[];
  for (final sourceId in envelope.citedSourceIds) {
    final evidence = byId[sourceId];
    if (evidence == null) {
      return Rag2StructuredClaimDecision.absent('cited_source_not_retrieved');
    }
    cited.add(evidence);
  }
  if (envelope.scope != Rag2ClaimScope.unspecified &&
      cited.any((item) => item.authority.name != envelope.scope.name)) {
    return Rag2StructuredClaimDecision.absent('authority_mismatch');
  }
  for (final item in cited) {
    final sameAuthority = retrievedEvidence.where(
      (candidate) => candidate.authority == item.authority,
    );
    final maximumRevision = sameAuthority
        .map((candidate) => candidate.revision)
        .reduce((a, b) => a > b ? a : b);
    if (item.revision < maximumRevision) {
      return Rag2StructuredClaimDecision.absent('superseded_revision');
    }
  }
  final decisions = [
    for (final item in cited)
      verifyRag2Claim(
        claim: claim,
        evidence: item.content,
        policy: rag2FrozenClaimVerifierPolicy,
      ),
  ];
  return Rag2StructuredClaimDecision(
    reason: 'verified_citations',
    verifierDecision: aggregateRag2AuthorityDecisions(decisions),
    citedEvidence: cited,
  );
}

enum Rag2ClaimScope { current, historical, unspecified }

final class Rag2ClaimEnvelope {
  const Rag2ClaimEnvelope({
    required this.candidateId,
    required this.scope,
    required this.citedSourceIds,
  });

  final String candidateId;
  final Rag2ClaimScope scope;
  final List<String> citedSourceIds;
}

final class Rag2ClaimEnvelopeSet {
  const Rag2ClaimEnvelopeSet({
    required this.envelopeSetId,
    required this.envelopes,
  });

  final String envelopeSetId;
  final List<Rag2ClaimEnvelope> envelopes;

  Map<String, Rag2ClaimEnvelope> get byCandidateId => {
    for (final item in envelopes) item.candidateId: item,
  };

  static Future<Rag2ClaimEnvelopeSet> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != 'caverno_rag2_claim_envelopes' ||
        json['schemaVersion'] != 1) {
      throw StateError('Unsupported RAG2 claim-envelope schema.');
    }
    return Rag2ClaimEnvelopeSet(
      envelopeSetId: json['envelopeSetId']! as String,
      envelopes: [
        for (final row in (json['envelopes'] as List).cast<Map>())
          _fromJson(row.cast<String, Object?>()),
      ],
    );
  }

  static Rag2ClaimEnvelope _fromJson(Map<String, Object?> json) =>
      Rag2ClaimEnvelope(
        candidateId: json['candidateId']! as String,
        scope: Rag2ClaimScope.values.byName(json['scope']! as String),
        citedSourceIds: (json['citedSourceIds'] as List).cast<String>(),
      );

  void validate(Rag2ClaimCandidateSet claims) {
    final claimIds = claims.claims.map((item) => item.id).toSet();
    final envelopeIds = envelopes.map((item) => item.candidateId).toSet();
    if (envelopeIds.length != envelopes.length ||
        claimIds.difference(envelopeIds).isNotEmpty ||
        envelopeIds.difference(claimIds).isNotEmpty) {
      throw StateError('Every fixed claim must have exactly one envelope.');
    }
  }
}

final class Rag2StructuredClaimDecision {
  const Rag2StructuredClaimDecision({
    required this.reason,
    required this.verifierDecision,
    required this.citedEvidence,
  });

  factory Rag2StructuredClaimDecision.absent(String reason) =>
      Rag2StructuredClaimDecision(
        reason: reason,
        verifierDecision: const Rag2ClaimVerifierDecision(
          verdict: Rag2ClaimVerdict.absent,
          coverage: 0,
          skeletonCoverage: 0,
          numericMismatch: false,
        ),
        citedEvidence: const [],
      );

  final String reason;
  final Rag2ClaimVerifierDecision verifierDecision;
  final List<Rag2AuthorityEvidence> citedEvidence;

  Map<String, Object?> toJson() => {
    'reason': reason,
    'verdict': verifierDecision.verdict.name,
    'citedSourceIds': [for (final item in citedEvidence) item.objectId],
  };
}

final class Rag2StructuredDatasetResult {
  const Rag2StructuredDatasetResult({
    required this.result,
    required this.decisions,
  });

  final Rag2ClaimVerificationResult result;
  final Map<String, Rag2StructuredClaimDecision> decisions;

  Map<String, Object?> toJson() => {
    'result': result.toJson(),
    'decisions': {
      for (final entry in decisions.entries) entry.key: entry.value.toJson(),
    },
  };
}

final class Rag2StructuredClaimReport {
  const Rag2StructuredClaimReport({
    required this.candidateSetId,
    required this.envelopeSetId,
    required this.metadataId,
    required this.results,
  });

  final String candidateSetId;
  final String envelopeSetId;
  final String metadataId;
  final List<Rag2StructuredDatasetResult> results;

  bool get passed => results.every((item) => item.result.meetsGate);

  Map<String, Object?> toJson() => {
    'schemaName': rag2StructuredClaimSchema,
    'schemaVersion': rag2StructuredClaimSchemaVersion,
    'candidateSetId': candidateSetId,
    'envelopeSetId': envelopeSetId,
    'metadataId': metadataId,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'verifierPolicy': rag2FrozenClaimVerifierPolicy.toJson(),
    'results': [for (final item in results) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Structured Claim Verification')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Claim envelope: explicit scope and cited source IDs')
      ..writeln()
      ..writeln(
        '| Dataset | Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | --- |');
    for (final item in results) {
      final metrics = item.result.metrics;
      buffer.writeln(
        '| ${item.result.fixtureId} | ${item.result.macroF1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.supported]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.contradicted]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.absent]!.f1.toStringAsFixed(3)} | '
        '${item.result.meetsGate ? 'pass' : 'fail'} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Residual errors')
      ..writeln()
      ..writeln('| Dataset | Candidate | Expected | Predicted | Reason |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final dataset in results) {
      for (final item in dataset.result.cases.where((item) => !item.correct)) {
        buffer.writeln(
          '| ${dataset.result.fixtureId} | ${item.candidateId} | '
          '${item.expected.name} | ${item.predicted.name} | '
          '${dataset.decisions[item.candidateId]!.reason} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'Missing or invalid citations fail closed before the unchanged lexical verifier runs. Envelope labels are fixed evaluation inputs and are not inferred from prose.',
      );
    return buffer.toString();
  }
}

final class Rag2StructuredClaimOptions {
  const Rag2StructuredClaimOptions({
    required this.claimsPath,
    required this.envelopesPath,
    required this.authorityPath,
    required this.seedFixturePath,
    required this.holdoutFixturePath,
    required this.auditFixturePath,
    required this.outDir,
  });

  final String claimsPath;
  final String envelopesPath;
  final String authorityPath;
  final String seedFixturePath;
  final String holdoutFixturePath;
  final String auditFixturePath;
  final String outDir;

  static Rag2StructuredClaimOptions? parse(List<String> args) {
    if (args.length != 14) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final claims = values['--claims'];
    final envelopes = values['--envelopes'];
    final authority = values['--authority'];
    final seed = values['--seed-fixture'];
    final holdout = values['--holdout-fixture'];
    final audit = values['--audit-fixture'];
    final outDir = values['--out-dir'];
    if ([
          claims,
          envelopes,
          authority,
          seed,
          holdout,
          audit,
          outDir,
        ].contains(null) ||
        values.length != 7) {
      return null;
    }
    return Rag2StructuredClaimOptions(
      claimsPath: claims!,
      envelopesPath: envelopes!,
      authorityPath: authority!,
      seedFixturePath: seed!,
      holdoutFixturePath: holdout!,
      auditFixturePath: audit!,
      outDir: outDir!,
    );
  }
}
