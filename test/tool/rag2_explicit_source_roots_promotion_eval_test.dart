import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_explicit_source_roots_development_eval.dart';
import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_source_discovery_replay.dart';

const _declarationPath =
    'tool/fixtures/rag2_explicit_source_roots_holdout_v1/declaration.json';
const _fixturePath =
    'tool/fixtures/rag2_explicit_source_roots_holdout_v1/evaluation.json';

void main() {
  late Map<String, dynamic> declaration;
  late Map<String, dynamic> fixture;
  late Set<String> inventoryPaths;

  setUpAll(() async {
    declaration = _readFixture(_declarationPath);
    fixture = _readFixture(_fixturePath);
    final project = CodingProject(
      id: declaration['projectId'] as String,
      name: 'RAG2 promotion fixture test',
      rootPath: Directory.current.path,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final inventory = await inventoryRag2SourceCandidates(
      project: project,
      maxFileBytes: rag2ExplicitSourceRootsPolicy.maxFileBytes,
    );
    inventoryPaths = {
      for (final candidate in inventory.candidates) candidate.path,
    };
  });

  test('passes every frozen promotion scope gate', () {
    final result = evaluateRag2ExplicitRootsDevelopmentFixture(
      declaration: declaration,
      fixture: fixture,
      inventoryCandidatePaths: inventoryPaths,
    );

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
    expect(result.selectedCandidateFileCount, 15);
  });

  test('fails when an out-of-scope control points inside the declaration', () {
    final changedFixture = _deepCopy(fixture);
    final cases = changedFixture['cases'] as List<dynamic>;
    final control = cases.last as Map<String, dynamic>;
    control['requiredEvidencePaths'] = [
      'lib/features/routines/domain/entities/routine.dart',
    ];

    final result = evaluateRag2ExplicitRootsDevelopmentFixture(
      declaration: declaration,
      fixture: changedFixture,
      inventoryCandidatePaths: inventoryPaths,
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
      inventoryCandidatePaths: inventoryPaths,
    );

    expect(result.blockers, contains('oracle_evidence_unavailable'));
    expect(result.blockers, contains('in_scope_evidence_incomplete'));
    expect(result.blockers, contains('decision_mismatch'));
  });

  test('keeps aggregate output free of questions and evidence paths', () {
    final result = evaluateRag2ExplicitRootsDevelopmentFixture(
      declaration: declaration,
      fixture: fixture,
      inventoryCandidatePaths: inventoryPaths,
    );
    final output = jsonEncode(result.toJson());

    for (final rawCase in fixture['cases'] as List<dynamic>) {
      final item = rawCase as Map<String, dynamic>;
      expect(output, isNot(contains(item['question'] as String)));
      for (final path in item['requiredEvidencePaths'] as List<dynamic>) {
        expect(output, isNot(contains(path as String)));
      }
    }
  });
}

Map<String, dynamic> _readFixture(String path) =>
    Map<String, dynamic>.from(jsonDecode(File(path).readAsStringSync()) as Map);

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
