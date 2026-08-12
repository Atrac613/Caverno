import 'dart:convert';

import '../domain/entities/personal_eval_case.dart';

/// Loads the committed authored fixture corpus into [PersonalEvalCase]s.
///
/// Every case it produces is stamped `origin: authored`, which is the whole
/// point: the 2026-08-12 inventory found about two distinct recorded coding
/// tasks against a requirement of twenty, so this corpus carries the model
/// comparison — and a report that let authored evidence pass as recorded would
/// claim representativeness the corpus does not have.
class PersonalEvalAuthoredCorpus {
  const PersonalEvalAuthoredCorpus({
    required this.schemaVersion,
    required this.seedRoot,
    required this.cases,
  });

  static const schemaName = 'caverno_personal_eval_authored_corpus';
  static const supportedSchemaVersion = 1;

  final int schemaVersion;

  /// Directory under a fixture holding per-case seed overlays.
  final String seedRoot;

  final List<PersonalEvalCase> cases;

  List<PersonalEvalCase> get heldIn => cases
      .where((item) => item.split == PersonalEvalCaseSplit.heldIn)
      .toList(growable: false);

  List<PersonalEvalCase> get heldOut => cases
      .where((item) => item.split == PersonalEvalCaseSplit.heldOut)
      .toList(growable: false);

  /// Parses [source]. Throws [FormatException] rather than skipping a bad task:
  /// a corpus that silently drops entries would change the denominator of a
  /// comparison without saying so.
  factory PersonalEvalAuthoredCorpus.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'Authored corpus is not valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Authored corpus must be a JSON object.');
    }
    if (decoded['schemaName'] != schemaName) {
      throw FormatException(
        'Authored corpus schemaName must be $schemaName, '
        'got ${decoded['schemaName']}.',
      );
    }
    final version = decoded['schemaVersion'];
    if (version is! int || version > supportedSchemaVersion) {
      throw FormatException(
        'Unsupported authored corpus schemaVersion $version; this build '
        'understands up to $supportedSchemaVersion.',
      );
    }

    final replay = decoded['replay'];
    final rawSeedRoot = replay is Map<String, dynamic>
        ? replay['seedRoot']
        : null;
    if (rawSeedRoot != null && rawSeedRoot is! String) {
      throw const FormatException('Authored corpus seedRoot must be a string.');
    }
    final seedRoot = (rawSeedRoot as String? ?? 'seeds').trim();
    if (seedRoot.isEmpty) {
      throw const FormatException(
        'Authored corpus seedRoot must not be empty.',
      );
    }

    final rawTasks = decoded['tasks'];
    if (rawTasks is! List || rawTasks.isEmpty) {
      throw const FormatException('Authored corpus has no tasks.');
    }

    final seenIds = <String>{};
    final seenReconstructionObjectives = <String>{};
    final cases = <PersonalEvalCase>[];
    for (final raw in rawTasks) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Authored corpus task must be an object.');
      }
      final caseId = (raw['caseId'] as String? ?? '').trim();
      if (caseId.isEmpty) {
        throw const FormatException('Authored corpus task is missing caseId.');
      }
      if (!seenIds.add(caseId)) {
        throw FormatException('Duplicate authored corpus caseId $caseId.');
      }
      final split = switch (raw['split']) {
        'heldIn' => PersonalEvalCaseSplit.heldIn,
        'heldOut' => PersonalEvalCaseSplit.heldOut,
        final value => throw FormatException(
          'Authored corpus task $caseId has invalid split $value.',
        ),
      };
      final tier = raw['tier'];
      if (tier is! int || tier < 1 || tier > 3) {
        throw FormatException(
          'Authored corpus task $caseId has invalid tier $tier.',
        );
      }
      if (tier >= 2) {
        final objectiveFingerprint = raw['objectiveFingerprint'];
        if (objectiveFingerprint is! String ||
            objectiveFingerprint.trim().isEmpty) {
          throw FormatException(
            'Authored corpus reconstruction task $caseId is missing an '
            'objectiveFingerprint.',
          );
        }
        if (!seenReconstructionObjectives.add(objectiveFingerprint.trim())) {
          throw FormatException(
            'Duplicate authored corpus reconstruction objective '
            '${objectiveFingerprint.trim()}.',
          );
        }
      }
      final promptStyle = switch (raw['promptStyle']) {
        'guided' => PersonalEvalPromptStyle.guided,
        'unguided' => PersonalEvalPromptStyle.unguided,
        final value => throw FormatException(
          'Authored corpus task $caseId has invalid promptStyle $value.',
        ),
      };
      final evalCase = PersonalEvalCase(
        caseId: caseId,
        title: (raw['title'] as String? ?? '').trim(),
        prompt: (raw['prompt'] as String? ?? '').trim(),
        // Authored tasks have no recorded repository ref; their state is the
        // committed fixture plus the seed overlay.
        repoStateRef: '',
        fixtureDirectory: (raw['fixtureDirectory'] as String? ?? '').trim(),
        verificationCommand: (raw['verificationCommand'] as String? ?? '')
            .trim(),
        origin: PersonalEvalCaseOrigin.authored,
        split: split,
        tier: tier,
        promptStyle: promptStyle,
        workspaceMode: 'coding',
      );
      if (evalCase.readiness != PersonalEvalCaseReadiness.ready) {
        throw FormatException(
          'Authored corpus task $caseId is not runnable: it needs a prompt, a '
          'fixture directory, and a verification command.',
        );
      }
      cases.add(evalCase);
    }

    return PersonalEvalAuthoredCorpus(
      schemaVersion: version,
      seedRoot: seedRoot,
      cases: List.unmodifiable(cases),
    );
  }
}
