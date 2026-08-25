import 'dart:convert';
import 'dart:io';

import 'rag2_authority_claim_eval.dart';
import 'rag2_post_answer_claim_eval.dart';
import 'rag2_semantic_claim_eval.dart';
import 'rag2_structured_claim_eval.dart';

const rag2SemanticHoldoutSchema = 'caverno_rag2_semantic_holdout_eval';
const rag2SemanticHoldoutSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2SemanticHoldoutOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_semantic_holdout_eval.dart '
      '--claims PATH --envelopes PATH --authority PATH '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2SemanticHoldoutEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 semantic holdout evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2SemanticHoldoutReport> runRag2SemanticHoldoutEval(
  Rag2SemanticHoldoutOptions options, {
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
  final dataset = await loadRag2AuthorityDataset(
    options.fixturePath,
    claimSet,
    metadata,
  );
  claimSet.validate({
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
  final result = evaluateRag2SemanticDataset(dataset, envelopes, verifier);
  final report = Rag2SemanticHoldoutReport(
    candidateSetId: claimSet.candidateSetId,
    envelopeSetId: envelopes.envelopeSetId,
    metadataId: metadata.metadataId,
    verifierId: verifier.id,
    result: result,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_semantic_holdout_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_semantic_holdout_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag2SemanticHoldoutReport {
  const Rag2SemanticHoldoutReport({
    required this.candidateSetId,
    required this.envelopeSetId,
    required this.metadataId,
    required this.verifierId,
    required this.result,
  });

  final String candidateSetId;
  final String envelopeSetId;
  final String metadataId;
  final String verifierId;
  final Rag2StructuredDatasetResult result;

  bool get passed => result.result.meetsGate;

  Map<String, Object?> toJson() => {
    'schemaName': rag2SemanticHoldoutSchema,
    'schemaVersion': rag2SemanticHoldoutSchemaVersion,
    'candidateSetId': candidateSetId,
    'envelopeSetId': envelopeSetId,
    'metadataId': metadataId,
    'verifierId': verifierId,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'holdout': result.toJson(),
  };

  String toMarkdown() {
    final metrics = result.result.metrics;
    final buffer = StringBuffer()
      ..writeln('# RAG2 Blinded Semantic Holdout')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Frozen verifier: `$verifierId`')
      ..writeln('- Claims: `${result.result.cases.length}`')
      ..writeln()
      ..writeln(
        '| Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |',
      )
      ..writeln('| ---: | ---: | ---: | ---: | --- |')
      ..writeln(
        '| ${result.result.macroF1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.supported]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.contradicted]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.absent]!.f1.toStringAsFixed(3)} | '
        '${passed ? 'pass' : 'fail'} |',
      )
      ..writeln()
      ..writeln('## Errors')
      ..writeln()
      ..writeln('| Candidate | Expected | Predicted | Reason |')
      ..writeln('| --- | --- | --- | --- |');
    for (final item in result.result.cases.where((item) => !item.correct)) {
      buffer.writeln(
        '| ${item.candidateId} | ${item.expected.name} | '
        '${item.predicted.name} | '
        '${result.decisions[item.candidateId]!.reason} |',
      );
    }
    return buffer.toString();
  }
}

final class Rag2SemanticHoldoutOptions {
  const Rag2SemanticHoldoutOptions({
    required this.claimsPath,
    required this.envelopesPath,
    required this.authorityPath,
    required this.fixturePath,
    required this.outDir,
  });

  final String claimsPath;
  final String envelopesPath;
  final String authorityPath;
  final String fixturePath;
  final String outDir;

  static Rag2SemanticHoldoutOptions? parse(List<String> args) {
    if (args.length != 10) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final claims = values['--claims'];
    final envelopes = values['--envelopes'];
    final authority = values['--authority'];
    final fixture = values['--fixture'];
    final outDir = values['--out-dir'];
    if ([claims, envelopes, authority, fixture, outDir].contains(null) ||
        values.length != 5) {
      return null;
    }
    return Rag2SemanticHoldoutOptions(
      claimsPath: claims!,
      envelopesPath: envelopes!,
      authorityPath: authority!,
      fixturePath: fixture!,
      outDir: outDir!,
    );
  }
}
