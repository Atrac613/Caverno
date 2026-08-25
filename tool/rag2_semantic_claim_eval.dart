import 'dart:convert';
import 'dart:io';

import 'rag2_authority_claim_eval.dart';
import 'rag2_post_answer_claim_eval.dart';
import 'rag2_structured_claim_eval.dart';

const rag2SemanticClaimSchema = 'caverno_rag2_semantic_claim_eval';
const rag2SemanticClaimSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2StructuredClaimOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_semantic_claim_eval.dart '
      '--claims PATH --envelopes PATH --authority PATH '
      '--seed-fixture PATH --holdout-fixture PATH '
      '--audit-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2SemanticClaimEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 semantic claim evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2SemanticClaimReport> runRag2SemanticClaimEval(
  Rag2StructuredClaimOptions options, {
  Rag2SemanticSupportVerifier verifier =
      const Rag2DeterministicSemanticSupportVerifier(),
}) async {
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
    results.add(evaluateRag2SemanticDataset(dataset, envelopes, verifier));
  }
  final report = Rag2SemanticClaimReport(
    candidateSetId: claimSet.candidateSetId,
    envelopeSetId: envelopes.envelopeSetId,
    metadataId: metadata.metadataId,
    verifierId: verifier.id,
    verifierAvailable: verifier.available,
    results: results,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_semantic_claim_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_semantic_claim_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag2StructuredDatasetResult evaluateRag2SemanticDataset(
  Rag2AuthorityDataset dataset,
  Rag2ClaimEnvelopeSet envelopes,
  Rag2SemanticSupportVerifier verifier,
) {
  final cases = <Rag2ClaimVerificationCase>[];
  final decisions = <String, Rag2StructuredClaimDecision>{};
  for (final claim in dataset.claims) {
    final structural = verifyRag2StructuredClaim(
      claim: claim.claim,
      envelope: envelopes.byCandidateId[claim.id]!,
      retrievedEvidence: dataset.evidenceByCase[claim.caseId] ?? const [],
    );
    final decision = structural.reason == 'verified_citations'
        ? _verifySemanticCitations(claim.claim, structural, verifier)
        : structural;
    decisions[claim.id] = decision;
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
    decisions: decisions,
  );
}

Rag2StructuredClaimDecision _verifySemanticCitations(
  String claim,
  Rag2StructuredClaimDecision structural,
  Rag2SemanticSupportVerifier verifier,
) {
  if (!verifier.available) {
    return Rag2StructuredClaimDecision.absent('semantic_verifier_unavailable');
  }
  final semanticDecisions = [
    for (final evidence in structural.citedEvidence)
      verifier.verify(claim: claim, evidence: evidence.content),
  ];
  return Rag2StructuredClaimDecision(
    reason: 'semantic_verified_citations',
    verifierDecision: aggregateRag2AuthorityDecisions(semanticDecisions),
    citedEvidence: structural.citedEvidence,
  );
}

abstract interface class Rag2SemanticSupportVerifier {
  String get id;
  bool get available;

  Rag2ClaimVerifierDecision verify({
    required String claim,
    required String evidence,
  });
}

final class Rag2DeterministicSemanticSupportVerifier
    implements Rag2SemanticSupportVerifier {
  const Rag2DeterministicSemanticSupportVerifier({this.available = true});

  @override
  final bool available;

  @override
  String get id => 'deterministic-atomic-facts-v1';

  @override
  Rag2ClaimVerifierDecision verify({
    required String claim,
    required String evidence,
  }) {
    if (!available) {
      throw StateError('Semantic verifier is unavailable.');
    }
    final lexical = verifyRag2Claim(
      claim: claim,
      evidence: evidence,
      policy: rag2FrozenClaimVerifierPolicy,
    );
    final claimTerms = _semanticTerms(claim);
    final evidenceTerms = _semanticTerms(evidence);
    final claimNumbers = _numbers(claim);
    final evidenceNumbers = _numbers(evidence);
    final numericMismatch =
        claimNumbers.isNotEmpty &&
        evidenceNumbers.isNotEmpty &&
        !evidenceNumbers.containsAll(claimNumbers);
    final semanticCoverage = _coverage(claimTerms, evidenceTerms);
    final claimSkeleton = claimTerms.difference(claimNumbers);
    final evidenceSkeleton = evidenceTerms.difference(evidenceNumbers);
    final skeletonCoverage = _coverage(claimSkeleton, evidenceSkeleton);
    final claimState = _booleanState(claim);
    final evidenceState = _booleanState(evidence);

    if (claimState != null &&
        evidenceState != null &&
        claimState != evidenceState &&
        skeletonCoverage >= rag2FrozenClaimVerifierPolicy.contradictionThreshold) {
      return Rag2ClaimVerifierDecision(
        verdict: Rag2ClaimVerdict.contradicted,
        coverage: semanticCoverage,
        skeletonCoverage: skeletonCoverage,
        numericMismatch: false,
      );
    }
    if (numericMismatch &&
        skeletonCoverage >= rag2FrozenClaimVerifierPolicy.contradictionThreshold) {
      return Rag2ClaimVerifierDecision(
        verdict: Rag2ClaimVerdict.contradicted,
        coverage: semanticCoverage,
        skeletonCoverage: skeletonCoverage,
        numericMismatch: true,
      );
    }
    if (semanticCoverage >= rag2FrozenClaimVerifierPolicy.supportThreshold) {
      return Rag2ClaimVerifierDecision(
        verdict: Rag2ClaimVerdict.supported,
        coverage: semanticCoverage,
        skeletonCoverage: skeletonCoverage,
        numericMismatch: false,
      );
    }
    return lexical;
  }
}

Set<String> _semanticTerms(String source) {
  final splitIdentifiers = source.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  final terms = RegExp(
    r'[a-z0-9]+(?:\.[a-z0-9]+)*',
    caseSensitive: false,
  ).allMatches(splitIdentifiers.toLowerCase()).map((match) {
    final term = match.group(0)!;
    return const {
          'initial': 'default',
          'defaults': 'default',
          'iteration': 'limit',
          'iterations': 'limit',
          'currently': 'current',
        }[term] ??
        term;
  }).where((term) => !const {
    'a',
    'an',
    'are',
    'at',
    'is',
    'it',
    'the',
    'to',
    'was',
    'were',
  }.contains(term)).toSet();
  if (RegExp(r'https?://[^\s`]+:\d+', caseSensitive: false).hasMatch(source)) {
    terms.add('port');
  }
  return terms;
}

bool? _booleanState(String source) {
  final normalized = source
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .toLowerCase();
  if (RegExp(r'\b(?:not|never)\s+disabled\b').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'\b(?:not|never)\s+enabled\b').hasMatch(normalized)) {
    return false;
  }
  if (RegExp(r'\benabled\b').hasMatch(normalized)) return true;
  if (RegExp(r'\bdisabled\b').hasMatch(normalized)) return false;
  return null;
}

Set<String> _numbers(String source) => RegExp(
  r'(?<![a-z0-9])\d+(?:\.\d+)?(?![a-z0-9])',
  caseSensitive: false,
).allMatches(source).map((match) => match.group(0)!).toSet();

double _coverage(Set<String> claim, Set<String> evidence) =>
    claim.isEmpty ? 0 : claim.intersection(evidence).length / claim.length;

final class Rag2SemanticClaimReport {
  const Rag2SemanticClaimReport({
    required this.candidateSetId,
    required this.envelopeSetId,
    required this.metadataId,
    required this.verifierId,
    required this.verifierAvailable,
    required this.results,
  });

  final String candidateSetId;
  final String envelopeSetId;
  final String metadataId;
  final String verifierId;
  final bool verifierAvailable;
  final List<Rag2StructuredDatasetResult> results;

  bool get passed => results.every((item) => item.result.meetsGate);

  Map<String, Object?> toJson() => {
    'schemaName': rag2SemanticClaimSchema,
    'schemaVersion': rag2SemanticClaimSchemaVersion,
    'candidateSetId': candidateSetId,
    'envelopeSetId': envelopeSetId,
    'metadataId': metadataId,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'verifier': {'id': verifierId, 'available': verifierAvailable},
    'verifierPolicy': rag2FrozenClaimVerifierPolicy.toJson(),
    'results': [for (final item in results) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Semantic Claim Verification')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Verifier: `$verifierId`')
      ..writeln('- Verifier available: `$verifierAvailable`')
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
      ..writeln();
    final errors = results
        .expand((dataset) => dataset.result.cases)
        .where((item) => !item.correct)
        .toList();
    if (errors.isEmpty) {
      buffer.writeln('None.');
    } else {
      for (final item in errors) {
        buffer.writeln(
          '- `${item.candidateId}`: expected `${item.expected.name}`, predicted `${item.predicted.name}`',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'Structural citation checks run first. An unavailable semantic verifier fails closed as absent; unresolved relations retain the frozen lexical verdict.',
      );
    return buffer.toString();
  }
}
