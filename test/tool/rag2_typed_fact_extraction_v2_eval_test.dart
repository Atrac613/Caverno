import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_typed_fact_extraction_eval.dart';
import '../../tool/rag2_typed_fact_extraction_v2_eval.dart';

void main() {
  test('v2 accepts only syntax-level simple Dart literals', () {
    const content =
        "const defaultFormat = 'json';\n"
        'const retryCount = 3;\n'
        'const diagnosticsEnabled = true;\n'
        r'''const releaseChannel = "stable-${'beta'}";'''
        '\n'
        'const computedTimeout = 5 * 60;\n';

    final v1 = extractDartAssignmentFacts(
      content: content,
      objectId: 'lib/config.dart',
      corpusHash: 'hash',
    );
    final v2 = extractDartAssignmentFactsV2(
      content: content,
      objectId: 'lib/config.dart',
      corpusHash: 'hash',
    );

    expect(v1, hasLength(4));
    expect(v2, hasLength(3));
    expect(v2.map((fact) => fact.atom.subject), [
      'default',
      'retry',
      'diagnostics',
    ]);
    expect(
      v2.map((fact) => fact.provenanceKind),
      everyElement('deterministic_extractor_v2'),
    );
  });

  test('v2 rejects malformed URI tokens without adding relation aliases', () {
    const content =
        'The billing console uses `https://billing.local:8443`.\n'
        'The broken endpoint uses `https://bad.local:notaport`.\n'
        'Edge endpoint `https://edge.local:7444` is healthy.\n';

    final v1 = extractMarkdownUriFacts(
      content: content,
      objectId: 'docs/services.md',
      corpusHash: 'hash',
    );
    final v2 = extractMarkdownUriFactsV2(
      content: content,
      objectId: 'docs/services.md',
      corpusHash: 'hash',
    );

    expect(v1.map((fact) => fact.atom.subject), [
      'billing_console',
      'broken_endpoint',
    ]);
    expect(v2.map((fact) => fact.atom.subject), ['billing_console']);
    expect(v2.single.atom.value.value, 8443);
  });

  test('compares precision-only v2 across both frozen fixtures', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-extraction-v2-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2TypedFactExtractionV2Eval(
      _options(directory.path),
    );

    expect(report.development.v1.overall.precision, 1.0);
    expect(report.development.v2.overall.precision, 1.0);
    expect(report.development.v2.overall.recall, closeTo(9 / 14, 0.000001));
    expect(report.holdout.v1.overall.precision, closeTo(5 / 7, 0.000001));
    expect(report.holdout.v2.overall.precision, 1.0);
    expect(report.holdout.v2.overall.recall, closeTo(5 / 11, 0.000001));
    expect(report.holdout.v2.overall.f1, 0.625);
    expect(report.holdout.v2.meetsGate, isFalse);
    expect(report.toJson()['independentPromotionEvidence'], isFalse);
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_typed_fact_extraction_v2_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_typed_fact_extraction_v2_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });
}

Rag2TypedFactExtractionV2Options _options(String outDir) =>
    Rag2TypedFactExtractionV2Options(
      developmentFixturePath:
          'tool/fixtures/rag2_compositional_holdout/fixture.json',
      developmentOracleFactsPath:
          'tool/fixtures/rag2_compositional_holdout/oracle_facts.json',
      holdoutFixturePath: 'tool/fixtures/rag2_extraction_holdout/fixture.json',
      holdoutOracleFactsPath:
          'tool/fixtures/rag2_extraction_holdout/oracle_facts.json',
      outDir: outDir,
    );
