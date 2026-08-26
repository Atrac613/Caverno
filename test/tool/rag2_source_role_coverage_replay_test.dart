import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_source_role_coverage_replay.dart';
import '../../tool/rag2_source_scope_measurement.dart';

void main() {
  test('measures aggregate oracle coverage across frozen profiles', () async {
    final root = Directory.systemTemp.createTempSync('rag2-role-coverage-');
    addTearDown(() => root.deleteSync(recursive: true));
    final fixture = _writeSyntheticFixture(root);

    final report = await runRag2SourceRoleCoverageReplay(
      _options(root, fixture),
    );
    final profiles = {
      for (final profile in report.profiles) profile.profileId: profile,
    };
    final json = jsonEncode(report.toJson());

    expect(report.questionCount, 8);
    expect(report.validatedEvidenceFileCount, 8);
    expect(report.requiredMarkerCount, 8);
    expect(report.inventoryMetadataIdentity, startsWith('inventory_metadata_'));
    expect(report.validatedEvidenceIdentity, startsWith('evidence_'));
    expect(report.sourceRoleQuestionCounts, {
      'documentation': 2,
      'root_sources': 1,
      'runtime_source': 2,
      'tests': 2,
      'tooling': 1,
    });
    expect(profiles['all_candidates_control']?.coveredQuestionCount, 8);
    expect(profiles['runtime_only']?.coveredQuestionCount, 2);
    expect(profiles['runtime_and_top_level_docs']?.coveredQuestionCount, 4);
    expect(
      profiles['runtime_tests_and_top_level_docs']?.coveredQuestionCount,
      6,
    );
    expect(profiles['runtime_only']?.blockers, [
      'question_coverage_incomplete',
    ]);
    expect(report.toJson()['scopeDecision'], 'not_selected');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      (report.toJson()['policy']! as Map<String, Object?>)['defaultMaxFiles'],
      512,
    );
    expect(
      report.toJson()['evaluationMode'],
      'oracle_required_source_coverage_only',
    );
    for (final forbidden in [
      root.path,
      'private question',
      'private evidence marker',
      'lib/runtime_a.dart',
      'README.md',
    ]) {
      expect(json, isNot(contains(forbidden)));
    }
  });

  test('fails closed when an evidence marker or source role drifts', () async {
    final root = Directory.systemTemp.createTempSync('rag2-role-drift-');
    addTearDown(() => root.deleteSync(recursive: true));
    final fixture = _writeSyntheticFixture(root);
    final decoded =
        jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;
    final questions = decoded['questions']! as List<Object?>;
    final first = questions.first! as Map<String, Object?>;

    final firstSources = first['evidenceSources']! as List<Object?>;
    final firstSource = firstSources.first! as Map<String, Object?>;
    firstSource['requiredMarkers'] = ['missing marker'];
    fixture.writeAsStringSync(jsonEncode(decoded));
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );

    firstSource['requiredMarkers'] = ['private evidence marker runtime a'];
    first['expectedSourceRole'] = 'documentation';
    fixture.writeAsStringSync(jsonEncode(decoded));
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );
  });

  test(
    'rejects unsafe paths, duplicate IDs, and duplicate evidence paths',
    () async {
      final root = Directory.systemTemp.createTempSync('rag2-role-invalid-');
      addTearDown(() => root.deleteSync(recursive: true));
      final fixture = _writeSyntheticFixture(root);
      final decoded =
          jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;
      final questions = decoded['questions']! as List<Object?>;
      final first = questions.first! as Map<String, Object?>;

      final firstSources = first['evidenceSources']! as List<Object?>;
      final firstSource = firstSources.first! as Map<String, Object?>;
      firstSource['evidencePath'] = '../escape.md';
      fixture.writeAsStringSync(jsonEncode(decoded));
      await expectLater(
        Rag2SourceRoleCoverageFixture.load(fixture),
        throwsFormatException,
      );

      firstSource['evidencePath'] = 'lib/runtime_a.dart';
      final second = questions[1]! as Map<String, Object?>;
      second['id'] = first['id'];
      fixture.writeAsStringSync(jsonEncode(decoded));
      await expectLater(
        Rag2SourceRoleCoverageFixture.load(fixture),
        throwsFormatException,
      );

      second['id'] = 'question-1';
      final secondSources = second['evidenceSources']! as List<Object?>;
      final secondSource = secondSources.first! as Map<String, Object?>;
      secondSource['evidencePath'] = 'lib/runtime_a.dart';
      fixture.writeAsStringSync(jsonEncode(decoded));
      await expectLater(
        Rag2SourceRoleCoverageFixture.load(fixture),
        throwsFormatException,
      );
    },
  );

  test('requires every marker in an evidence source', () async {
    final root = Directory.systemTemp.createTempSync('rag2-role-all-of-');
    addTearDown(() => root.deleteSync(recursive: true));
    final fixture = _writeSyntheticFixture(root, addSecondRuntimeMarker: true);

    final report = await runRag2SourceRoleCoverageReplay(
      _options(root, fixture),
    );
    expect(report.requiredMarkerCount, 9);

    File(
      '${root.path}/lib/runtime_a.dart',
    ).writeAsStringSync('private evidence marker runtime a');
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );
  });

  test('requires every evidence source for a question', () async {
    final root = Directory.systemTemp.createTempSync('rag2-role-sources-');
    addTearDown(() => root.deleteSync(recursive: true));
    final fixture = _writeSyntheticFixture(root);
    final support = File('${root.path}/lib/runtime_support.dart')
      ..writeAsStringSync('private supporting evidence marker');
    final decoded =
        jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;
    final questions = decoded['questions']! as List<Object?>;
    final first = questions.first! as Map<String, Object?>;
    final evidenceSources = first['evidenceSources']! as List<Object?>;
    evidenceSources.add({
      'evidencePath': 'lib/runtime_support.dart',
      'requiredMarkers': ['private supporting evidence marker'],
    });
    fixture.writeAsStringSync(jsonEncode(decoded));

    final report = await runRag2SourceRoleCoverageReplay(
      _options(root, fixture),
    );
    expect(report.validatedEvidenceFileCount, 9);

    support.writeAsStringSync('support removed');
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );
  });

  test('rejects NUL and malformed UTF-8 evidence', () async {
    final root = Directory.systemTemp.createTempSync('rag2-role-binary-');
    addTearDown(() => root.deleteSync(recursive: true));
    final fixture = _writeSyntheticFixture(root);
    final evidence = File('${root.path}/lib/runtime_a.dart');

    evidence.writeAsBytesSync([0]);
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );

    evidence.writeAsBytesSync([0xff]);
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );
  });

  test(
    'fails closed when evidence grows or becomes a symlink after inventory',
    () async {
      final root = Directory.systemTemp.createTempSync('rag2-role-race-');
      final outside = Directory.systemTemp.createTempSync('rag2-role-outside-');
      addTearDown(() => root.deleteSync(recursive: true));
      addTearDown(() => outside.deleteSync(recursive: true));
      final fixture = _writeSyntheticFixture(root);
      final evidence = File('${root.path}/lib/runtime_a.dart');

      await expectLater(
        runRag2SourceRoleCoverageReplay(
          _options(root, fixture),
          beforeEvidenceValidation: () async {
            evidence.writeAsStringSync('x' * (512 * 1024 + 1));
          },
        ),
        throwsFormatException,
      );

      _writeSyntheticFixture(root);
      final outsideFile = File('${outside.path}/runtime_a.dart')
        ..writeAsStringSync('private evidence marker runtime a');
      await expectLater(
        runRag2SourceRoleCoverageReplay(
          _options(root, fixture),
          beforeEvidenceValidation: () async {
            evidence.deleteSync();
            Link(evidence.path).createSync(outsideFile.path);
          },
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'inventory identity changes when non-evidence metadata changes',
    () async {
      final root = Directory.systemTemp.createTempSync('rag2-role-identity-');
      addTearDown(() => root.deleteSync(recursive: true));
      final fixture = _writeSyntheticFixture(root);
      final first = await runRag2SourceRoleCoverageReplay(
        _options(root, fixture),
      );

      File(
        '${root.path}/docs/non_evidence.md',
      ).writeAsStringSync('new metadata');
      final second = await runRag2SourceRoleCoverageReplay(
        _options(root, fixture),
      );

      expect(
        second.inventoryMetadataIdentity,
        isNot(first.inventoryMetadataIdentity),
      );
      expect(second.validatedEvidenceIdentity, first.validatedEvidenceIdentity);
    },
  );

  test('default-limit overflow blocks scope eligibility', () {
    final profile = Rag2SourceProfileCoverage(
      profileId: 'synthetic',
      profileKind: 'comparison_profile',
      scope: const Rag2ScopeAggregate(
        id: 'synthetic',
        candidateFileCount: 513,
        candidateCorpusBytes: 1,
      ),
      questionCount: 1,
      coveredQuestionCount: 1,
      sourceRoleCoverage: const [],
    );

    expect(profile.blockers, ['default_limits_exceeded']);
    expect(profile.toJson()['scopeEligibilityDecision'], 'no_go');
  });

  test('loads the frozen active-project question fixture', () async {
    final fixture = await Rag2SourceRoleCoverageFixture.load(
      File('tool/fixtures/rag2_source_role_coverage_v2/fixture.json'),
    );

    expect(fixture.fixtureId, 'caverno-active-project-source-role-coverage-v2');
    expect(fixture.questions, hasLength(8));
    expect(
      fixture.questions.map((question) => question.expectedSourceRole).toSet(),
      {'runtime_source', 'documentation', 'tests', 'tooling', 'root_sources'},
    );
  });

  test('requires explicit replay inputs and bounded file size', () {
    expect(
      Rag2SourceRoleCoverageOptions.parse([
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        '--fixture',
        '/tmp/fixture.json',
      ]),
      isNull,
    );
    expect(
      Rag2SourceRoleCoverageOptions.parse([
        '--enable-live-replay',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        '--fixture',
        '/tmp/fixture.json',
        '--max-file-bytes',
        '${1024 * 1024 + 1}',
      ]),
      isNull,
    );
    expect(
      Rag2SourceRoleCoverageOptions.parse([
        '--enable-live-replay',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        '--fixture',
        '/tmp/fixture.json',
      ]),
      isNotNull,
    );
  });
}

Rag2SourceRoleCoverageOptions _options(Directory root, File fixture) =>
    Rag2SourceRoleCoverageOptions(
      enabled: true,
      projectId: 'source-role-coverage-test-project',
      projectRoot: root.path,
      fixturePath: fixture.path,
      maxFileBytes: 512 * 1024,
    );

File _writeSyntheticFixture(
  Directory root, {
  bool addSecondRuntimeMarker = false,
}) {
  final sources = <String, String>{
    'lib/runtime_a.dart': 'private evidence marker runtime a',
    'packages/core/lib/runtime_b.dart': 'private evidence marker runtime b',
    'docs/guide_a.md': 'private evidence marker docs a',
    'docs/guide_b.md': 'private evidence marker docs b',
    'test/runtime_a_test.dart': 'private evidence marker tests a',
    'packages/core/test/runtime_b_test.dart': 'private evidence marker tests b',
    'tool/measure.dart': 'private evidence marker tooling',
    'README.md': 'private evidence marker root',
  };
  if (addSecondRuntimeMarker) {
    sources['lib/runtime_a.dart'] =
        '${sources['lib/runtime_a.dart']}\nprivate second marker runtime a';
  }
  for (final entry in sources.entries) {
    final file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  const roles = <String, String>{
    'lib/runtime_a.dart': 'runtime_source',
    'packages/core/lib/runtime_b.dart': 'runtime_source',
    'docs/guide_a.md': 'documentation',
    'docs/guide_b.md': 'documentation',
    'test/runtime_a_test.dart': 'tests',
    'packages/core/test/runtime_b_test.dart': 'tests',
    'tool/measure.dart': 'tooling',
    'README.md': 'root_sources',
  };
  final questions = <Map<String, Object?>>[];
  var index = 0;
  for (final entry in sources.entries) {
    final markers = <String>[
      if (entry.key == 'lib/runtime_a.dart')
        'private evidence marker runtime a'
      else
        entry.value,
    ];
    if (entry.key == 'lib/runtime_a.dart' && addSecondRuntimeMarker) {
      const secondMarker = 'private second marker runtime a';
      markers.add(secondMarker);
    }
    questions.add({
      'id': 'question-${index++}',
      'question': 'private question ${entry.key}',
      'evidenceSources': [
        {'evidencePath': entry.key, 'requiredMarkers': markers},
      ],
      'expectedSourceRole': roles[entry.key],
    });
  }
  final fixture = File('${root.path}/fixture.json');
  fixture.writeAsStringSync(
    jsonEncode({
      'schemaName': rag2SourceRoleCoverageFixtureSchema,
      'schemaVersion': 2,
      'fixtureId': 'synthetic-source-role-coverage-v2',
      'questions': questions,
    }),
  );
  return fixture;
}
