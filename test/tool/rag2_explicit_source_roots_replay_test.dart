import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_explicit_source_roots_replay.dart';
import '../../tool/rag2_git_evidence_collector.dart';

void main() {
  test('admits every eligible source under explicit complete roots', () async {
    final root = await _createRepository();
    addTearDown(() => root.deleteSync(recursive: true));
    var commandCount = 0;

    final replay = await runRag2ExplicitSourceRootsReplay(
      options: _options(root, const ['docs', 'lib/core']),
      processRunner:
          ({
            required arguments,
            required workingDirectory,
            required timeout,
            required maxOutputBytes,
          }) async {
            commandCount++;
            return runRag2GitCommand(
              arguments: arguments,
              workingDirectory: workingDirectory,
              timeout: timeout,
              maxOutputBytes: maxOutputBytes,
            );
          },
    );
    final report = replay.report;
    final json = jsonEncode(report.toJson());

    expect(report.contractPassed, isTrue);
    expect(report.sourceRootCount, 2);
    expect(report.inventoryCandidateFileCount, 7);
    expect(report.eligibleCandidateFileCount, 4);
    expect(report.admittedSourceCount, 4);
    expect(report.instructionBearingExcludedCount, 1);
    expect(report.policyExclusionCounts, {
      'generated_file': 1,
      'unsupported_extension': 1,
    });
    expect(report.gitCommandCount, 3);
    expect(commandCount, 3);
    expect(report.blockers, isEmpty);
    expect(
      replay.admittedSourcePaths,
      unorderedEquals(const [
        'docs/guide.md',
        'docs/nested/details.md',
        'lib/core/config.dart',
        'lib/core/runtime.dart',
      ]),
    );
    expect(
      replay.inventoryCandidatePaths,
      containsAll(replay.admittedSourcePaths),
    );
    expect(json, isNot(contains('inventoryCandidatePaths')));
    expect(json, isNot(contains('admittedSourcePaths')));
    expect(report.toJson()['scopeDecision'], 'not_selected');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      (report.toJson()['policy']! as Map<String, Object?>)['maxFiles'],
      512,
    );
    for (final forbidden in [
      root.path,
      'docs/guide.md',
      'lib/core/config.dart',
      'source roots sentinel',
      'AGENTS.md',
    ]) {
      expect(json, isNot(contains(forbidden)));
    }
  });

  test('accepts an explicit repository-root declaration', () async {
    final root = await _createRepository();
    addTearDown(() => root.deleteSync(recursive: true));

    final replay = await runRag2ExplicitSourceRootsReplay(
      options: _options(root, const ['.']),
    );
    final report = replay.report;

    expect(report.contractPassed, isTrue);
    expect(report.eligibleCandidateFileCount, 6);
    expect(report.admittedSourceCount, 6);
    expect(report.instructionBearingExcludedCount, 1);
  });

  test(
    'keeps declaration and selection identities independent of root order',
    () async {
      final root = await _createRepository();
      addTearDown(() => root.deleteSync(recursive: true));

      final forward = await runRag2ExplicitSourceRootsReplay(
        options: _options(root, const ['docs', 'lib/core']),
      );
      final reversed = await runRag2ExplicitSourceRootsReplay(
        options: _options(root, const ['lib/core', 'docs']),
      );

      expect(forward.report.toJson(), reversed.report.toJson());
    },
  );

  test(
    'rejects malformed, duplicate, overlapping, and unavailable roots',
    () async {
      final root = await _createRepository();
      addTearDown(() => root.deleteSync(recursive: true));
      var invoked = false;
      Future<Rag2GitCommandResult> forbiddenRunner({
        required List<String> arguments,
        required String workingDirectory,
        required Duration timeout,
        required int maxOutputBytes,
      }) async {
        invoked = true;
        return Rag2GitCommandResult.startFailed();
      }

      final cases = <(List<String>, String)>[
        (['../docs'], 'source_root_invalid'),
        ([root.path], 'source_root_invalid'),
        (['docs', 'docs'], 'source_root_duplicate'),
        (['docs', 'docs/nested'], 'source_root_overlap'),
        (['missing'], 'source_root_unavailable'),
        (['README.md'], 'source_root_not_directory'),
      ];
      for (final entry in cases) {
        final replay = await runRag2ExplicitSourceRootsReplay(
          options: _options(root, entry.$1),
          processRunner: forbiddenRunner,
        );
        final report = replay.report;
        expect(report.contractPassed, isFalse, reason: entry.$1.join(','));
        expect(report.admittedSourceCount, 0, reason: entry.$1.join(','));
        expect(replay.admittedSourcePaths, isEmpty, reason: entry.$1.join(','));
        expect(report.gitCommandCount, 0, reason: entry.$1.join(','));
        expect(report.blockers, [entry.$2], reason: entry.$1.join(','));
      }
      expect(invoked, isFalse);
    },
  );

  test(
    'rejects a source root containing a symlink component before Git',
    () async {
      final root = await _createRepository();
      addTearDown(() => root.deleteSync(recursive: true));
      final link = Link('${root.path}/linked_docs');
      try {
        link.createSync('${root.path}/docs');
      } on FileSystemException {
        markTestSkipped('Symbolic links are unavailable on this platform.');
        return;
      }
      var invoked = false;

      final replay = await runRag2ExplicitSourceRootsReplay(
        options: _options(root, const ['linked_docs/nested']),
        processRunner:
            ({
              required arguments,
              required workingDirectory,
              required timeout,
              required maxOutputBytes,
            }) async {
              invoked = true;
              return Rag2GitCommandResult.startFailed();
            },
      );
      final report = replay.report;

      expect(report.blockers, ['source_root_symlink_rejected']);
      expect(report.admittedSourceCount, 0);
      expect(report.gitCommandCount, 0);
      expect(invoked, isFalse);
    },
  );

  test('enforces the unchanged default file ceiling before Git', () async {
    final root = Directory.systemTemp.createTempSync('rag2-explicit-limit-');
    addTearDown(() => root.deleteSync(recursive: true));
    final docs = Directory('${root.path}/docs')..createSync();
    for (var index = 0; index < 513; index++) {
      File('${docs.path}/case_$index.md').writeAsStringSync('');
    }
    var invoked = false;

    final replay = await runRag2ExplicitSourceRootsReplay(
      options: _options(root, const ['docs']),
      processRunner:
          ({
            required arguments,
            required workingDirectory,
            required timeout,
            required maxOutputBytes,
          }) async {
            invoked = true;
            return Rag2GitCommandResult.startFailed();
          },
    );
    final report = replay.report;

    expect(report.eligibleCandidateFileCount, 513);
    expect(report.blockers, ['file_count_exceeded']);
    expect(report.admittedSourceCount, 0);
    expect(report.gitCommandCount, 0);
    expect(invoked, isFalse);
  });

  test(
    'rejects the whole declaration when Git evidence is unavailable',
    () async {
      final root = await _createRepository();
      addTearDown(() => root.deleteSync(recursive: true));

      final replay = await runRag2ExplicitSourceRootsReplay(
        options: _options(root, const ['docs']),
        processRunner:
            ({
              required arguments,
              required workingDirectory,
              required timeout,
              required maxOutputBytes,
            }) async => Rag2GitCommandResult.startFailed(),
      );
      final report = replay.report;

      expect(report.blockers, ['batch_git_repository_unavailable']);
      expect(report.eligibleCandidateFileCount, 2);
      expect(report.admittedSourceCount, 0);
      expect(replay.admittedSourcePaths, isEmpty);
      expect(report.gitCommandCount, 1);
    },
  );

  test('rejects the whole declaration when one attestation fails', () async {
    final root = await _createRepository();
    addTearDown(() => root.deleteSync(recursive: true));

    final replay = await runRag2ExplicitSourceRootsReplay(
      options: _options(root, const ['docs']),
      processRunner:
          ({
            required arguments,
            required workingDirectory,
            required timeout,
            required maxOutputBytes,
          }) async {
            final result = await runRag2GitCommand(
              arguments: arguments,
              workingDirectory: workingDirectory,
              timeout: timeout,
              maxOutputBytes: maxOutputBytes,
            );
            if (arguments.contains('ls-files')) {
              File('${root.path}/docs/guide.md').deleteSync();
            }
            return result;
          },
    );
    final report = replay.report;

    expect(report.blockers, ['source_attestation_incomplete']);
    expect(report.eligibleCandidateFileCount, 2);
    expect(report.admittedSourceCount, 0);
    expect(replay.admittedSourcePaths, isEmpty);
    expect(report.gitCommandCount, 3);
  });

  test('requires opt-in and supports repeated explicit roots', () {
    expect(
      Rag2ExplicitSourceRootsOptions.parse([
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        '--source-root',
        'docs',
      ]),
      isNull,
    );
    final parsed = Rag2ExplicitSourceRootsOptions.parse([
      '--enable-replay',
      '--project-id',
      'project',
      '--project-root',
      '/tmp/project',
      '--source-root',
      'docs',
      '--source-root',
      'lib/core',
    ]);
    expect(parsed?.sourceRoots, ['docs', 'lib/core']);
    expect(
      Rag2ExplicitSourceRootsOptions.parse([
        '--enable-replay',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        for (var index = 0; index < 17; index++) ...[
          '--source-root',
          'root_$index',
        ],
      ]),
      isNull,
    );
  });
}

Rag2ExplicitSourceRootsOptions _options(
  Directory root,
  List<String> sourceRoots,
) => Rag2ExplicitSourceRootsOptions(
  enabled: true,
  projectId: 'rag2-explicit-roots-test-project',
  projectRoot: root.path,
  sourceRoots: sourceRoots,
);

Future<Directory> _createRepository() async {
  final root = Directory.systemTemp.createTempSync('rag2-explicit-roots-');
  final files = <String, String>{
    'docs/guide.md': '# Guide\n\nsource roots sentinel\n',
    'docs/nested/details.md': '# Details\n',
    'docs/AGENTS.md': '# Instructions\n',
    'docs/generated.g.dart': 'const generated = true;\n',
    'docs/note.txt': 'unsupported\n',
    'lib/core/config.dart': 'const endpoint = 1;\n',
    'lib/core/runtime.dart': 'class Runtime {}\n',
    'lib/feature/outside.dart': 'class Outside {}\n',
    'README.md': '# Project\n',
  };
  for (final entry in files.entries) {
    final file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  await _git(root, ['init', '-q']);
  await _git(root, ['config', 'user.name', 'RAG2 Explicit Roots']);
  await _git(root, ['config', 'user.email', 'rag2@example.invalid']);
  await _git(root, ['add', '--', '.']);
  await _git(root, ['commit', '-q', '-m', 'Initialize explicit roots fixture']);
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
