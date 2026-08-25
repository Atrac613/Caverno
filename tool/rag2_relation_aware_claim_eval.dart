import 'dart:convert';
import 'dart:io';

import 'rag2_post_answer_claim_eval.dart';
import 'rag2_semantic_claim_eval.dart';
import 'rag2_semantic_holdout_eval.dart';
import 'rag2_structured_claim_eval.dart';

const rag2RelationComparisonSchema =
    'caverno_rag2_relation_aware_claim_comparison';
const rag2RelationComparisonSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2RelationComparisonOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_relation_aware_claim_eval.dart '
      '--claims PATH --envelopes PATH --authority PATH '
      '--seed-fixture PATH --holdout-fixture PATH --audit-fixture PATH '
      '--semantic-claims PATH --semantic-envelopes PATH '
      '--semantic-authority PATH --semantic-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2RelationComparison(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 relation-aware comparison failed: $error');
    exitCode = 65;
  }
}

Future<Rag2RelationComparisonReport> runRag2RelationComparison(
  Rag2RelationComparisonOptions options,
) async {
  const v1 = Rag2DeterministicSemanticSupportVerifier();
  const v2 = Rag2RelationAwareSemanticSupportVerifier();
  final v1Original = await runRag2SemanticClaimEval(
    options.originalOptions('${options.outDir}/v1/original'),
    verifier: v1,
  );
  final v2Original = await runRag2SemanticClaimEval(
    options.originalOptions('${options.outDir}/v2/original'),
    verifier: v2,
  );
  final v1Holdout = await runRag2SemanticHoldoutEval(
    options.semanticOptions('${options.outDir}/v1/holdout'),
    verifier: v1,
  );
  final v2Holdout = await runRag2SemanticHoldoutEval(
    options.semanticOptions('${options.outDir}/v2/holdout'),
    verifier: v2,
  );
  final report = Rag2RelationComparisonReport(
    v1Original: v1Original,
    v2Original: v2Original,
    v1Holdout: v1Holdout,
    v2Holdout: v2Holdout,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_relation_aware_claim_comparison.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_relation_aware_claim_comparison.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag2RelationAwareSemanticSupportVerifier
    implements Rag2SemanticSupportVerifier {
  const Rag2RelationAwareSemanticSupportVerifier({this.available = true});

  @override
  final bool available;

  @override
  String get id => 'relation-aware-atomic-facts-v2';

  @override
  Rag2ClaimVerifierDecision verify({
    required String claim,
    required String evidence,
  }) {
    if (!available) {
      throw StateError('Relation-aware semantic verifier is unavailable.');
    }
    return _verifyBooleanRelation(claim, evidence) ??
        _verifyUrlPortRelation(claim, evidence) ??
        _verifyCodeNumericAssignment(claim, evidence) ??
        const Rag2DeterministicSemanticSupportVerifier().verify(
          claim: claim,
          evidence: evidence,
        );
  }
}

Rag2ClaimVerifierDecision? _verifyBooleanRelation(
  String claim,
  String evidence,
) {
  final claimState = _booleanState(claim);
  if (claimState == null) return null;
  final subject = _relationTerms(
    claim,
  ).difference(const {'current', 'default', 'enabled', 'disabled'});
  final sentences = _sentences(
    evidence,
  ).where((sentence) => _booleanState(sentence) != null).toList();
  if (sentences.isEmpty) return null;
  sentences.sort(
    (a, b) => _overlap(
      subject,
      _relationTerms(b),
    ).compareTo(_overlap(subject, _relationTerms(a))),
  );
  final sentence = sentences.first;
  final coverage = _coverage(subject, _relationTerms(sentence));
  if (coverage < 0.5) return null;
  if (_containsModality(sentence)) {
    return _relationDecision(Rag2ClaimVerdict.absent, coverage);
  }
  final evidenceState = _booleanState(sentence)!;
  return _relationDecision(
    claimState == evidenceState
        ? Rag2ClaimVerdict.supported
        : Rag2ClaimVerdict.contradicted,
    coverage,
  );
}

Rag2ClaimVerifierDecision? _verifyUrlPortRelation(
  String claim,
  String evidence,
) {
  final claimNumbers = _numbers(claim);
  if (!RegExp(r'\bport\b', caseSensitive: false).hasMatch(claim) ||
      claimNumbers.length != 1) {
    return null;
  }
  final subject = _relationTerms(
    claim,
  ).difference({...claimNumbers, 'current', 'default', 'port'});
  final candidates = <({String sentence, Uri uri, double coverage})>[];
  for (final sentence in _sentences(evidence)) {
    final coverage = _coverage(subject, _relationTerms(sentence));
    for (final match in RegExp(
      r'https?://[^\s`]+',
      caseSensitive: false,
    ).allMatches(sentence)) {
      final raw = match.group(0)!.replaceFirst(RegExp(r'[.,;:)]+$'), '');
      final uri = Uri.tryParse(raw);
      if (uri != null) {
        candidates.add((sentence: sentence, uri: uri, coverage: coverage));
      }
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.coverage.compareTo(a.coverage));
  final candidate = candidates.first;
  if (candidate.coverage < 0.5) return null;
  final hasExplicitPort = RegExp(r':\d+$').hasMatch(candidate.uri.authority);
  if (!hasExplicitPort) {
    return _relationDecision(Rag2ClaimVerdict.absent, candidate.coverage);
  }
  final expected = claimNumbers.single;
  return _relationDecision(
    candidate.uri.port.toString() == expected
        ? Rag2ClaimVerdict.supported
        : Rag2ClaimVerdict.contradicted,
    candidate.coverage,
    numericMismatch: candidate.uri.port.toString() != expected,
  );
}

Rag2ClaimVerifierDecision? _verifyCodeNumericAssignment(
  String claim,
  String evidence,
) {
  final claimNumbers = _numbers(claim);
  if (claimNumbers.isEmpty) return null;
  final subject = _relationTerms(claim).difference(claimNumbers);
  for (final match in RegExp(
    r'\b(?:const|final|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+);',
  ).allMatches(evidence)) {
    final assignmentTerms = _relationTerms(match.group(1)!);
    final coverage = _coverage(subject, assignmentTerms);
    if (coverage < 0.75) continue;
    final assignmentNumbers = _numbers(match.group(2)!);
    if (assignmentNumbers.isEmpty) continue;
    final supported = assignmentNumbers.containsAll(claimNumbers);
    return _relationDecision(
      supported ? Rag2ClaimVerdict.supported : Rag2ClaimVerdict.contradicted,
      coverage,
      numericMismatch: !supported,
    );
  }
  return null;
}

Rag2ClaimVerifierDecision _relationDecision(
  Rag2ClaimVerdict verdict,
  double coverage, {
  bool numericMismatch = false,
}) => Rag2ClaimVerifierDecision(
  verdict: verdict,
  coverage: coverage,
  skeletonCoverage: coverage,
  numericMismatch: numericMismatch,
);

Set<String> _relationTerms(String source) {
  final expanded = source.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return RegExp(r'[a-z0-9]+(?:\.[a-z0-9]+)?', caseSensitive: false)
      .allMatches(expanded.toLowerCase())
      .map((match) {
        final term = match.group(0)!;
        return const {
              'initial': 'default',
              'defaults': 'default',
              'iteration': 'limit',
              'iterations': 'limit',
              'currently': 'current',
            }[term] ??
            term;
      })
      .where(
        (term) => !const {
          'a',
          'an',
          'are',
          'at',
          'be',
          'feature',
          'is',
          'it',
          'the',
          'to',
          'was',
          'were',
        }.contains(term),
      )
      .toSet();
}

bool? _booleanState(String source) {
  final tokens = _plainTokens(source);
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token != 'enabled' && token != 'disabled') continue;
    var state = token == 'enabled';
    var cursor = index - 1;
    var negations = 0;
    while (cursor >= 0 && tokens[cursor] == 'not') {
      negations++;
      cursor--;
    }
    if (negations.isOdd) state = !state;
    return state;
  }
  return null;
}

List<String> _plainTokens(String source) => RegExp(
  r'[a-z]+',
  caseSensitive: false,
).allMatches(source.toLowerCase()).map((match) => match.group(0)!).toList();

bool _containsModality(String sentence) => _plainTokens(sentence).any(
  const {'can', 'could', 'may', 'might', 'possibly', 'potentially'}.contains,
);

List<String> _sentences(String source) => source
    .replaceAll(RegExp(r'\s*\n\s*'), ' ')
    .split(RegExp(r'(?<=[.!?;])\s+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

Set<String> _numbers(String source) => RegExp(
  r'(?<![a-z0-9])\d+(?:\.\d+)?(?![a-z0-9])',
  caseSensitive: false,
).allMatches(source).map((match) => match.group(0)!).toSet();

int _overlap(Set<String> a, Set<String> b) => a.intersection(b).length;

double _coverage(Set<String> claim, Set<String> evidence) =>
    claim.isEmpty ? 0 : _overlap(claim, evidence) / claim.length;

final class Rag2RelationComparisonReport {
  const Rag2RelationComparisonReport({
    required this.v1Original,
    required this.v2Original,
    required this.v1Holdout,
    required this.v2Holdout,
  });

  final Rag2SemanticClaimReport v1Original;
  final Rag2SemanticClaimReport v2Original;
  final Rag2SemanticHoldoutReport v1Holdout;
  final Rag2SemanticHoldoutReport v2Holdout;

  bool get passed => v2Original.passed && v2Holdout.passed;

  Map<String, Object?> toJson() => {
    'schemaName': rag2RelationComparisonSchema,
    'schemaVersion': rag2RelationComparisonSchemaVersion,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'v1': {
      'original': v1Original.toJson(),
      'semanticHoldout': v1Holdout.toJson(),
    },
    'v2': {
      'original': v2Original.toJson(),
      'semanticHoldout': v2Holdout.toJson(),
    },
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Relation-Aware Claim Comparison')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln('| Verifier | Dataset | Macro F1 | Gate |')
      ..writeln('| --- | --- | ---: | --- |');
    _writeOriginalRows(buffer, v1Original);
    _writeHoldoutRow(buffer, v1Holdout);
    _writeOriginalRows(buffer, v2Original);
    _writeHoldoutRow(buffer, v2Holdout);
    return buffer.toString();
  }

  void _writeOriginalRows(StringBuffer buffer, Rag2SemanticClaimReport report) {
    for (final dataset in report.results) {
      buffer.writeln(
        '| ${report.verifierId} | ${dataset.result.fixtureId} | '
        '${dataset.result.macroF1.toStringAsFixed(3)} | '
        '${dataset.result.meetsGate ? 'pass' : 'fail'} |',
      );
    }
  }

  void _writeHoldoutRow(StringBuffer buffer, Rag2SemanticHoldoutReport report) {
    buffer.writeln(
      '| ${report.verifierId} | ${report.result.result.fixtureId} | '
      '${report.result.result.macroF1.toStringAsFixed(3)} | '
      '${report.passed ? 'pass' : 'fail'} |',
    );
  }
}

final class Rag2RelationComparisonOptions {
  const Rag2RelationComparisonOptions({
    required this.claimsPath,
    required this.envelopesPath,
    required this.authorityPath,
    required this.seedFixturePath,
    required this.holdoutFixturePath,
    required this.auditFixturePath,
    required this.semanticClaimsPath,
    required this.semanticEnvelopesPath,
    required this.semanticAuthorityPath,
    required this.semanticFixturePath,
    required this.outDir,
  });

  final String claimsPath;
  final String envelopesPath;
  final String authorityPath;
  final String seedFixturePath;
  final String holdoutFixturePath;
  final String auditFixturePath;
  final String semanticClaimsPath;
  final String semanticEnvelopesPath;
  final String semanticAuthorityPath;
  final String semanticFixturePath;
  final String outDir;

  Rag2StructuredClaimOptions originalOptions(String outputPath) =>
      Rag2StructuredClaimOptions(
        claimsPath: claimsPath,
        envelopesPath: envelopesPath,
        authorityPath: authorityPath,
        seedFixturePath: seedFixturePath,
        holdoutFixturePath: holdoutFixturePath,
        auditFixturePath: auditFixturePath,
        outDir: outputPath,
      );

  Rag2SemanticHoldoutOptions semanticOptions(String outputPath) =>
      Rag2SemanticHoldoutOptions(
        claimsPath: semanticClaimsPath,
        envelopesPath: semanticEnvelopesPath,
        authorityPath: semanticAuthorityPath,
        fixturePath: semanticFixturePath,
        outDir: outputPath,
      );

  static Rag2RelationComparisonOptions? parse(List<String> args) {
    if (args.length != 22) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final required = [
      '--claims',
      '--envelopes',
      '--authority',
      '--seed-fixture',
      '--holdout-fixture',
      '--audit-fixture',
      '--semantic-claims',
      '--semantic-envelopes',
      '--semantic-authority',
      '--semantic-fixture',
      '--out-dir',
    ];
    if (required.any((key) => values[key] == null) || values.length != 11) {
      return null;
    }
    return Rag2RelationComparisonOptions(
      claimsPath: values['--claims']!,
      envelopesPath: values['--envelopes']!,
      authorityPath: values['--authority']!,
      seedFixturePath: values['--seed-fixture']!,
      holdoutFixturePath: values['--holdout-fixture']!,
      auditFixturePath: values['--audit-fixture']!,
      semanticClaimsPath: values['--semantic-claims']!,
      semanticEnvelopesPath: values['--semantic-envelopes']!,
      semanticAuthorityPath: values['--semantic-authority']!,
      semanticFixturePath: values['--semantic-fixture']!,
      outDir: values['--out-dir']!,
    );
  }
}
