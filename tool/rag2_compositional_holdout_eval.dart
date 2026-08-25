import 'dart:convert';
import 'dart:io';

import 'rag2_post_answer_claim_eval.dart';
import 'rag2_relation_aware_claim_eval.dart';
import 'rag2_semantic_claim_eval.dart';
import 'rag2_semantic_holdout_eval.dart';

const rag2CompositionalHoldoutSchema =
    'caverno_rag2_compositional_holdout_comparison';
const rag2CompositionalHoldoutSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2SemanticHoldoutOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_compositional_holdout_eval.dart '
      '--claims PATH --envelopes PATH --authority PATH '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2CompositionalHoldoutComparison(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 compositional holdout evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2CompositionalHoldoutReport> runRag2CompositionalHoldoutComparison(
  Rag2SemanticHoldoutOptions options,
) async {
  final v1 = await runRag2SemanticHoldoutEval(
    _outputOptions(options, '${options.outDir}/v1'),
    verifier: const Rag2DeterministicSemanticSupportVerifier(),
  );
  final v2 = await runRag2SemanticHoldoutEval(
    _outputOptions(options, '${options.outDir}/v2'),
    verifier: const Rag2RelationAwareSemanticSupportVerifier(),
  );
  final report = Rag2CompositionalHoldoutReport(v1: v1, v2: v2);
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_compositional_holdout_comparison.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_compositional_holdout_comparison.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Rag2SemanticHoldoutOptions _outputOptions(
  Rag2SemanticHoldoutOptions source,
  String outDir,
) => Rag2SemanticHoldoutOptions(
  claimsPath: source.claimsPath,
  envelopesPath: source.envelopesPath,
  authorityPath: source.authorityPath,
  fixturePath: source.fixturePath,
  outDir: outDir,
);

final class Rag2CompositionalHoldoutReport {
  const Rag2CompositionalHoldoutReport({required this.v1, required this.v2});

  final Rag2SemanticHoldoutReport v1;
  final Rag2SemanticHoldoutReport v2;

  bool get passed => v2.passed;

  Map<String, Object?> toJson() => {
    'schemaName': rag2CompositionalHoldoutSchema,
    'schemaVersion': rag2CompositionalHoldoutSchemaVersion,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'v1': v1.toJson(),
    'v2': v2.toJson(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Compositional Semantic Holdout')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Verifier | Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | --- |');
    _writeMetricRow(buffer, v1);
    _writeMetricRow(buffer, v2);
    _writeErrors(buffer, v1);
    _writeErrors(buffer, v2);
    return buffer.toString();
  }

  void _writeMetricRow(StringBuffer buffer, Rag2SemanticHoldoutReport report) {
    final result = report.result.result;
    final metrics = result.metrics;
    buffer.writeln(
      '| ${report.verifierId} | ${result.macroF1.toStringAsFixed(3)} | '
      '${metrics[Rag2ClaimVerdict.supported]!.f1.toStringAsFixed(3)} | '
      '${metrics[Rag2ClaimVerdict.contradicted]!.f1.toStringAsFixed(3)} | '
      '${metrics[Rag2ClaimVerdict.absent]!.f1.toStringAsFixed(3)} | '
      '${report.passed ? 'pass' : 'fail'} |',
    );
  }

  void _writeErrors(StringBuffer buffer, Rag2SemanticHoldoutReport report) {
    buffer
      ..writeln()
      ..writeln('## ${report.verifierId} errors')
      ..writeln()
      ..writeln('| Candidate | Expected | Predicted |')
      ..writeln('| --- | --- | --- |');
    for (final item in report.result.result.cases.where(
      (item) => !item.correct,
    )) {
      buffer.writeln(
        '| ${item.candidateId} | ${item.expected.name} | '
        '${item.predicted.name} |',
      );
    }
  }
}
