import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_batch_git_inventory_replay.dart';
import '../../tool/rag2_git_evidence_collector.dart';

void main() {
  test(
    'matches per-path states and clean revisions in three commands',
    () async {
      final root = await _createParityRepository();
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/docs/modified.md').writeAsStringSync('# Modified\n');
      const untrackedPath = 'docs/space ü.md';
      File('${root.path}/$untrackedPath').writeAsStringSync('# Untracked\n');
      const stagedPath = 'docs/staged.md';
      File('${root.path}/$stagedPath').writeAsStringSync('# Staged\n');
      await _git(root, ['add', '--', stagedPath]);
      const renamedPath = 'lib/renamed config ü.dart';
      await _git(root, ['mv', 'lib/rename_me.dart', renamedPath]);
      const paths = [
        'docs/clean.md',
        'docs/modified.md',
        untrackedPath,
        stagedPath,
        renamedPath,
      ];

      final batch = await Rag2BatchGitInventoryCollector(
        project: _project(root),
      ).collect(paths);
      final perPath = Rag2GitEvidenceCollector(project: _project(root));

      expect(batch.decision, 'collected');
      expect(batch.commandCount, 3);
      for (final path in paths) {
        final expected = await perPath.collect(path);
        final actual = batch.evidenceByPath[path];
        expect(expected.decision, 'collected', reason: path);
        expect(actual?.collectedState, expected.state, reason: path);
        expect(
          actual?.headBlobRevision,
          expected.evidence?.headBlobRevision,
          reason: path,
        );
        expect(
          actual?.lsFilesExitCode,
          expected.evidence?.lsFilesExitCode,
          reason: path,
        );
      }
      expect(batch.toJson()['stateCounts'], {
        'cleanTracked': 1,
        'modifiedTracked': 3,
        'untracked': 1,
      });
    },
  );

  test(
    'uses fixed repository-wide argv and emits aggregate metadata',
    () async {
      final root = Directory.systemTemp.createTempSync('rag2-batch-runner-');
      addTearDown(() => root.deleteSync(recursive: true));
      final calls = <List<String>>[];
      final collector = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner:
            ({
              required arguments,
              required workingDirectory,
              required timeout,
              required maxOutputBytes,
            }) async {
              calls.add(List<String>.from(arguments));
              if (arguments.contains('--show-toplevel')) {
                return _result(stdout: '${root.path}\n');
              }
              if (arguments.contains('status')) {
                return _result(
                  stdout: ' M docs/modified.md\u0000?? docs/untracked.md\u0000',
                );
              }
              if (arguments.contains('ls-files')) {
                return _result(
                  stdout:
                      '100644 ${'a' * 40} 0\tdocs/clean.md\u0000'
                      '100644 ${'b' * 40} 0\tdocs/modified.md\u0000',
                );
              }
              throw StateError('Unexpected Git command: $arguments');
            },
      );

      final collection = await collector.collect(const [
        'docs/untracked.md',
        'docs/clean.md',
        'docs/modified.md',
      ]);
      final json = jsonEncode(collection.toJson());

      expect(collection.decision, 'collected');
      expect(calls, [
        ['--literal-pathspecs', 'rev-parse', '--show-toplevel'],
        [
          '--literal-pathspecs',
          'status',
          '--porcelain=v1',
          '-z',
          '--untracked-files=all',
        ],
        ['--literal-pathspecs', 'ls-files', '--stage', '-z'],
      ]);
      expect(collection.toJson(), containsPair('commandCount', 3));
      expect(collection.toJson(), containsPair('requestedPathCount', 3));
      expect(
        collection.toJson(),
        containsPair('manifestIntegrationDecision', 'not_evaluated'),
      );
      expect(collection.toJson(), containsPair('productionDecision', 'no_go'));
      for (final forbidden in [
        root.path,
        'docs/clean.md',
        'docs/modified.md',
        'docs/untracked.md',
        'a' * 40,
        'b' * 40,
      ]) {
        expect(json, isNot(contains(forbidden)));
      }
    },
  );

  test('fails closed when the project is not the repository root', () async {
    final root = await _createParityRepository();
    addTearDown(() => root.deleteSync(recursive: true));
    final nested = Directory('${root.path}/docs');

    final collection = await Rag2BatchGitInventoryCollector(
      project: _project(nested),
    ).collect(const ['clean.md']);

    expect(collection.decision, 'rejected');
    expect(collection.reason, 'project_not_repository_root');
    expect(collection.commandCount, 1);
    expect(collection.evidenceByPath, isEmpty);
  });

  test(
    'fails closed on timeout, overflow, and malformed inventories',
    () async {
      final root = Directory.systemTemp.createTempSync('rag2-batch-failures-');
      addTearDown(() => root.deleteSync(recursive: true));

      final timeout = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner: _runner(root, preflight: _result(timedOut: true)),
      );
      expect(
        (await timeout.collect(const ['docs/file.md'])).reason,
        'batch_git_repository_timeout',
      );

      final overflow = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner: _runner(
          root,
          status: _result(outputLimitExceeded: true),
        ),
      );
      final overflowResult = await overflow.collect(const ['docs/file.md']);
      expect(overflowResult.reason, 'batch_git_status_output_exceeded');
      expect(overflowResult.commandCount, 2);

      final malformedStatus = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner: _runner(root, status: _result(stdout: 'bad\u0000')),
      );
      expect(
        (await malformedStatus.collect(const ['docs/file.md'])).reason,
        'batch_git_status_ambiguous',
      );

      final malformedIndex = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner: _runner(root, index: _result(stdout: 'bad\u0000')),
      );
      expect(
        (await malformedIndex.collect(const ['docs/file.md'])).reason,
        'batch_git_index_ambiguous',
      );

      final conflictedIndex = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner: _runner(
          root,
          status: _result(stdout: 'UU docs/file.md\u0000'),
          index: _result(
            stdout:
                '100644 ${'a' * 40} 1\tdocs/file.md\u0000'
                '100644 ${'b' * 40} 2\tdocs/file.md\u0000',
          ),
        ),
      );
      expect(
        (await conflictedIndex.collect(const ['docs/file.md'])).reason,
        'batch_git_state_ambiguous',
      );

      final missing = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner: _runner(root),
      );
      final missingResult = await missing.collect(const ['docs/file.md']);
      expect(missingResult.reason, 'batch_git_state_ambiguous');
      expect(missingResult.commandCount, 3);
    },
  );

  test(
    'rejects invalid, duplicate, and oversized candidate sets before Git',
    () async {
      final root = Directory.systemTemp.createTempSync('rag2-batch-input-');
      addTearDown(() => root.deleteSync(recursive: true));
      var invoked = false;
      final collector = Rag2BatchGitInventoryCollector(
        project: _project(root),
        processRunner:
            ({
              required arguments,
              required workingDirectory,
              required timeout,
              required maxOutputBytes,
            }) async {
              invoked = true;
              return _result();
            },
      );

      expect(
        (await collector.collect(const ['docs/bad\nname.md'])).reason,
        'repo_relative_path_invalid',
      );
      expect(
        (await collector.collect(const ['docs/a.md', 'docs/a.md'])).reason,
        'candidate_paths_ambiguous',
      );
      final oversized = await collector.collect(
        List.generate(2049, (index) => 'docs/file_$index.md'),
      );
      expect(oversized.reason, 'candidate_file_count_exceeded');
      expect(invoked, isFalse);
    },
  );
}

CodingProject _project(Directory root) => CodingProject(
  id: 'rag2-batch-test-project',
  name: 'RAG2 batch test project',
  rootPath: root.path,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
);

Rag2GitProcessRunner _runner(
  Directory root, {
  Rag2GitCommandResult? preflight,
  Rag2GitCommandResult? status,
  Rag2GitCommandResult? index,
}) =>
    ({
      required arguments,
      required workingDirectory,
      required timeout,
      required maxOutputBytes,
    }) async {
      if (arguments.contains('--show-toplevel')) {
        return preflight ?? _result(stdout: '${root.path}\n');
      }
      if (arguments.contains('status')) return status ?? _result();
      if (arguments.contains('ls-files')) return index ?? _result();
      throw StateError('Unexpected Git command: $arguments');
    };

Rag2GitCommandResult _result({
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
  bool timedOut = false,
  bool outputLimitExceeded = false,
}) => Rag2GitCommandResult(
  started: true,
  exitCode: exitCode,
  stdoutBytes: utf8.encode(stdout),
  stderrBytes: utf8.encode(stderr),
  timedOut: timedOut,
  outputLimitExceeded: outputLimitExceeded,
);

Future<Directory> _createParityRepository() async {
  final root = Directory.systemTemp.createTempSync('rag2-batch-repository-');
  Directory('${root.path}/docs').createSync();
  Directory('${root.path}/lib').createSync();
  File('${root.path}/docs/clean.md').writeAsStringSync('# Clean\n');
  File('${root.path}/docs/modified.md').writeAsStringSync('# Initial\n');
  File(
    '${root.path}/lib/rename_me.dart',
  ).writeAsStringSync('class RenameMe {}\n');
  await _git(root, ['init', '-q']);
  await _git(root, ['config', 'user.name', 'RAG2 Batch Fixture']);
  await _git(root, ['config', 'user.email', 'rag2@example.invalid']);
  await _git(root, ['add', '--', '.']);
  await _git(root, ['commit', '-q', '-m', 'Initialize batch fixture']);
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
