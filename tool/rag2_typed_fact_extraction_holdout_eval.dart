import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'rag2_typed_fact_extraction_eval.dart';
import 'rag2_typed_fact_oracle_eval.dart';

const rag2TypedFactExtractionHoldoutSchema =
    'caverno_rag2_typed_fact_extraction_holdout_eval';
const rag2TypedFactExtractionHoldoutSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2TypedFactExtractionHoldoutOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_typed_fact_extraction_holdout_eval.dart '
      '--fixture PATH --oracle-facts PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2TypedFactExtractionHoldoutEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 typed-fact extraction holdout failed: $error');
    exitCode = 65;
  }
}

Future<Rag2TypedFactExtractionHoldoutReport>
runRag2TypedFactExtractionHoldoutEval(
  Rag2TypedFactExtractionHoldoutOptions options,
) async {
  final fixture = await Rag2TypedFactExtractionFixture.load(
    File(options.fixturePath),
  );
  final corpusHash = await fixture.computeCorpusHash();
  if (corpusHash != fixture.corpusHash) {
    throw StateError('Typed-fact extraction holdout corpus hash mismatch.');
  }
  final oracle = await Rag2TypedEvidenceFactSet.load(
    File(options.oracleFactsPath),
  );
  await fixture.validateOracle(oracle);

  final extracted = await extractRag2TypedFacts(
    corpusRoot: fixture.corpusDirectory,
    corpusHash: corpusHash,
  );
  final metrics = Rag2FactExtractionMetrics.compare(
    oracle: oracle.facts,
    extracted: extracted,
  );
  final report = Rag2TypedFactExtractionHoldoutReport(
    fixtureId: fixture.fixtureId,
    extractorVersion: fixture.extractorVersion,
    oracleFactSetId: oracle.factSetId,
    corpusHash: corpusHash,
    metrics: metrics,
    extractedFacts: extracted,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_holdout_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_holdout_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag2TypedFactExtractionFixture {
  const Rag2TypedFactExtractionFixture({
    required this.sourceFile,
    required this.fixtureId,
    required this.extractorVersion,
    required this.corpusRoot,
    required this.corpusHash,
    required this.sourceFamilies,
  });

  final File sourceFile;
  final String fixtureId;
  final String extractorVersion;
  final String corpusRoot;
  final String corpusHash;
  final Set<Rag2ExtractionSourceFamily> sourceFamilies;

  Directory get corpusDirectory =>
      Directory('${sourceFile.parent.path}/$corpusRoot');

  static Future<Rag2TypedFactExtractionFixture> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != 'caverno_rag2_typed_fact_extraction_fixture' ||
        json['schemaVersion'] != 1) {
      throw StateError('Unsupported typed-fact extraction fixture schema.');
    }
    final families = (json['sourceFamilies'] as List)
        .cast<String>()
        .map(Rag2ExtractionSourceFamily.values.byName)
        .toSet();
    if (families.length != Rag2ExtractionSourceFamily.values.length ||
        !families.containsAll(Rag2ExtractionSourceFamily.values)) {
      throw StateError('Extraction fixture must cover every source family.');
    }
    final fixture = Rag2TypedFactExtractionFixture(
      sourceFile: file,
      fixtureId: json['fixtureId']! as String,
      extractorVersion: json['extractorVersion']! as String,
      corpusRoot: json['corpusRoot']! as String,
      corpusHash: json['corpusHash']! as String,
      sourceFamilies: families,
    );
    if (fixture.extractorVersion != 'typed-fact-extraction-v1-frozen' ||
        !fixture.corpusDirectory.existsSync()) {
      throw StateError('Extraction fixture identity is invalid.');
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
      throw StateError('Extraction holdout oracle identity is invalid.');
    }
    final coveredFamilies = <Rag2ExtractionSourceFamily>{};
    for (final fact in oracle.facts) {
      if (fact.provenanceKind != 'oracle_annotation' ||
          fact.provenanceCorpusHash != corpusHash ||
          fact.source.startLine < 1 ||
          fact.source.endLine < fact.source.startLine) {
        throw StateError('Extraction holdout oracle provenance is invalid.');
      }
      final source = File('${corpusDirectory.path}/${fact.source.objectId}');
      if (!source.existsSync() ||
          fact.source.endLine >
              await source.readAsLines().then((lines) => lines.length)) {
        throw StateError('Extraction holdout oracle span is invalid.');
      }
      coveredFamilies.add(rag2ExtractionSourceFamily(fact));
    }
    if (!coveredFamilies.containsAll(sourceFamilies)) {
      throw StateError('Extraction holdout oracle misses a source family.');
    }
  }
}

final class Rag2TypedFactExtractionHoldoutReport {
  const Rag2TypedFactExtractionHoldoutReport({
    required this.fixtureId,
    required this.extractorVersion,
    required this.oracleFactSetId,
    required this.corpusHash,
    required this.metrics,
    required this.extractedFacts,
  });

  final String fixtureId;
  final String extractorVersion;
  final String oracleFactSetId;
  final String corpusHash;
  final Rag2FactExtractionMetrics metrics;
  final List<Rag2TypedEvidenceFact> extractedFacts;

  Map<String, Object?> toJson() => {
    'schemaName': rag2TypedFactExtractionHoldoutSchema,
    'schemaVersion': rag2TypedFactExtractionHoldoutSchemaVersion,
    'fixtureId': fixtureId,
    'extractorVersion': extractorVersion,
    'oracleFactSetId': oracleFactSetId,
    'corpusHash': corpusHash,
    'holdoutIndependent': true,
    'result': metrics.meetsGate ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'downstreamMatcherDecision': 'not_evaluated',
    'extraction': metrics.toJson(),
    'extractedFacts': [for (final fact in extractedFacts) _factJson(fact)],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Typed Fact Extraction Holdout')
      ..writeln()
      ..writeln('- Extractor: `$extractorVersion`')
      ..writeln('- Holdout independent: `true`')
      ..writeln('- Extraction result: `${metrics.meetsGate ? 'go' : 'no_go'}`')
      ..writeln('- Downstream matcher: `not_evaluated`')
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Source family | Precision | Recall | F1 | Extracted / Oracle | Gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | --- |');
    for (final entry in metrics.byFamily.entries) {
      final score = entry.value;
      buffer.writeln(
        '| `${entry.key.name}` | ${score.precision.toStringAsFixed(3)} | '
        '${score.recall.toStringAsFixed(3)} | ${score.f1.toStringAsFixed(3)} | '
        '${score.extractedCount} / ${score.oracleCount} | '
        '${score.meetsGate ? 'pass' : 'fail'} |',
      );
    }
    final overall = metrics.overall;
    buffer.writeln(
      '| **Overall** | ${overall.precision.toStringAsFixed(3)} | '
      '${overall.recall.toStringAsFixed(3)} | '
      '${overall.f1.toStringAsFixed(3)} | '
      '${overall.extractedCount} / ${overall.oracleCount} | '
      '${metrics.meetsGate ? 'pass' : 'fail'} |',
    );
    return buffer.toString();
  }
}

Map<String, Object?> _factJson(Rag2TypedEvidenceFact fact) => {
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
};

final class Rag2TypedFactExtractionHoldoutOptions {
  const Rag2TypedFactExtractionHoldoutOptions({
    required this.fixturePath,
    required this.oracleFactsPath,
    required this.outDir,
  });

  final String fixturePath;
  final String oracleFactsPath;
  final String outDir;

  static Rag2TypedFactExtractionHoldoutOptions? parse(List<String> args) {
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
    return Rag2TypedFactExtractionHoldoutOptions(
      fixturePath: values['--fixture']!,
      oracleFactsPath: values['--oracle-facts']!,
      outDir: values['--out-dir']!,
    );
  }
}
