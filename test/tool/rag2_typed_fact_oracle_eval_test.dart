import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_post_answer_claim_eval.dart';
import '../../tool/rag2_structured_claim_eval.dart';
import '../../tool/rag2_typed_fact_oracle_eval.dart';

void main() {
  test('matches typed values and rejects non-asserted evidence', () {
    const claim = Rag2TypedClaimAtom(
      candidateId: 'claim',
      claimText: 'The service port is 443.',
      atom: Rag2TypedAtom(
        subject: 'service',
        relation: 'network.port',
        value: Rag2TypedValue(type: Rag2FactValueType.integer, value: 443),
        scope: Rag2FactScope.current,
        polarity: Rag2FactPolarity.positive,
        modality: Rag2FactModality.asserted,
      ),
    );
    const envelope = Rag2ClaimEnvelope(
      candidateId: 'claim',
      scope: Rag2ClaimScope.current,
      citedSourceIds: ['source.md'],
    );

    expect(
      matchRag2TypedFact(
        claim: claim,
        envelope: envelope,
        facts: [_fact(value: 443)],
      ).verdict,
      Rag2ClaimVerdict.supported,
    );
    expect(
      matchRag2TypedFact(
        claim: claim,
        envelope: envelope,
        facts: [_fact(value: 8443)],
      ).verdict,
      Rag2ClaimVerdict.contradicted,
    );
    expect(
      matchRag2TypedFact(
        claim: claim,
        envelope: envelope,
        facts: [_fact(value: 443, modality: Rag2FactModality.conditional)],
      ).verdict,
      Rag2ClaimVerdict.absent,
    );
    expect(
      matchRag2TypedFact(
        claim: claim,
        envelope: envelope,
        facts: [_fact(value: 443, objectId: 'other.md')],
      ).verdict,
      Rag2ClaimVerdict.absent,
    );
  });

  test('evaluates the frozen oracle facts deterministically', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-fact-oracle-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2TypedFactOracleEval(_options(directory.path));

    expect(report.passed, isTrue);
    expect(report.result.cases, hasLength(12));
    expect(report.result.macroF1, 1.0);
    expect(
      report.result.metrics.values.map((metric) => metric.f1),
      everyElement(1.0),
    );
    expect(report.toJson()['extractionDecision'], 'not_evaluated');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_typed_fact_oracle_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_typed_fact_oracle_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test('rejects an oracle fact outside its source span', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-fact-invalid-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final json =
        jsonDecode(
              File(
                'tool/fixtures/rag2_compositional_holdout/oracle_facts.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final facts = (json['facts']! as List).cast<Map<String, Object?>>();
    final source = (facts.first['source']! as Map).cast<String, Object?>();
    source['endLine'] = 999;
    final invalidFacts = File('${directory.path}/invalid_facts.json');
    invalidFacts.writeAsStringSync(jsonEncode(json));

    final options = _options(directory.path);
    await expectLater(
      runRag2TypedFactOracleEval(
        Rag2TypedFactOracleOptions(
          claimsPath: options.claimsPath,
          claimAtomsPath: options.claimAtomsPath,
          envelopesPath: options.envelopesPath,
          factsPath: invalidFacts.path,
          fixturePath: options.fixturePath,
          outDir: options.outDir,
        ),
      ),
      throwsStateError,
    );
  });
}

Rag2TypedEvidenceFact _fact({
  required int value,
  String objectId = 'source.md',
  Rag2FactModality modality = Rag2FactModality.asserted,
}) => Rag2TypedEvidenceFact(
  factId: 'fact-$value-$objectId-${modality.name}',
  atom: Rag2TypedAtom(
    subject: 'service',
    relation: 'network.port',
    value: Rag2TypedValue(type: Rag2FactValueType.integer, value: value),
    scope: Rag2FactScope.current,
    polarity: Rag2FactPolarity.positive,
    modality: modality,
  ),
  source: Rag2FactSource(objectId: objectId, startLine: 1, endLine: 1),
  provenanceKind: 'oracle_annotation',
  provenanceCorpusHash: 'hash',
);

Rag2TypedFactOracleOptions _options(String outDir) =>
    Rag2TypedFactOracleOptions(
      claimsPath: 'tool/fixtures/rag2_compositional_holdout/claims.json',
      claimAtomsPath:
          'tool/fixtures/rag2_compositional_holdout/claim_atoms.json',
      envelopesPath: 'tool/fixtures/rag2_compositional_holdout/envelopes.json',
      factsPath: 'tool/fixtures/rag2_compositional_holdout/oracle_facts.json',
      fixturePath: 'tool/fixtures/rag2_compositional_holdout/fixture.json',
      outDir: outDir,
    );
