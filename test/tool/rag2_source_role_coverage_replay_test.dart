import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_source_role_coverage_replay.dart';

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

    first['evidenceMarker'] = 'missing marker';
    fixture.writeAsStringSync(jsonEncode(decoded));
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );

    first['evidenceMarker'] = 'private evidence marker runtime a';
    first['expectedSourceRole'] = 'documentation';
    fixture.writeAsStringSync(jsonEncode(decoded));
    await expectLater(
      runRag2SourceRoleCoverageReplay(_options(root, fixture)),
      throwsFormatException,
    );
  });

  test('rejects unsafe paths and duplicate question IDs', () async {
    final root = Directory.systemTemp.createTempSync('rag2-role-invalid-');
    addTearDown(() => root.deleteSync(recursive: true));
    final fixture = _writeSyntheticFixture(root);
    final decoded =
        jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;
    final questions = decoded['questions']! as List<Object?>;
    final first = questions.first! as Map<String, Object?>;

    first['evidencePath'] = '../escape.md';
    fixture.writeAsStringSync(jsonEncode(decoded));
    await expectLater(
      Rag2SourceRoleCoverageFixture.load(fixture),
      throwsFormatException,
    );

    first['evidencePath'] = 'lib/runtime_a.dart';
    final second = questions[1]! as Map<String, Object?>;
    second['id'] = first['id'];
    fixture.writeAsStringSync(jsonEncode(decoded));
    await expectLater(
      Rag2SourceRoleCoverageFixture.load(fixture),
      throwsFormatException,
    );
  });

  test('loads the frozen active-project question fixture', () async {
    final fixture = await Rag2SourceRoleCoverageFixture.load(
      File('tool/fixtures/rag2_source_role_coverage/fixture.json'),
    );

    expect(fixture.fixtureId, 'caverno-active-project-source-role-coverage-v1');
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

File _writeSyntheticFixture(Directory root) {
  const sources = <String, String>{
    'lib/runtime_a.dart': 'private evidence marker runtime a',
    'packages/core/lib/runtime_b.dart': 'private evidence marker runtime b',
    'docs/guide_a.md': 'private evidence marker docs a',
    'docs/guide_b.md': 'private evidence marker docs b',
    'test/runtime_a_test.dart': 'private evidence marker tests a',
    'packages/core/test/runtime_b_test.dart': 'private evidence marker tests b',
    'tool/measure.dart': 'private evidence marker tooling',
    'README.md': 'private evidence marker root',
  };
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
    questions.add({
      'id': 'question-${index++}',
      'question': 'private question ${entry.key}',
      'evidencePath': entry.key,
      'evidenceMarker': entry.value,
      'expectedSourceRole': roles[entry.key],
    });
  }
  final fixture = File('${root.path}/fixture.json');
  fixture.writeAsStringSync(
    jsonEncode({
      'schemaName': rag2SourceRoleCoverageFixtureSchema,
      'schemaVersion': 1,
      'fixtureId': 'synthetic-source-role-coverage-v1',
      'questions': questions,
    }),
  );
  return fixture;
}
