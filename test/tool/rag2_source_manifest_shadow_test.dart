import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_source_discovery_replay.dart';
import '../../tool/rag2_source_manifest_shadow.dart';

void main() {
  test('emits a metadata-only manifest for explicit live shadow', () async {
    final root = await _createShadowRepository();
    addTearDown(() => root.deleteSync(recursive: true));

    final report = await runRag2SourceManifestShadow(options: _options(root));
    final json = jsonEncode(report.toJson());

    expect(report.manifestPassed, isTrue);
    expect(report.result.candidateFileCount, 3);
    expect(report.result.candidates, hasLength(3));
    expect(
      report.result.candidates.map(
        (source) => (
          source.attestation.repoRelativePath,
          source.attestation.worktreeState,
        ),
      ),
      [
        ('docs/clean.md', 'clean'),
        ('docs/untracked.md', 'untracked'),
        ('lib/config.dart', 'modified'),
      ],
    );
    expect(
      report.result.candidates.every((source) => source.chunks.isEmpty),
      isTrue,
    );
    expect(
      report.result.exclusions.map((item) => item.toJson()),
      containsAll([
        {'path': '.git/', 'reason': 'generated_directory'},
        {'path': 'assets/note.txt', 'reason': 'unsupported_extension'},
        {'path': 'build/', 'reason': 'generated_directory'},
        {'path': 'lib/config.g.dart', 'reason': 'generated_file'},
      ]),
    );
    for (final forbidden in [
      root.path,
      '/Users/',
      'source body sentinel',
      'modified source sentinel',
      'untracked source sentinel',
      'chunks',
    ]) {
      expect(json, isNot(contains(forbidden)));
    }
  });

  test('records symlink exclusion without following the link', () async {
    final root = await _createShadowRepository();
    addTearDown(() => root.deleteSync(recursive: true));
    final link = Link('${root.path}/docs/linked.md');
    try {
      link.createSync('${root.path}/docs/clean.md');
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }

    final report = await runRag2SourceManifestShadow(options: _options(root));

    expect(report.manifestPassed, isTrue);
    expect(
      report.result.exclusions.any(
        (item) =>
            item.path == 'docs/linked.md' && item.reason == 'symlink_rejected',
      ),
      isTrue,
    );
  });

  test(
    'fails closed before Git probes when manifest limits are exceeded',
    () async {
      final root = await _createShadowRepository();
      addTearDown(() => root.deleteSync(recursive: true));
      var invoked = false;

      final report = await runRag2SourceManifestShadow(
        options: _options(
          root,
          policy: const Rag2SourceDiscoveryPolicy(
            maxFiles: 1,
            maxFileBytes: 1024,
            maxCorpusBytes: 4096,
          ),
        ),
        processRunner:
            ({
              required arguments,
              required workingDirectory,
              required timeout,
              required maxOutputBytes,
            }) async {
              invoked = true;
              throw StateError(
                'Git must not run after a manifest limit failure.',
              );
            },
      );

      expect(report.manifestPassed, isFalse);
      expect(report.result.violations, ['file_count_exceeded']);
      expect(report.result.candidates, isEmpty);
      expect(invoked, isFalse);
    },
  );

  test(
    'retains typed Git failure reason without exposing command output',
    () async {
      final root = await _createShadowRepository();
      addTearDown(() => root.deleteSync(recursive: true));
      final nested = Directory('${root.path}/docs');

      final report = await runRag2SourceManifestShadow(
        options: _options(nested),
      );
      final json = jsonEncode(report.toJson());

      expect(report.manifestPassed, isFalse);
      expect(report.result.candidates, isEmpty);
      expect(
        report.evidenceFailures.values,
        everyElement('project_not_repository_root'),
      );
      expect(json, contains('project_not_repository_root'));
      expect(json, isNot(contains(root.path)));
    },
  );

  test('requires explicit opt-in and rejects limits above hard caps', () {
    expect(
      Rag2SourceManifestShadowOptions.parse([
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
      ]),
      isNull,
    );
    expect(
      Rag2SourceManifestShadowOptions.parse([
        '--enable-live-shadow',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        '--max-files',
        '${rag2ShadowHardMaxFiles + 1}',
      ]),
      isNull,
    );
    final parsed = Rag2SourceManifestShadowOptions.parse([
      '--enable-live-shadow',
      '--project-id',
      'project',
      '--project-root',
      '/tmp/project',
      '--max-files',
      '12',
    ]);
    expect(parsed, isNotNull);
    expect(parsed?.policy.maxFiles, 12);
  });
}

Rag2SourceManifestShadowOptions _options(
  Directory root, {
  Rag2SourceDiscoveryPolicy policy = const Rag2SourceDiscoveryPolicy(
    maxFiles: 16,
    maxFileBytes: 4096,
    maxCorpusBytes: 16384,
  ),
}) => Rag2SourceManifestShadowOptions(
  enabled: true,
  projectId: 'rag2-shadow-test-project',
  projectRoot: root.path,
  policy: policy,
);

Future<Directory> _createShadowRepository() async {
  final root = Directory.systemTemp.createTempSync('rag2-shadow-repository-');
  Directory('${root.path}/docs').createSync();
  Directory('${root.path}/lib').createSync();
  Directory('${root.path}/assets').createSync();
  Directory('${root.path}/build').createSync();
  File(
    '${root.path}/docs/clean.md',
  ).writeAsStringSync('# Guide\n\nsource body sentinel\n');
  File(
    '${root.path}/lib/config.dart',
  ).writeAsStringSync("const endpoint = 'initial';\n");
  await _git(root, ['init', '-q']);
  await _git(root, ['config', 'user.name', 'RAG2 Shadow']);
  await _git(root, ['config', 'user.email', 'rag2@example.invalid']);
  await _git(root, ['add', '--', 'docs/clean.md', 'lib/config.dart']);
  await _git(root, ['commit', '-q', '-m', 'Initialize shadow fixture']);

  File(
    '${root.path}/lib/config.dart',
  ).writeAsStringSync('// modified source sentinel\n');
  File(
    '${root.path}/docs/untracked.md',
  ).writeAsStringSync('# Draft\n\nuntracked source sentinel\n');
  File('${root.path}/lib/config.g.dart').writeAsStringSync('generated');
  File('${root.path}/assets/note.txt').writeAsStringSync('unsupported');
  File('${root.path}/build/generated.md').writeAsStringSync('generated');
  return root;
}

Future<void> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
    environment: const {'LANG': 'C', 'LC_ALL': 'C'},
    includeParentEnvironment: true,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
