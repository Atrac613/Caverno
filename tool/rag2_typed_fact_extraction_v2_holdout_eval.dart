import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'rag2_typed_fact_extraction_eval.dart';
import 'rag2_typed_fact_extraction_v2_eval.dart';
import 'rag2_typed_fact_oracle_eval.dart';

const rag2TypedFactExtractionV2HoldoutSchema =
    'caverno_rag2_typed_fact_extraction_v2_holdout_eval';
const rag2TypedFactExtractionV2HoldoutSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2TypedFactExtractionV2HoldoutOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_typed_fact_extraction_v2_holdout_eval.dart '
      '--fixture PATH --oracle-facts PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2TypedFactExtractionV2HoldoutEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 typed-fact extraction v2 holdout failed: $error');
    exitCode = 65;
  }
}

Future<Rag2TypedFactExtractionV2HoldoutReport>
runRag2TypedFactExtractionV2HoldoutEval(
  Rag2TypedFactExtractionV2HoldoutOptions options,
) async {
  final fixture = await Rag2TypedFactExtractionPrecisionFixture.load(
    File(options.fixturePath),
  );
  final corpusHash = await fixture.computeCorpusHash();
  if (fixture.corpusHash != corpusHash) {
    throw StateError('Extraction v2 precision holdout corpus hash mismatch.');
  }
  final oracle = await Rag2TypedEvidenceFactSet.load(
    File(options.oracleFactsPath),
  );
  await fixture.validateOracle(oracle);
  final v1Facts = await extractRag2TypedFacts(
    corpusRoot: fixture.corpusDirectory,
    corpusHash: corpusHash,
  );
  final v2Facts = await extractRag2TypedFactsV2(
    corpusRoot: fixture.corpusDirectory,
    corpusHash: corpusHash,
  );
  final report = Rag2TypedFactExtractionV2HoldoutReport(
    fixtureId: fixture.fixtureId,
    corpusHash: corpusHash,
    precisionFamilies: fixture.precisionFamilies,
    v1: Rag2FactExtractionMetrics.compare(
      oracle: oracle.facts,
      extracted: v1Facts,
    ),
    v2: Rag2FactExtractionMetrics.compare(
      oracle: oracle.facts,
      extracted: v2Facts,
    ),
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_v2_holdout_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_v2_holdout_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag2TypedFactExtractionPrecisionFixture {
  const Rag2TypedFactExtractionPrecisionFixture({
    required this.sourceFile,
    required this.fixtureId,
    required this.frozenExtractors,
    required this.corpusRoot,
    required this.corpusHash,
    required this.precisionFamilies,
    required this.observationalFamilies,
  });

  final File sourceFile;
  final String fixtureId;
  final Set<String> frozenExtractors;
  final String corpusRoot;
  final String corpusHash;
  final Set<Rag2ExtractionSourceFamily> precisionFamilies;
  final Set<Rag2ExtractionSourceFamily> observationalFamilies;

  Directory get corpusDirectory =>
      Directory('${sourceFile.parent.path}/$corpusRoot');

  static Future<Rag2TypedFactExtractionPrecisionFixture> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] !=
            'caverno_rag2_typed_fact_extraction_precision_fixture' ||
        json['schemaVersion'] != 1) {
      throw StateError('Unsupported extraction precision fixture schema.');
    }
    final fixture = Rag2TypedFactExtractionPrecisionFixture(
      sourceFile: file,
      fixtureId: json['fixtureId']! as String,
      frozenExtractors: (json['frozenExtractors'] as List)
          .cast<String>()
          .toSet(),
      corpusRoot: json['corpusRoot']! as String,
      corpusHash: json['corpusHash']! as String,
      precisionFamilies: (json['precisionFamilies'] as List)
          .cast<String>()
          .map(Rag2ExtractionSourceFamily.values.byName)
          .toSet(),
      observationalFamilies: (json['observationalFamilies'] as List)
          .cast<String>()
          .map(Rag2ExtractionSourceFamily.values.byName)
          .toSet(),
    );
    if (!fixture.frozenExtractors.containsAll({
          'typed-fact-extraction-v1-frozen',
          rag2TypedFactExtractionV2Policy,
        }) ||
        fixture.precisionFamilies.isEmpty ||
        fixture.precisionFamilies
            .intersection(fixture.observationalFamilies)
            .isNotEmpty ||
        !fixture.precisionFamilies
            .union(fixture.observationalFamilies)
            .containsAll(Rag2ExtractionSourceFamily.values) ||
        !fixture.corpusDirectory.existsSync()) {
      throw StateError('Extraction precision fixture identity is invalid.');
    }
    return fixture;
  }

  Future<String> computeCorpusHash() async {
    final files =
        corpusDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final bytes = <int>[];
    for (final file in files) {
      bytes
        ..addAll(
          utf8.encode(file.path.substring(corpusDirectory.path.length + 1)),
        )
        ..add(0)
        ..addAll(await file.readAsBytes())
        ..add(0);
    }
    return sha256.convert(bytes).toString();
  }

  Future<void> validateOracle(Rag2TypedEvidenceFactSet oracle) async {
    if (oracle.datasetId != fixtureId ||
        oracle.corpusHash != corpusHash ||
        oracle.facts.map((fact) => fact.factId).toSet().length !=
            oracle.facts.length) {
      throw StateError('Extraction precision oracle identity is invalid.');
    }
    final families = <Rag2ExtractionSourceFamily>{};
    for (final fact in oracle.facts) {
      if (fact.provenanceKind != 'oracle_annotation' ||
          fact.provenanceCorpusHash != corpusHash ||
          fact.source.startLine < 1 ||
          fact.source.endLine < fact.source.startLine) {
        throw StateError('Extraction precision oracle provenance is invalid.');
      }
      final source = File('${corpusDirectory.path}/${fact.source.objectId}');
      if (!source.existsSync() ||
          fact.source.endLine >
              await source.readAsLines().then((lines) => lines.length)) {
        throw StateError('Extraction precision oracle span is invalid.');
      }
      families.add(rag2ExtractionSourceFamily(fact));
    }
    if (!families.containsAll(precisionFamilies.union(observationalFamilies))) {
      throw StateError('Extraction precision oracle misses a source family.');
    }
  }
}

final class Rag2TypedFactExtractionV2HoldoutReport {
  const Rag2TypedFactExtractionV2HoldoutReport({
    required this.fixtureId,
    required this.corpusHash,
    required this.precisionFamilies,
    required this.v1,
    required this.v2,
  });

  final String fixtureId;
  final String corpusHash;
  final Set<Rag2ExtractionSourceFamily> precisionFamilies;
  final Rag2FactExtractionMetrics v1;
  final Rag2FactExtractionMetrics v2;

  bool get precisionGatePassed => precisionFamilies.every((family) {
    final baseline = v1.byFamily[family]!;
    final candidate = v2.byFamily[family]!;
    return candidate.extractedCount > 0 &&
        candidate.precision >= 0.95 &&
        candidate.truePositiveCount >= baseline.truePositiveCount;
  });

  Map<String, Object?> toJson() => {
    'schemaName': rag2TypedFactExtractionV2HoldoutSchema,
    'schemaVersion': rag2TypedFactExtractionV2HoldoutSchemaVersion,
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'extractorVersion': rag2TypedFactExtractionV2Policy,
    'holdoutIndependent': true,
    'precisionBaselineDecision': precisionGatePassed ? 'go' : 'no_go',
    'extractionDecision': 'no_go',
    'productionDecision': 'no_go',
    'precisionFamilies': precisionFamilies.map((family) => family.name).toList()
      ..sort(),
    'v1': v1.toJson(),
    'v2': v2.toJson(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Typed Fact Extraction V2 Precision Holdout')
      ..writeln()
      ..writeln('- Holdout independent: `true`')
      ..writeln(
        '- Precision baseline decision: `${precisionGatePassed ? 'go' : 'no_go'}`',
      )
      ..writeln('- Extraction decision: `no_go`')
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Family | V1 precision | V1 recall | V2 precision | V2 recall | Precision gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | --- |');
    for (final family in Rag2ExtractionSourceFamily.values) {
      final v1Score = v1.byFamily[family]!;
      final v2Score = v2.byFamily[family]!;
      final scoped = precisionFamilies.contains(family);
      final passed =
          scoped &&
          v2Score.extractedCount > 0 &&
          v2Score.precision >= 0.95 &&
          v2Score.truePositiveCount >= v1Score.truePositiveCount;
      buffer.writeln(
        '| `${family.name}` | ${v1Score.precision.toStringAsFixed(3)} | '
        '${v1Score.recall.toStringAsFixed(3)} | '
        '${v2Score.precision.toStringAsFixed(3)} | '
        '${v2Score.recall.toStringAsFixed(3)} | '
        '${scoped ? (passed ? 'pass' : 'fail') : 'observational'} |',
      );
    }
    return buffer.toString();
  }
}

final class Rag2TypedFactExtractionV2HoldoutOptions {
  const Rag2TypedFactExtractionV2HoldoutOptions({
    required this.fixturePath,
    required this.oracleFactsPath,
    required this.outDir,
  });

  final String fixturePath;
  final String oracleFactsPath;
  final String outDir;

  static Rag2TypedFactExtractionV2HoldoutOptions? parse(List<String> args) {
    if (args.length != 6) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    if (values.length != 3 ||
        values['--fixture'] == null ||
        values['--oracle-facts'] == null ||
        values['--out-dir'] == null) {
      return null;
    }
    return Rag2TypedFactExtractionV2HoldoutOptions(
      fixturePath: values['--fixture']!,
      oracleFactsPath: values['--oracle-facts']!,
      outDir: values['--out-dir']!,
    );
  }
}
