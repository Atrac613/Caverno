import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_explicit_source_roots_development_eval.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart'
    show rag2ExplicitSourceRootsPolicy;

const _declarationPath =
    'tool/fixtures/rag2_explicit_source_roots_holdout_v1/declaration.json';
const _fixturePath =
    'tool/fixtures/rag2_explicit_source_roots_holdout_v1/evaluation.json';
const _inScopeEvidencePath =
    'lib/features/routines/domain/entities/routine.dart';

void main() {
  late Map<String, dynamic> declaration;
  late Map<String, dynamic> fixture;
  late Rag2ExplicitRootsDevelopmentEvalRun run;

  setUpAll(() async {
    declaration = _readFixture(_declarationPath);
    fixture = _readFixture(_fixturePath);
    run = await runRag2ExplicitRootsDevelopmentEvaluation(
      projectRoot: Directory.current.path,
      declaration: declaration,
      fixture: fixture,
    );
  });

  test('passes live acquisition and every frozen promotion scope gate', () {
    final acquisition = run.acquisition;
    final result = run.evaluation;

    expect(acquisition.blockers, isEmpty);
    expect(acquisition.contractPassed, isTrue);
    expect(acquisition.declarationIdentity, declaration['declarationIdentity']);
    expect(acquisition.gitCommandCount, 3);
    expect(
      acquisition.admittedSourceCount,
      acquisition.eligibleCandidateFileCount,
    );
    expect(
      acquisition.admittedSourceCount,
      greaterThanOrEqualTo(result.inScopeEvidenceCount),
    );
    expect(
      acquisition.admittedSourceCount,
      lessThanOrEqualTo(rag2ExplicitSourceRootsPolicy.maxFiles),
    );
    expect(run.admittedSourcePaths, hasLength(acquisition.admittedSourceCount));
    expect(result.blockers, isEmpty);
    expect(result.caseCount, 11);
    expect(result.availableCaseCount, 7);
    expect(result.notAvailableCaseCount, 4);
    expect(result.correctDecisionCount, 11);
    expect(result.inScopeEvidenceCount, 8);
    expect(result.includedInScopeEvidenceCount, 8);
    expect(result.outOfScopeEvidenceCount, 4);
    expect(result.excludedOutOfScopeEvidenceCount, 4);
    expect(result.unavailableOracleEvidenceCount, 0);
    expect(result.selectedCandidateFileCount, acquisition.admittedSourceCount);
    expect(run.report['acquisitionDecision'], 'go');
    expect(run.report['blockers'], isEmpty);
  });

  test('fails when an out-of-scope control points inside the declaration', () {
    final changedFixture = _deepCopy(fixture);
    final cases = changedFixture['cases'] as List<dynamic>;
    final control = cases.last as Map<String, dynamic>;
    control['requiredEvidencePaths'] = [_inScopeEvidencePath];

    final result = evaluateRag2ExplicitRootsDevelopmentFixture(
      declaration: declaration,
      fixture: changedFixture,
      inventoryCandidatePaths: run.inventoryCandidatePaths.toSet(),
      admittedSourcePaths: run.admittedSourcePaths.toSet(),
    );

    expect(result.blockers, contains('out_of_scope_evidence_admitted'));
    expect(result.blockers, contains('decision_mismatch'));
  });

  test('fails when required in-scope evidence is unavailable', () {
    final changedFixture = _deepCopy(fixture);
    final cases = changedFixture['cases'] as List<dynamic>;
    final inScope = cases.first as Map<String, dynamic>;
    inScope['requiredEvidencePaths'] = [
      'lib/features/routines/domain/entities/missing_routine.dart',
    ];

    final result = evaluateRag2ExplicitRootsDevelopmentFixture(
      declaration: declaration,
      fixture: changedFixture,
      inventoryCandidatePaths: run.inventoryCandidatePaths.toSet(),
      admittedSourcePaths: run.admittedSourcePaths.toSet(),
    );

    expect(result.blockers, contains('oracle_evidence_unavailable'));
    expect(result.blockers, contains('in_scope_evidence_incomplete'));
    expect(result.blockers, contains('decision_mismatch'));
  });

  test('fails when acquisition omits required in-scope evidence', () {
    final omitted = run.admittedSourcePaths.toSet()
      ..remove(_inScopeEvidencePath);

    final result = evaluateRag2ExplicitRootsDevelopmentFixture(
      declaration: declaration,
      fixture: fixture,
      inventoryCandidatePaths: run.inventoryCandidatePaths.toSet(),
      admittedSourcePaths: omitted,
    );

    expect(result.blockers, contains('in_scope_evidence_incomplete'));
    expect(result.blockers, contains('decision_mismatch'));
  });

  test('keeps aggregate output free of questions and evidence paths', () {
    final output = jsonEncode(run.toJson());

    for (final rawCase in fixture['cases'] as List<dynamic>) {
      final item = rawCase as Map<String, dynamic>;
      expect(output, isNot(contains(item['question'] as String)));
      for (final path in item['requiredEvidencePaths'] as List<dynamic>) {
        expect(output, isNot(contains(path as String)));
      }
    }
    expect(output, isNot(contains('inventoryCandidatePaths')));
    expect(output, isNot(contains('admittedSourcePaths')));
  });
}

Map<String, dynamic> _readFixture(String path) =>
    Map<String, dynamic>.from(jsonDecode(File(path).readAsStringSync()) as Map);

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
