import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_typed_fact_extraction_eval.dart';

void main() {
  test('extracts mechanical Dart assignments without claim input', () {
    final facts = extractDartAssignmentFacts(
      content:
          "const defaultReportFormat = 'json';\n"
          'const retryCount = 3;\n'
          'const dynamicValue = resolveValue();\n',
      objectId: 'lib/config.dart',
      corpusHash: 'hash',
    );

    expect(facts, hasLength(2));
    expect(facts.first.atom.subject, 'default_report');
    expect(facts.first.atom.relation, 'config.format');
    expect(facts.first.atom.value.value, 'json');
    expect(facts.last.atom.subject, 'retry');
    expect(facts.last.atom.relation, 'config.count');
    expect(facts.last.atom.value.value, 3);
    expect(
      facts.map((fact) => fact.provenanceKind),
      everyElement('deterministic_extractor'),
    );
  });

  test('extracts explicit and default URI ports with source spans', () {
    final facts = extractMarkdownUriFacts(
      content:
          'The admin console is served at `https://admin.local:7443`.\n'
          'The public portal uses\n'
          '`https://portal.local/docs` over HTTPS.\n',
      objectId: 'docs/endpoints.md',
      corpusHash: 'hash',
    );

    expect(facts, hasLength(2));
    expect(facts.first.atom.subject, 'admin_console');
    expect(facts.first.atom.value.value, 7443);
    expect(facts.first.source.startLine, 1);
    expect(facts.first.source.endLine, 1);
    expect(facts.last.atom.subject, 'public_portal');
    expect(facts.last.atom.value.value, 443);
    expect(facts.last.source.startLine, 2);
    expect(facts.last.source.endLine, 3);
  });

  test('measures extraction separately from the frozen matcher', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-fact-extraction-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2TypedFactExtractionEval(
      _options(directory.path),
    );

    expect(report.extraction.meetsGate, isFalse);
    expect(report.extraction.overall.extractedCount, 9);
    expect(report.extraction.overall.oracleCount, 14);
    expect(report.extraction.overall.precision, 1.0);
    expect(report.extraction.overall.recall, closeTo(9 / 14, 0.000001));
    expect(
      report
          .extraction
          .byFamily[Rag2ExtractionSourceFamily.dartAssignment]!
          .meetsGate,
      isTrue,
    );
    expect(
      report
          .extraction
          .byFamily[Rag2ExtractionSourceFamily.markdownUri]!
          .meetsGate,
      isTrue,
    );
    expect(
      report.extraction.byFamily[Rag2ExtractionSourceFamily.proseState]!.recall,
      0.0,
    );
    expect(report.matcher.meetsGate, isTrue);
    expect(report.matcher.macroF1, closeTo(0.9153439153, 0.000001));
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_typed_fact_extraction_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_typed_fact_extraction_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });
}

Rag2TypedFactExtractionOptions _options(
  String outDir,
) => Rag2TypedFactExtractionOptions(
  claimsPath: 'tool/fixtures/rag2_compositional_holdout/claims.json',
  claimAtomsPath: 'tool/fixtures/rag2_compositional_holdout/claim_atoms.json',
  envelopesPath: 'tool/fixtures/rag2_compositional_holdout/envelopes.json',
  oracleFactsPath: 'tool/fixtures/rag2_compositional_holdout/oracle_facts.json',
  fixturePath: 'tool/fixtures/rag2_compositional_holdout/fixture.json',
  outDir: outDir,
);
