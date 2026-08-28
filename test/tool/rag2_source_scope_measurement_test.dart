import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_source_scope_measurement.dart';

void main() {
  test('measures top-level scopes and source roles without Git', () async {
    final root = Directory.systemTemp.createTempSync('rag2-scope-measurement-');
    addTearDown(() => root.deleteSync(recursive: true));
    _writeFixture(root);

    final report = await runRag2SourceScopeMeasurement(_options(root));
    final json = jsonEncode(report.toJson());
    final roles = {for (final role in report.sourceRoles) role.id: role};
    final scopes = {for (final scope in report.topLevelScopes) scope.id: scope};
    final profiles = {
      for (final profile in report.comparisonProfiles) profile.id: profile,
    };

    expect(report.total.candidateFileCount, 11);
    expect(roles['runtime_source']?.candidateFileCount, 2);
    expect(roles['tests']?.candidateFileCount, 3);
    expect(roles['documentation']?.candidateFileCount, 1);
    expect(roles['tooling']?.candidateFileCount, 2);
    expect(roles['instruction_bearing']?.candidateFileCount, 1);
    expect(roles['root_sources']?.candidateFileCount, 1);
    expect(roles['other']?.candidateFileCount, 1);
    expect(scopes['packages']?.candidateFileCount, 2);
    expect(scopes['root']?.candidateFileCount, 2);
    expect(profiles['runtime_only']?.candidateFileCount, 2);
    expect(profiles['runtime_and_top_level_docs']?.candidateFileCount, 3);
    expect(profiles['runtime_tests_and_top_level_docs']?.candidateFileCount, 6);
    expect(report.exclusionCounts, {
      'generated_directory': 2,
      'generated_file': 1,
      'unsupported_extension': 1,
    });
    for (final forbidden in [
      root.path,
      'scope measurement source sentinel',
      'main.dart',
      'guide.md',
      'AGENTS.md',
    ]) {
      expect(json, isNot(contains(forbidden)));
    }
  });

  test('compares default and hard bounds without selecting a scope', () async {
    final root = Directory.systemTemp.createTempSync('rag2-scope-limits-');
    addTearDown(() => root.deleteSync(recursive: true));
    final testDirectory = Directory('${root.path}/test')..createSync();
    for (var index = 0; index < 513; index++) {
      File('${testDirectory.path}/case_$index.dart').writeAsStringSync('');
    }

    final report = await runRag2SourceScopeMeasurement(_options(root));
    final json = report.toJson();

    expect(report.total.candidateFileCount, 513);
    expect(report.total.withinDefaultLimits, isFalse);
    expect(report.total.withinHardLimits, isTrue);
    expect(report.total.toJson()['estimatedCurrentCollectorProcesses'], {
      'minimumIncludingPreflight': 1027,
      'maximumIncludingPreflight': 1540,
    });
    expect(json['scopeDecision'], 'not_selected');
    expect(json['productionDecision'], 'no_go');
  });

  test('requires explicit opt-in and bounded file size', () {
    expect(
      Rag2SourceScopeMeasurementOptions.parse([
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
      ]),
      isNull,
    );
    expect(
      Rag2SourceScopeMeasurementOptions.parse([
        '--enable-live-measurement',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        '--max-file-bytes',
        '${1024 * 1024 + 1}',
      ]),
      isNull,
    );
    expect(
      Rag2SourceScopeMeasurementOptions.parse([
        '--enable-live-measurement',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
      ]),
      isNotNull,
    );
  });
}

Rag2SourceScopeMeasurementOptions _options(Directory root) =>
    Rag2SourceScopeMeasurementOptions(
      enabled: true,
      projectId: 'scope-measurement-test-project',
      projectRoot: root.path,
      maxFileBytes: 512 * 1024,
    );

void _writeFixture(Directory root) {
  final files = <String, String>{
    'lib/main.dart': "const marker = 'scope measurement source sentinel';\n",
    'packages/core/lib/core.dart': 'class Core {}\n',
    'packages/core/test/core_test.dart': 'void main() {}\n',
    'test/main_test.dart': 'void main() {}\n',
    'integration_test/app_test.dart': 'void main() {}\n',
    'docs/guide.md': '# Guide\n',
    'tool/task.dart': 'void main() {}\n',
    'services/README.md': '# Service\n',
    'AGENTS.md': '# Instructions\n',
    'README.md': '# Project\n',
    'assets/skills/helper.md': '# Helper\n',
    'lib/config.g.dart': 'generated\n',
    'assets/note.txt': 'unsupported\n',
    'build/generated.md': 'generated directory\n',
    '.private/secret.md': 'hidden directory\n',
  };
  for (final entry in files.entries) {
    final file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
}
