import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_git_evidence_collector.dart';
import '../../tool/rag2_provenance_attestation_replay.dart';

void main() {
  test('collects clean, modified, untracked, and renamed Git states', () async {
    final root = await _createRepository();
    addTearDown(() => root.deleteSync(recursive: true));
    final collector = Rag2GitEvidenceCollector(project: _project(root));

    final clean = await collector.collect('docs/guide.md');
    expect(clean.decision, 'collected');
    expect(clean.state, Rag2CollectedGitState.cleanTracked);
    expect(
      clean.evidence?.headBlobRevision,
      matches(RegExp(r'^[0-9a-f]{40}([0-9a-f]{24})?$')),
    );
    final cleanAttestation = await attestRag2ProjectSource(
      caseId: 'clean',
      project: _project(root),
      repoRelativePath: 'docs/guide.md',
      gitEvidence: clean.evidence!,
    );
    expect(cleanAttestation.decision, 'attested');
    expect(cleanAttestation.worktreeState, 'clean');

    File('${root.path}/docs/guide.md').writeAsStringSync('# Changed\n');
    final modified = await collector.collect('docs/guide.md');
    expect(modified.decision, 'collected');
    expect(modified.state, Rag2CollectedGitState.modifiedTracked);

    final untrackedPath = 'docs/space ü.md';
    File('${root.path}/$untrackedPath').writeAsStringSync('# Untracked\n');
    final untracked = await collector.collect(untrackedPath);
    expect(untracked.decision, 'collected');
    expect(untracked.state, Rag2CollectedGitState.untracked);

    await _git(root, ['add', '--', untrackedPath]);
    final staged = await collector.collect(untrackedPath);
    expect(staged.decision, 'collected');
    expect(staged.state, Rag2CollectedGitState.modifiedTracked);

    await _git(root, ['mv', 'lib/config.dart', 'lib/renamed config.dart']);
    final renamed = await collector.collect('lib/renamed config.dart');
    expect(renamed.decision, 'collected');
    expect(renamed.state, Rag2CollectedGitState.modifiedTracked);
  });

  test('uses literal bounded argv and caches repository preflight', () async {
    final root = Directory.systemTemp.createTempSync('rag2-git-runner-');
    addTearDown(() => root.deleteSync(recursive: true));
    final calls = <List<String>>[];
    final collector = Rag2GitEvidenceCollector(
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
              return _result(stdout: ' M docs/file.md\u0000');
            }
            if (arguments.contains('ls-files')) {
              return _result(stdout: 'docs/file.md\u0000');
            }
            throw StateError('Unexpected Git command: $arguments');
          },
    );

    final first = await collector.collect('docs/file.md');
    final second = await collector.collect('docs/file.md');

    expect(first.state, Rag2CollectedGitState.modifiedTracked);
    expect(second.state, Rag2CollectedGitState.modifiedTracked);
    expect(
      calls.where((call) => call.contains('--show-toplevel')),
      hasLength(1),
    );
    expect(calls[1], [
      '--literal-pathspecs',
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
      '--',
      'docs/file.md',
    ]);
    expect(calls[2], [
      '--literal-pathspecs',
      'ls-files',
      '-z',
      '--error-unmatch',
      '--',
      'docs/file.md',
    ]);
  });

  test('fails closed when the project is not the repository root', () async {
    final root = await _createRepository();
    addTearDown(() => root.deleteSync(recursive: true));
    final nested = Directory('${root.path}/docs');
    final collector = Rag2GitEvidenceCollector(project: _project(nested));

    final result = await collector.collect('guide.md');

    expect(result.decision, 'rejected');
    expect(result.reason, 'project_not_repository_root');
    expect(result.evidence, isNull);
  });

  test('fails closed on timeout, overflow, and ambiguous status', () async {
    final root = Directory.systemTemp.createTempSync('rag2-git-failures-');
    addTearDown(() => root.deleteSync(recursive: true));

    final timeout = Rag2GitEvidenceCollector(
      project: _project(root),
      processRunner:
          ({
            required arguments,
            required workingDirectory,
            required timeout,
            required maxOutputBytes,
          }) async => _result(timedOut: true),
    );
    expect(
      (await timeout.collect('docs/file.md')).reason,
      'git_repository_timeout',
    );

    final overflow = Rag2GitEvidenceCollector(
      project: _project(root),
      processRunner:
          ({
            required arguments,
            required workingDirectory,
            required timeout,
            required maxOutputBytes,
          }) async => _result(outputLimitExceeded: true),
    );
    expect(
      (await overflow.collect('docs/file.md')).reason,
      'git_repository_output_exceeded',
    );

    final ambiguous = Rag2GitEvidenceCollector(
      project: _project(root),
      processRunner:
          ({
            required arguments,
            required workingDirectory,
            required timeout,
            required maxOutputBytes,
          }) async {
            if (arguments.contains('--show-toplevel')) {
              return _result(stdout: '${root.path}\n');
            }
            return _result(
              stdout: ' M docs/file.md\u0000 M docs/other.md\u0000',
            );
          },
    );
    expect(
      (await ambiguous.collect('docs/file.md')).reason,
      'git_status_ambiguous',
    );

    final failedStatus = Rag2GitEvidenceCollector(
      project: _project(root),
      processRunner:
          ({
            required arguments,
            required workingDirectory,
            required timeout,
            required maxOutputBytes,
          }) async {
            if (arguments.contains('--show-toplevel')) {
              return _result(stdout: '${root.path}\n');
            }
            return _result(exitCode: 128, stderr: 'fatal');
          },
    );
    expect(
      (await failedStatus.collect('docs/file.md')).reason,
      'git_status_failed',
    );
  });

  test('bounds output in the real process runner', () async {
    final root = await _createRepository();
    addTearDown(() => root.deleteSync(recursive: true));
    final collector = Rag2GitEvidenceCollector(
      project: _project(root),
      maxCommandOutputBytes: 4,
    );

    final result = await collector.collect('docs/guide.md');

    expect(result.decision, 'rejected');
    expect(result.reason, 'git_repository_output_exceeded');
  });

  test('rejects control characters before invoking Git', () async {
    final root = Directory.systemTemp.createTempSync('rag2-git-path-');
    addTearDown(() => root.deleteSync(recursive: true));
    var invoked = false;
    final collector = Rag2GitEvidenceCollector(
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

    final result = await collector.collect('docs/bad\nname.md');

    expect(result.reason, 'repo_relative_path_invalid');
    expect(invoked, isFalse);
  });
}

CodingProject _project(Directory root) => CodingProject(
  id: 'rag2-test-project',
  name: 'RAG2 test project',
  rootPath: root.path,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
);

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

Future<Directory> _createRepository() async {
  final root = Directory.systemTemp.createTempSync('rag2-git-repository-');
  Directory('${root.path}/docs').createSync();
  Directory('${root.path}/lib').createSync();
  File('${root.path}/docs/guide.md').writeAsStringSync('# Guide\n');
  File(
    '${root.path}/lib/config.dart',
  ).writeAsStringSync("const endpoint = 'http://localhost';\n");
  await _git(root, ['init', '-q']);
  await _git(root, ['config', 'user.name', 'RAG2 Fixture']);
  await _git(root, ['config', 'user.email', 'rag2@example.invalid']);
  await _git(root, ['add', '--', 'docs/guide.md', 'lib/config.dart']);
  await _git(root, ['commit', '-q', '-m', 'Initialize fixture']);
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
