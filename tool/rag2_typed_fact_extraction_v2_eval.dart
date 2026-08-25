import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'rag2_typed_fact_extraction_eval.dart';
import 'rag2_typed_fact_extraction_holdout_eval.dart';
import 'rag2_typed_fact_oracle_eval.dart';
import 'rag_retrieval_eval.dart';

const rag2TypedFactExtractionV2Schema =
    'caverno_rag2_typed_fact_extraction_v2_eval';
const rag2TypedFactExtractionV2SchemaVersion = 1;
const rag2TypedFactExtractionV2Policy =
    'typed-fact-extraction-v2-precision-only';

Future<void> main(List<String> args) async {
  final options = Rag2TypedFactExtractionV2Options.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_typed_fact_extraction_v2_eval.dart '
      '--development-fixture PATH --development-oracle-facts PATH '
      '--holdout-fixture PATH --holdout-oracle-facts PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2TypedFactExtractionV2Eval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 typed-fact extraction v2 evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2TypedFactExtractionV2Report> runRag2TypedFactExtractionV2Eval(
  Rag2TypedFactExtractionV2Options options,
) async {
  final developmentFixture = await RagRetrievalFixture.load(
    File(options.developmentFixturePath),
  );
  developmentFixture.validate();
  final developmentHash = await developmentFixture.computeCorpusHash();
  if (developmentFixture.corpusHash != developmentHash) {
    throw StateError('Extraction v2 development corpus hash mismatch.');
  }
  final developmentOracle = await Rag2TypedEvidenceFactSet.load(
    File(options.developmentOracleFactsPath),
  );
  await developmentOracle.validate(developmentFixture, developmentHash);

  final holdoutFixture = await Rag2TypedFactExtractionFixture.load(
    File(options.holdoutFixturePath),
  );
  final holdoutHash = await holdoutFixture.computeCorpusHash();
  if (holdoutFixture.corpusHash != holdoutHash) {
    throw StateError('Extraction v2 holdout corpus hash mismatch.');
  }
  final holdoutOracle = await Rag2TypedEvidenceFactSet.load(
    File(options.holdoutOracleFactsPath),
  );
  await holdoutFixture.validateOracle(holdoutOracle);

  final development = await _evaluateDataset(
    datasetId: developmentFixture.fixtureId,
    corpusRoot: Directory(
      '${developmentFixture.sourceFile.parent.path}/'
      '${developmentFixture.corpusRoot}',
    ),
    corpusHash: developmentHash,
    oracle: developmentOracle.facts,
    independent: false,
  );
  final holdout = await _evaluateDataset(
    datasetId: holdoutFixture.fixtureId,
    corpusRoot: holdoutFixture.corpusDirectory,
    corpusHash: holdoutHash,
    oracle: holdoutOracle.facts,
    independent: false,
  );
  final report = Rag2TypedFactExtractionV2Report(
    development: development,
    holdout: holdout,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_v2_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_v2_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2TypedFactExtractionV2DatasetReport> _evaluateDataset({
  required String datasetId,
  required Directory corpusRoot,
  required String corpusHash,
  required List<Rag2TypedEvidenceFact> oracle,
  required bool independent,
}) async {
  final v1Facts = await extractRag2TypedFacts(
    corpusRoot: corpusRoot,
    corpusHash: corpusHash,
  );
  final v2Facts = await extractRag2TypedFactsV2(
    corpusRoot: corpusRoot,
    corpusHash: corpusHash,
  );
  return Rag2TypedFactExtractionV2DatasetReport(
    datasetId: datasetId,
    corpusHash: corpusHash,
    independent: independent,
    v1: Rag2FactExtractionMetrics.compare(oracle: oracle, extracted: v1Facts),
    v2: Rag2FactExtractionMetrics.compare(oracle: oracle, extracted: v2Facts),
    v2Facts: v2Facts,
  );
}

Future<List<Rag2TypedEvidenceFact>> extractRag2TypedFactsV2({
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
        extractDartAssignmentFactsV2(
          content: content,
          objectId: objectId,
          corpusHash: corpusHash,
        ),
      );
    } else if (objectId.endsWith('.md')) {
      facts.addAll(
        extractMarkdownUriFactsV2(
          content: content,
          objectId: objectId,
          corpusHash: corpusHash,
        ),
      );
    }
  }
  return facts;
}

List<Rag2TypedEvidenceFact> extractDartAssignmentFactsV2({
  required String content,
  required String objectId,
  required String corpusHash,
}) {
  final parsed = parseString(content: content, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) return const [];
  final facts = <Rag2TypedEvidenceFact>[];
  for (final declaration in parsed.unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration ||
        !declaration.variables.isConst) {
      continue;
    }
    for (final variable in declaration.variables.variables) {
      final value = _literalValue(variable.initializer);
      final tokens = _identifierTokensV2(variable.name.lexeme);
      if (value == null || tokens.length < 2) continue;
      final relationName = tokens.removeLast();
      final subject = tokens.join('_');
      final line = parsed.lineInfo.getLocation(variable.offset).lineNumber;
      facts.add(
        Rag2TypedEvidenceFact(
          factId: 'extracted-dart-$subject-$line',
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
            startLine: line,
            endLine: line,
          ),
          provenanceKind: 'deterministic_extractor_v2',
          provenanceCorpusHash: corpusHash,
        ),
      );
    }
  }
  return facts;
}

Rag2TypedValue? _literalValue(Expression? expression) => switch (expression) {
  SimpleStringLiteral(:final value) => Rag2TypedValue(
    type: Rag2FactValueType.string,
    value: value,
  ),
  IntegerLiteral(:final value?) => Rag2TypedValue(
    type: Rag2FactValueType.integer,
    value: value,
  ),
  BooleanLiteral(:final value) => Rag2TypedValue(
    type: Rag2FactValueType.boolean,
    value: value,
  ),
  _ => null,
};

List<String> _identifierTokensV2(String identifier) => RegExp(
  r'[A-Z]?[a-z]+|[A-Z]+(?=[A-Z]|$)|[0-9]+',
).allMatches(identifier).map((match) => match.group(0)!.toLowerCase()).toList();

List<Rag2TypedEvidenceFact> extractMarkdownUriFactsV2({
  required String content,
  required String objectId,
  required String corpusHash,
}) {
  final tokenPattern = RegExp(r'''https?://[^\s`)]+''');
  final codeUnits = content.codeUnits.toList();
  for (final match in tokenPattern.allMatches(content)) {
    final token = match.group(0)!;
    final core = token.replaceFirst(RegExp(r'[.,;!?]+$'), '');
    if (isStrictHttpUriV2(core)) continue;
    for (var index = match.start; index < match.end; index++) {
      if (codeUnits[index] != 10 && codeUnits[index] != 13) {
        codeUnits[index] = 32;
      }
    }
  }
  final facts = extractMarkdownUriFacts(
    content: String.fromCharCodes(codeUnits),
    objectId: objectId,
    corpusHash: corpusHash,
  );
  return [
    for (final fact in facts)
      Rag2TypedEvidenceFact(
        factId: fact.factId,
        atom: fact.atom,
        source: fact.source,
        provenanceKind: 'deterministic_extractor_v2',
        provenanceCorpusHash: corpusHash,
      ),
  ];
}

bool isStrictHttpUriV2(String token) {
  final uri = Uri.tryParse(token);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  final authorityStart = token.indexOf('://') + 3;
  final authorityEnd = token.indexOf(RegExp(r'[/#?]'), authorityStart);
  final authority = token.substring(
    authorityStart,
    authorityEnd < 0 ? token.length : authorityEnd,
  );
  if (authority.contains('[') || authority.contains(']')) return false;
  final colon = authority.lastIndexOf(':');
  if (colon < 0) return true;
  if (authority.indexOf(':') != colon) return false;
  final portText = authority.substring(colon + 1);
  final port = int.tryParse(portText);
  return port != null && port >= 1 && port <= 65535;
}

final class Rag2TypedFactExtractionV2DatasetReport {
  const Rag2TypedFactExtractionV2DatasetReport({
    required this.datasetId,
    required this.corpusHash,
    required this.independent,
    required this.v1,
    required this.v2,
    required this.v2Facts,
  });

  final String datasetId;
  final String corpusHash;
  final bool independent;
  final Rag2FactExtractionMetrics v1;
  final Rag2FactExtractionMetrics v2;
  final List<Rag2TypedEvidenceFact> v2Facts;

  Map<String, Object?> toJson() => {
    'datasetId': datasetId,
    'corpusHash': corpusHash,
    'independentForV2': independent,
    'v1': v1.toJson(),
    'v2': v2.toJson(),
    'v2ExtractedFactCount': v2Facts.length,
  };
}

final class Rag2TypedFactExtractionV2Report {
  const Rag2TypedFactExtractionV2Report({
    required this.development,
    required this.holdout,
  });

  final Rag2TypedFactExtractionV2DatasetReport development;
  final Rag2TypedFactExtractionV2DatasetReport holdout;

  Map<String, Object?> toJson() => {
    'schemaName': rag2TypedFactExtractionV2Schema,
    'schemaVersion': rag2TypedFactExtractionV2SchemaVersion,
    'extractorVersion': rag2TypedFactExtractionV2Policy,
    'result': 'no_go',
    'productionDecision': 'no_go',
    'independentPromotionEvidence': false,
    'development': development.toJson(),
    'holdout': holdout.toJson(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Typed Fact Extraction V2')
      ..writeln()
      ..writeln('- Extractor: `$rag2TypedFactExtractionV2Policy`')
      ..writeln('- Independent promotion evidence: `false`')
      ..writeln('- Production decision: `no_go`')
      ..writeln();
    _writeDataset(buffer, 'Development fixture', development);
    buffer.writeln();
    _writeDataset(buffer, 'Frozen v1 holdout', holdout);
    return buffer.toString();
  }

  void _writeDataset(
    StringBuffer buffer,
    String label,
    Rag2TypedFactExtractionV2DatasetReport dataset,
  ) {
    buffer
      ..writeln('## $label')
      ..writeln()
      ..writeln('| Extractor | Precision | Recall | F1 | Gate |')
      ..writeln('| --- | ---: | ---: | ---: | --- |');
    for (final entry in {'v1': dataset.v1, 'v2': dataset.v2}.entries) {
      final score = entry.value.overall;
      buffer.writeln(
        '| `${entry.key}` | ${score.precision.toStringAsFixed(3)} | '
        '${score.recall.toStringAsFixed(3)} | ${score.f1.toStringAsFixed(3)} | '
        '${entry.value.meetsGate ? 'pass' : 'fail'} |',
      );
    }
  }
}

final class Rag2TypedFactExtractionV2Options {
  const Rag2TypedFactExtractionV2Options({
    required this.developmentFixturePath,
    required this.developmentOracleFactsPath,
    required this.holdoutFixturePath,
    required this.holdoutOracleFactsPath,
    required this.outDir,
  });

  final String developmentFixturePath;
  final String developmentOracleFactsPath;
  final String holdoutFixturePath;
  final String holdoutOracleFactsPath;
  final String outDir;

  static Rag2TypedFactExtractionV2Options? parse(List<String> args) {
    if (args.length != 10) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final required = [
      '--development-fixture',
      '--development-oracle-facts',
      '--holdout-fixture',
      '--holdout-oracle-facts',
      '--out-dir',
    ];
    if (values.length != required.length ||
        required.any((key) => values[key] == null)) {
      return null;
    }
    return Rag2TypedFactExtractionV2Options(
      developmentFixturePath: values['--development-fixture']!,
      developmentOracleFactsPath: values['--development-oracle-facts']!,
      holdoutFixturePath: values['--holdout-fixture']!,
      holdoutOracleFactsPath: values['--holdout-oracle-facts']!,
      outDir: values['--out-dir']!,
    );
  }
}
