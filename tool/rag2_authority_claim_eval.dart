import 'dart:convert';
import 'dart:io';

import 'rag2_claim_support_eval.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag2_post_answer_claim_eval.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2AuthorityClaimSchema = 'caverno_rag2_authority_claim_eval';
const rag2AuthorityClaimSchemaVersion = 1;
const rag2FrozenClaimVerifierPolicy = Rag2ClaimVerifierPolicy(
  supportThreshold: 0.90,
  contradictionThreshold: 0.50,
);

Future<void> main(List<String> args) async {
  final options = Rag2AuthorityClaimOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_authority_claim_eval.dart '
      '--claims PATH --authority PATH --seed-fixture PATH '
      '--holdout-fixture PATH --audit-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2AuthorityClaimEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 authority claim evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2AuthorityClaimReport> runRag2AuthorityClaimEval(
  Rag2AuthorityClaimOptions options,
) async {
  final claimSet = await Rag2ClaimCandidateSet.load(File(options.claimsPath));
  final metadata = await Rag2EvidenceAuthoritySet.load(
    File(options.authorityPath),
  );
  final datasets = <Rag2AuthorityDataset>[];
  for (final path in [
    options.seedFixturePath,
    options.holdoutFixturePath,
    options.auditFixturePath,
  ]) {
    datasets.add(await loadRag2AuthorityDataset(path, claimSet, metadata));
  }
  claimSet.validate({
    for (final dataset in datasets)
      dataset.fixture.fixtureId: Rag2ClaimCorpus(
        fixture: dataset.fixture,
        corpusHash: dataset.corpusHash,
        claims: dataset.claims,
        evidenceByCase: {
          for (final entry in dataset.evidenceByCase.entries)
            entry.key: entry.value.map((item) => item.content).join('\n'),
        },
      ),
  });
  final results = [
    for (final dataset in datasets) evaluateRag2AuthorityDataset(dataset),
  ];
  final report = Rag2AuthorityClaimReport(
    candidateSetId: claimSet.candidateSetId,
    metadataId: metadata.metadataId,
    results: results,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_authority_claim_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_authority_claim_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2AuthorityDataset> loadRag2AuthorityDataset(
  String fixturePath,
  Rag2ClaimCandidateSet claimSet,
  Rag2EvidenceAuthoritySet metadata,
) async {
  final fixture = await RagRetrievalFixture.load(File(fixturePath));
  fixture.validate();
  final corpusHash = await fixture.computeCorpusHash();
  if (corpusHash != fixture.corpusHash) {
    throw StateError(
      'Fixture ${fixture.fixtureId} corpus hash mismatch: $corpusHash.',
    );
  }
  final datasetMetadata = metadata.datasets[fixture.fixtureId];
  if (datasetMetadata == null) {
    throw StateError('Missing authority metadata for ${fixture.fixtureId}.');
  }
  final documents = await loadRagFixtureDocuments(fixture);
  final documentIds = documents.map((item) => item.objectId).toSet();
  if (datasetMetadata.keys.toSet().difference(documentIds).isNotEmpty ||
      documentIds.difference(datasetMetadata.keys.toSet()).isNotEmpty) {
    throw StateError(
      'Authority metadata must cover every object in ${fixture.fixtureId}.',
    );
  }
  final scorer = Rag2LexicalScorer(
    policy: Rag2LexicalPolicy.trigram,
    documents: documents,
  );
  try {
    final evidenceByCase = <String, List<Rag2AuthorityEvidence>>{};
    final queries = <String, String>{};
    for (final fixtureCase in fixture.cases) {
      if (!claimSet.claims.any(
        (item) =>
            item.datasetId == fixture.fixtureId &&
            item.caseId == fixtureCase.id,
      )) {
        continue;
      }
      queries[fixtureCase.id] = fixtureCase.query;
      final hits = applyRag2FrozenSufficiencyPolicy(
        scorer.rank(fixtureCase.query, limit: documents.length),
        metricK: fixture.metricK,
      );
      evidenceByCase[fixtureCase.id] = [
        for (final hit in hits)
          Rag2AuthorityEvidence(
            objectId: hit.objectId,
            content: documents
                .firstWhere((item) => item.objectId == hit.objectId)
                .content,
            authority: datasetMetadata[hit.objectId]!.authority,
            revision: datasetMetadata[hit.objectId]!.revision,
          ),
      ];
    }
    return Rag2AuthorityDataset(
      fixture: fixture,
      corpusHash: corpusHash,
      claims: claimSet.claims
          .where((item) => item.datasetId == fixture.fixtureId)
          .toList(),
      queries: queries,
      evidenceByCase: evidenceByCase,
    );
  } finally {
    scorer.close();
  }
}

Rag2AuthorityDatasetResult evaluateRag2AuthorityDataset(
  Rag2AuthorityDataset dataset,
) {
  final baselineCases = <Rag2ClaimVerificationCase>[];
  final authorityCases = <Rag2ClaimVerificationCase>[];
  final selections = <String, Rag2AuthoritySelection>{};
  for (final claim in dataset.claims) {
    final evidence = dataset.evidenceByCase[claim.caseId] ?? const [];
    final baseline = verifyRag2Claim(
      claim: claim.claim,
      evidence: evidence.map((item) => item.content).join('\n'),
      policy: rag2FrozenClaimVerifierPolicy,
    );
    baselineCases.add(_case(claim, baseline));
    final selection = selectRag2AuthorityEvidence(
      claim: claim.claim,
      query: dataset.queries[claim.caseId]!,
      evidence: evidence,
    );
    selections[claim.id] = selection;
    final decisions = [
      for (final item in selection.evidence)
        verifyRag2Claim(
          claim: claim.claim,
          evidence: item.content,
          policy: rag2FrozenClaimVerifierPolicy,
        ),
    ];
    final decision = aggregateRag2AuthorityDecisions(decisions);
    authorityCases.add(_case(claim, decision));
  }
  return Rag2AuthorityDatasetResult(
    baseline: Rag2ClaimVerificationResult(
      fixtureId: dataset.fixture.fixtureId,
      corpusHash: dataset.corpusHash,
      policy: rag2FrozenClaimVerifierPolicy,
      cases: baselineCases,
    ),
    authorityAware: Rag2ClaimVerificationResult(
      fixtureId: dataset.fixture.fixtureId,
      corpusHash: dataset.corpusHash,
      policy: rag2FrozenClaimVerifierPolicy,
      cases: authorityCases,
    ),
    selections: selections,
  );
}

Rag2ClaimVerificationCase _case(
  Rag2ClaimCandidate claim,
  Rag2ClaimVerifierDecision decision,
) => Rag2ClaimVerificationCase(
  candidateId: claim.id,
  expected: claim.expectedVerdict,
  predicted: decision.verdict,
  coverage: decision.coverage,
  skeletonCoverage: decision.skeletonCoverage,
  numericMismatch: decision.numericMismatch,
);

Rag2AuthoritySelection selectRag2AuthorityEvidence({
  required String claim,
  required String query,
  required List<Rag2AuthorityEvidence> evidence,
}) {
  final requested = inferRag2RequestedAuthority('$query\n$claim');
  final matching = evidence
      .where((item) => item.authority == requested)
      .toList();
  final candidates = matching.isEmpty ? evidence : matching;
  if (candidates.isEmpty) {
    return Rag2AuthoritySelection(
      requestedAuthority: requested,
      evidence: const [],
    );
  }
  final maximumRevision = candidates
      .map((item) => item.revision)
      .reduce((a, b) => a > b ? a : b);
  return Rag2AuthoritySelection(
    requestedAuthority: requested,
    evidence: candidates
        .where((item) => item.revision == maximumRevision)
        .toList(),
  );
}

Rag2EvidenceAuthority inferRag2RequestedAuthority(String source) {
  final normalized = source.toLowerCase();
  if (RegExp(
    r'\b(current|currently|default|now|authoritative)\b',
  ).hasMatch(normalized)) {
    return Rag2EvidenceAuthority.current;
  }
  if (RegExp(
    r'\b(former|formerly|prototype|historical|previously|once)\b',
  ).hasMatch(normalized)) {
    return Rag2EvidenceAuthority.historical;
  }
  return Rag2EvidenceAuthority.current;
}

Rag2ClaimVerifierDecision aggregateRag2AuthorityDecisions(
  List<Rag2ClaimVerifierDecision> decisions,
) {
  if (decisions.isEmpty) {
    return const Rag2ClaimVerifierDecision(
      verdict: Rag2ClaimVerdict.absent,
      coverage: 0,
      skeletonCoverage: 0,
      numericMismatch: false,
    );
  }
  Rag2ClaimVerifierDecision? best(Rag2ClaimVerdict verdict) {
    final matches = decisions.where((item) => item.verdict == verdict).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.coverage.compareTo(a.coverage));
    return matches.first;
  }

  return best(Rag2ClaimVerdict.supported) ??
      best(Rag2ClaimVerdict.contradicted) ??
      best(Rag2ClaimVerdict.absent)!;
}

enum Rag2EvidenceAuthority { current, historical }

final class Rag2AuthorityMetadata {
  const Rag2AuthorityMetadata({
    required this.authority,
    required this.revision,
  });

  final Rag2EvidenceAuthority authority;
  final int revision;
}

final class Rag2EvidenceAuthoritySet {
  const Rag2EvidenceAuthoritySet({
    required this.metadataId,
    required this.datasets,
  });

  final String metadataId;
  final Map<String, Map<String, Rag2AuthorityMetadata>> datasets;

  static Future<Rag2EvidenceAuthoritySet> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != 'caverno_rag2_evidence_authority' ||
        json['schemaVersion'] != 1) {
      throw StateError('Unsupported RAG2 evidence-authority schema.');
    }
    final datasets = (json['datasets'] as Map).cast<String, Object?>();
    return Rag2EvidenceAuthoritySet(
      metadataId: json['metadataId']! as String,
      datasets: {
        for (final dataset in datasets.entries)
          dataset.key: {
            for (final object in (dataset.value as Map).entries)
              object.key as String: _metadata(
                (object.value as Map).cast<String, Object?>(),
              ),
          },
      },
    );
  }

  static Rag2AuthorityMetadata _metadata(Map<String, Object?> json) =>
      Rag2AuthorityMetadata(
        authority: Rag2EvidenceAuthority.values.byName(
          json['authority']! as String,
        ),
        revision: json['revision']! as int,
      );
}

final class Rag2AuthorityEvidence {
  const Rag2AuthorityEvidence({
    required this.objectId,
    required this.content,
    required this.authority,
    required this.revision,
  });

  final String objectId;
  final String content;
  final Rag2EvidenceAuthority authority;
  final int revision;
}

final class Rag2AuthoritySelection {
  const Rag2AuthoritySelection({
    required this.requestedAuthority,
    required this.evidence,
  });

  final Rag2EvidenceAuthority requestedAuthority;
  final List<Rag2AuthorityEvidence> evidence;

  Map<String, Object?> toJson() => {
    'requestedAuthority': requestedAuthority.name,
    'evidence': [
      for (final item in evidence)
        {
          'objectId': item.objectId,
          'authority': item.authority.name,
          'revision': item.revision,
        },
    ],
  };
}

final class Rag2AuthorityDataset {
  const Rag2AuthorityDataset({
    required this.fixture,
    required this.corpusHash,
    required this.claims,
    required this.queries,
    required this.evidenceByCase,
  });

  final RagRetrievalFixture fixture;
  final String corpusHash;
  final List<Rag2ClaimCandidate> claims;
  final Map<String, String> queries;
  final Map<String, List<Rag2AuthorityEvidence>> evidenceByCase;
}

final class Rag2AuthorityDatasetResult {
  const Rag2AuthorityDatasetResult({
    required this.baseline,
    required this.authorityAware,
    required this.selections,
  });

  final Rag2ClaimVerificationResult baseline;
  final Rag2ClaimVerificationResult authorityAware;
  final Map<String, Rag2AuthoritySelection> selections;

  Map<String, Object?> toJson() => {
    'baseline': baseline.toJson(),
    'authorityAware': authorityAware.toJson(),
    'macroF1Delta': authorityAware.macroF1 - baseline.macroF1,
    'selections': {
      for (final entry in selections.entries) entry.key: entry.value.toJson(),
    },
  };
}

final class Rag2AuthorityClaimReport {
  const Rag2AuthorityClaimReport({
    required this.candidateSetId,
    required this.metadataId,
    required this.results,
  });

  final String candidateSetId;
  final String metadataId;
  final List<Rag2AuthorityDatasetResult> results;

  bool get passed => results.every((item) => item.authorityAware.meetsGate);

  Map<String, Object?> toJson() => {
    'schemaName': rag2AuthorityClaimSchema,
    'schemaVersion': rag2AuthorityClaimSchemaVersion,
    'candidateSetId': candidateSetId,
    'metadataId': metadataId,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'verifierPolicy': rag2FrozenClaimVerifierPolicy.toJson(),
    'results': [for (final item in results) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Authority-Aware Claim Verification')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln(
        '- Verifier policy: frozen support `0.90`, contradiction `0.50`',
      )
      ..writeln()
      ..writeln(
        '| Dataset | Baseline macro F1 | Authority macro F1 | Delta | Gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | --- |');
    for (final item in results) {
      buffer.writeln(
        '| ${item.authorityAware.fixtureId} | '
        '${item.baseline.macroF1.toStringAsFixed(3)} | '
        '${item.authorityAware.macroF1.toStringAsFixed(3)} | '
        '${(item.authorityAware.macroF1 - item.baseline.macroF1).toStringAsFixed(3)} | '
        '${item.authorityAware.meetsGate ? 'pass' : 'fail'} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Residual errors')
      ..writeln()
      ..writeln(
        '| Dataset | Candidate | Expected | Predicted | Authority | Objects |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final result in results) {
      for (final item in result.authorityAware.cases.where(
        (item) => !item.correct,
      )) {
        final selection = result.selections[item.candidateId]!;
        buffer.writeln(
          '| ${result.authorityAware.fixtureId} | ${item.candidateId} | '
          '${item.expected.name} | ${item.predicted.name} | '
          '${selection.requestedAuthority.name} | '
          '${selection.evidence.map((entry) => entry.objectId).join(', ')} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'Authority metadata is fixture input for this storage-independent experiment. The lexical verifier thresholds and 36 candidate labels are unchanged.',
      );
    return buffer.toString();
  }
}

final class Rag2AuthorityClaimOptions {
  const Rag2AuthorityClaimOptions({
    required this.claimsPath,
    required this.authorityPath,
    required this.seedFixturePath,
    required this.holdoutFixturePath,
    required this.auditFixturePath,
    required this.outDir,
  });

  final String claimsPath;
  final String authorityPath;
  final String seedFixturePath;
  final String holdoutFixturePath;
  final String auditFixturePath;
  final String outDir;

  static Rag2AuthorityClaimOptions? parse(List<String> args) {
    if (args.length != 12) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final claims = values['--claims'];
    final authority = values['--authority'];
    final seed = values['--seed-fixture'];
    final holdout = values['--holdout-fixture'];
    final audit = values['--audit-fixture'];
    final outDir = values['--out-dir'];
    if ([claims, authority, seed, holdout, audit, outDir].contains(null) ||
        values.length != 6) {
      return null;
    }
    return Rag2AuthorityClaimOptions(
      claimsPath: claims!,
      authorityPath: authority!,
      seedFixturePath: seed!,
      holdoutFixturePath: holdout!,
      auditFixturePath: audit!,
      outDir: outDir!,
    );
  }
}
