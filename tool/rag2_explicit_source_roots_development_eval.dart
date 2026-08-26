import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'rag2_explicit_source_roots_replay.dart';
import 'rag2_git_evidence_collector.dart'
    show Rag2GitProcessRunner, runRag2GitCommand;

const rag2ExplicitRootsDevelopmentEvalSchema =
    'caverno_rag2_explicit_source_roots_development_eval';
const rag2ExplicitRootsDevelopmentFixtureSchema =
    'caverno_rag2_explicit_source_roots_development_fixture';

const _usage = r'''
Usage: dart run tool/rag2_explicit_source_roots_development_eval.dart \
  --enable-evaluation \
  --project-root PATH \
  --declaration PATH \
  --fixture PATH
''';

Future<void> main(List<String> args) async {
  final options = Rag2ExplicitRootsDevelopmentEvalOptions.parse(args);
  if (options == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  try {
    final run = await runRag2ExplicitRootsDevelopmentEvaluation(
      projectRoot: options.projectRoot,
      declaration: _readJsonObject(options.declarationPath),
      fixture: _readJsonObject(options.fixturePath),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(run.toJson()));
  } on Object {
    stderr.writeln('RAG2 explicit roots development evaluation failed closed.');
    exitCode = 65;
  }
}

final class Rag2ExplicitRootsDevelopmentEvalOptions {
  const Rag2ExplicitRootsDevelopmentEvalOptions({
    required this.enabled,
    required this.projectRoot,
    required this.declarationPath,
    required this.fixturePath,
  });

  final bool enabled;
  final String projectRoot;
  final String declarationPath;
  final String fixturePath;

  static Rag2ExplicitRootsDevelopmentEvalOptions? parse(List<String> args) {
    var enabled = false;
    String? projectRoot;
    String? declarationPath;
    String? fixturePath;
    final seen = <String>{};
    for (var index = 0; index < args.length; index++) {
      final option = args[index];
      if (!seen.add(option)) return null;
      if (option == '--enable-evaluation') {
        enabled = true;
        continue;
      }
      if (index + 1 >= args.length) return null;
      final value = args[++index];
      switch (option) {
        case '--project-root':
          projectRoot = value;
        case '--declaration':
          declarationPath = value;
        case '--fixture':
          fixturePath = value;
        default:
          return null;
      }
    }
    if (!enabled ||
        (projectRoot?.trim().isEmpty ?? true) ||
        (declarationPath?.trim().isEmpty ?? true) ||
        (fixturePath?.trim().isEmpty ?? true)) {
      return null;
    }
    return Rag2ExplicitRootsDevelopmentEvalOptions(
      enabled: true,
      projectRoot: projectRoot!,
      declarationPath: declarationPath!,
      fixturePath: fixturePath!,
    );
  }
}

Future<Rag2ExplicitRootsDevelopmentEvalRun>
runRag2ExplicitRootsDevelopmentEvaluation({
  required String projectRoot,
  required Map<String, dynamic> declaration,
  required Map<String, dynamic> fixture,
  Rag2GitProcessRunner processRunner = runRag2GitCommand,
}) async {
  final projectId = declaration['projectId'] as String? ?? '';
  final replay = await runRag2ExplicitSourceRootsReplay(
    options: Rag2ExplicitSourceRootsOptions(
      enabled: true,
      projectId: projectId,
      projectRoot: projectRoot,
      sourceRoots: _stringList(declaration['sourceRoots']),
    ),
    processRunner: processRunner,
  );
  final acquisition = replay.report;
  final evaluation = evaluateRag2ExplicitRootsDevelopmentFixture(
    declaration: declaration,
    fixture: fixture,
    inventoryCandidatePaths: replay.inventoryCandidatePaths.toSet(),
    admittedSourcePaths: replay.admittedSourcePaths.toSet(),
  );
  final acquisitionDecision = acquisition.blockers.isEmpty ? 'go' : 'no_go';
  final blockers = <String>{
    if (acquisitionDecision != 'go' ||
        acquisition.admittedSourceCount !=
            acquisition.eligibleCandidateFileCount ||
        acquisition.admittedSourceCount !=
            evaluation.selectedCandidateFileCount)
      'acquisition_not_go',
    if (acquisition.declarationIdentity != declaration['declarationIdentity'])
      'acquisition_identity_mismatch',
    ...acquisition.blockers,
    ...evaluation.blockers,
  };
  return Rag2ExplicitRootsDevelopmentEvalRun(
    acquisition: acquisition,
    evaluation: evaluation,
    inventoryCandidatePaths: replay.inventoryCandidatePaths,
    admittedSourcePaths: replay.admittedSourcePaths,
    report: evaluation.toJson(
      acquisitionDecision: acquisitionDecision,
      acquisitionGitCommandCount: acquisition.gitCommandCount,
      acquisitionProjectIdentity: acquisition.projectIdentity,
      acquisitionDeclarationIdentity: acquisition.declarationIdentity,
      acquisitionInventoryIdentity: acquisition.inventoryMetadataIdentity,
      acquisitionSelectedIdentity: acquisition.selectedMetadataIdentity,
      blockers: blockers.toList()..sort(),
      fixtureIdentity: _fixtureIdentity(fixture),
    ),
  );
}

final class Rag2ExplicitRootsDevelopmentEvalRun {
  const Rag2ExplicitRootsDevelopmentEvalRun({
    required this.acquisition,
    required this.evaluation,
    required this.inventoryCandidatePaths,
    required this.admittedSourcePaths,
    required this.report,
  });

  final Rag2ExplicitSourceRootsReport acquisition;
  final Rag2ExplicitRootsDevelopmentEvaluation evaluation;
  final List<String> inventoryCandidatePaths;
  final List<String> admittedSourcePaths;
  final Map<String, dynamic> report;

  Map<String, dynamic> toJson() => report;
}

Rag2ExplicitRootsDevelopmentEvaluation
evaluateRag2ExplicitRootsDevelopmentFixture({
  required Map<String, dynamic> declaration,
  required Map<String, dynamic> fixture,
  required Set<String> inventoryCandidatePaths,
  required Set<String> admittedSourcePaths,
}) {
  final blockers = <String>{};
  final roots = _stringList(declaration['sourceRoots']);
  if (declaration['contract'] != rag2ExplicitSourceRootsContract ||
      roots.isEmpty ||
      fixture['schemaName'] != rag2ExplicitRootsDevelopmentFixtureSchema ||
      fixture['declarationId'] != declaration['declarationId'] ||
      fixture['declarationIdentity'] != declaration['declarationIdentity'] ||
      fixture['priorFixtureUse'] != 'forbidden') {
    blockers.add('fixture_contract_mismatch');
  }
  if (admittedSourcePaths.any(
    (path) => !inventoryCandidatePaths.contains(path),
  )) {
    blockers.add('admitted_source_not_inventoried');
  }

  final rawCases = fixture['cases'];
  if (rawCases is! List || rawCases.isEmpty) {
    blockers.add('evaluation_cases_unavailable');
    return Rag2ExplicitRootsDevelopmentEvaluation.empty(
      selectedCandidateFileCount: admittedSourcePaths.length,
      blockers: blockers,
    );
  }

  var availableCaseCount = 0;
  var notAvailableCaseCount = 0;
  var correctDecisionCount = 0;
  var inScopeEvidenceCount = 0;
  var includedInScopeEvidenceCount = 0;
  var outOfScopeEvidenceCount = 0;
  var excludedOutOfScopeEvidenceCount = 0;
  var unavailableOracleEvidenceCount = 0;
  final caseIds = <String>{};

  for (final rawCase in rawCases) {
    if (rawCase is! Map) {
      blockers.add('invalid_evaluation_case');
      continue;
    }
    final item = Map<String, dynamic>.from(rawCase);
    final caseId = item['id'];
    final question = item['question'];
    final expected = item['expectedDecision'];
    final evidencePaths = _stringList(item['requiredEvidencePaths']);
    if (caseId is! String ||
        caseId.trim().isEmpty ||
        !caseIds.add(caseId) ||
        question is! String ||
        question.trim().isEmpty ||
        (expected != 'available' && expected != 'not_available') ||
        evidencePaths.isEmpty ||
        evidencePaths.toSet().length != evidencePaths.length) {
      blockers.add('invalid_evaluation_case');
      continue;
    }

    final availableEvidence = evidencePaths
        .where(inventoryCandidatePaths.contains)
        .length;
    unavailableOracleEvidenceCount += evidencePaths.length - availableEvidence;
    final selectedEvidence = evidencePaths
        .where(admittedSourcePaths.contains)
        .length;
    final actual =
        availableEvidence == evidencePaths.length &&
            selectedEvidence == evidencePaths.length
        ? 'available'
        : 'not_available';
    if (actual == expected) correctDecisionCount++;

    if (expected == 'available') {
      availableCaseCount++;
      inScopeEvidenceCount += evidencePaths.length;
      includedInScopeEvidenceCount += selectedEvidence;
    } else {
      notAvailableCaseCount++;
      outOfScopeEvidenceCount += evidencePaths.length;
      excludedOutOfScopeEvidenceCount +=
          evidencePaths.length - selectedEvidence;
    }
  }

  if (unavailableOracleEvidenceCount > 0) {
    blockers.add('oracle_evidence_unavailable');
  }
  if (availableCaseCount == 0 || notAvailableCaseCount == 0) {
    blockers.add('control_mix_unavailable');
  }
  if (includedInScopeEvidenceCount != inScopeEvidenceCount) {
    blockers.add('in_scope_evidence_incomplete');
  }
  if (excludedOutOfScopeEvidenceCount != outOfScopeEvidenceCount) {
    blockers.add('out_of_scope_evidence_admitted');
  }
  if (correctDecisionCount != rawCases.length) {
    blockers.add('decision_mismatch');
  }

  return Rag2ExplicitRootsDevelopmentEvaluation(
    caseCount: rawCases.length,
    availableCaseCount: availableCaseCount,
    notAvailableCaseCount: notAvailableCaseCount,
    correctDecisionCount: correctDecisionCount,
    inScopeEvidenceCount: inScopeEvidenceCount,
    includedInScopeEvidenceCount: includedInScopeEvidenceCount,
    outOfScopeEvidenceCount: outOfScopeEvidenceCount,
    excludedOutOfScopeEvidenceCount: excludedOutOfScopeEvidenceCount,
    unavailableOracleEvidenceCount: unavailableOracleEvidenceCount,
    selectedCandidateFileCount: admittedSourcePaths.length,
    blockers: blockers,
  );
}

final class Rag2ExplicitRootsDevelopmentEvaluation {
  const Rag2ExplicitRootsDevelopmentEvaluation({
    required this.caseCount,
    required this.availableCaseCount,
    required this.notAvailableCaseCount,
    required this.correctDecisionCount,
    required this.inScopeEvidenceCount,
    required this.includedInScopeEvidenceCount,
    required this.outOfScopeEvidenceCount,
    required this.excludedOutOfScopeEvidenceCount,
    required this.unavailableOracleEvidenceCount,
    required this.selectedCandidateFileCount,
    required this.blockers,
  });

  const Rag2ExplicitRootsDevelopmentEvaluation.empty({
    required this.selectedCandidateFileCount,
    required this.blockers,
  }) : caseCount = 0,
       availableCaseCount = 0,
       notAvailableCaseCount = 0,
       correctDecisionCount = 0,
       inScopeEvidenceCount = 0,
       includedInScopeEvidenceCount = 0,
       outOfScopeEvidenceCount = 0,
       excludedOutOfScopeEvidenceCount = 0,
       unavailableOracleEvidenceCount = 0;

  final int caseCount;
  final int availableCaseCount;
  final int notAvailableCaseCount;
  final int correctDecisionCount;
  final int inScopeEvidenceCount;
  final int includedInScopeEvidenceCount;
  final int outOfScopeEvidenceCount;
  final int excludedOutOfScopeEvidenceCount;
  final int unavailableOracleEvidenceCount;
  final int selectedCandidateFileCount;
  final Set<String> blockers;

  Map<String, dynamic> toJson({
    String acquisitionDecision = 'not_run',
    int acquisitionGitCommandCount = 0,
    String? acquisitionProjectIdentity,
    String? acquisitionDeclarationIdentity,
    String? acquisitionInventoryIdentity,
    String? acquisitionSelectedIdentity,
    List<String>? blockers,
    String? fixtureIdentity,
  }) {
    final effectiveBlockers = blockers ?? (this.blockers.toList()..sort());
    return {
      'schemaName': rag2ExplicitRootsDevelopmentEvalSchema,
      'schemaVersion': 1,
      'contract': rag2ExplicitSourceRootsContract,
      'evaluationStage': 'development',
      'developmentDecision': effectiveBlockers.isEmpty ? 'go' : 'no_go',
      'promotionDecision': 'not_evaluated',
      'storageDecision': 'not_evaluated',
      'retrievalDecision': 'not_evaluated',
      'productionDecision': 'no_go',
      'fixtureIdentity': fixtureIdentity,
      'acquisitionDecision': acquisitionDecision,
      'acquisitionGitCommandCount': acquisitionGitCommandCount,
      'acquisitionProjectIdentity': acquisitionProjectIdentity,
      'acquisitionDeclarationIdentity': acquisitionDeclarationIdentity,
      'acquisitionInventoryIdentity': acquisitionInventoryIdentity,
      'acquisitionSelectedIdentity': acquisitionSelectedIdentity,
      'selectedCandidateFileCount': selectedCandidateFileCount,
      'caseCount': caseCount,
      'availableCaseCount': availableCaseCount,
      'notAvailableCaseCount': notAvailableCaseCount,
      'correctDecisionCount': correctDecisionCount,
      'inScopeEvidenceCount': inScopeEvidenceCount,
      'includedInScopeEvidenceCount': includedInScopeEvidenceCount,
      'outOfScopeEvidenceCount': outOfScopeEvidenceCount,
      'excludedOutOfScopeEvidenceCount': excludedOutOfScopeEvidenceCount,
      'unavailableOracleEvidenceCount': unavailableOracleEvidenceCount,
      'blockers': effectiveBlockers,
    };
  }
}

Map<String, dynamic> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map) throw const FormatException('Expected a JSON object.');
  return Map<String, dynamic>.from(decoded);
}

List<String> _stringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) return const [];
  return List<String>.unmodifiable(value.cast<String>());
}

String _fixtureIdentity(Map<String, dynamic> fixture) =>
    'fixture_${sha256.convert(utf8.encode(jsonEncode(fixture)))}';
