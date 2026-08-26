import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/bounded_text_file_classifier.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_provenance_attestation_replay.dart';

void main() {
  const fixturePath =
      'tool/fixtures/rag2_provenance_attestation_replay/fixture.json';

  test(
    'pins derived revision, trust, and root-move identity evidence',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-attestation-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final report = await runRag2ProvenanceAttestationReplay(
        Rag2ProvenanceReplayOptions(
          fixturePath: fixturePath,
          outDir: directory.path,
        ),
      );

      expect(report.contractPassed, isTrue);
      expect(report.identityPairsStable, isTrue);
      expect(report.results, hasLength(5));
      expect(
        report.results.where((result) => result.decision == 'attested'),
        hasLength(4),
      );
      expect(
        report.results.singleWhere((item) => item.caseId == 'modified-tracked'),
        isA<Rag2SourceAttestation>()
            .having(
              (item) => item.sourceTrust,
              'sourceTrust',
              'workspace_tracked',
            )
            .having((item) => item.worktreeState, 'worktreeState', 'modified')
            .having(
              (item) => item.revisionKind,
              'revisionKind',
              'working_tree_content',
            ),
      );
      expect(
        report.results.singleWhere((item) => item.caseId == 'git-unavailable'),
        isA<Rag2SourceAttestation>()
            .having((item) => item.decision, 'decision', 'rejected')
            .having(
              (item) => item.reason,
              'reason',
              'git_evidence_unavailable',
            ),
      );
    },
  );

  test('writes deterministic reports without absolute root paths', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-attestation-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2ProvenanceAttestationReplay(
      Rag2ProvenanceReplayOptions(
        fixturePath: fixturePath,
        outDir: directory.path,
      ),
    );
    final jsonReport = File(
      '${directory.path}/rag2_provenance_attestation_replay.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${directory.path}/rag2_provenance_attestation_replay.md',
    ).readAsStringSync();

    expect(jsonDecode(jsonReport), report.toJson());
    expect(markdownReport, report.toMarkdown());
    for (final forbidden in [Directory.current.path, '/Users/', 'root_a']) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  });

  test('rejects binary and oversized sources before Git attestation', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-attestation-');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/binary.dat').writeAsBytesSync([0, 1, 2]);
    File('${directory.path}/large.txt').writeAsStringSync('too large');

    final binaryResult = await attestRag2ProjectSource(
      caseId: 'binary',
      project: _project(directory.path),
      repoRelativePath: 'binary.dat',
      gitEvidence: _trackedCleanEvidence,
    );
    final oversizedResult = await attestRag2ProjectSource(
      caseId: 'oversized',
      project: _project(directory.path),
      repoRelativePath: 'large.txt',
      gitEvidence: _trackedCleanEvidence,
      maxFileBytes: 4,
    );

    expect(binaryResult.reason, 'binary_source_not_supported');
    expect(oversizedResult.reason, 'source_too_large');
  });

  test('rejects a symlink that resolves outside the canonical root', () async {
    final sandbox = Directory.systemTemp.createTempSync('rag2-attestation-');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final project = Directory('${sandbox.path}/project')..createSync();
    final sibling = Directory('${sandbox.path}/sibling')..createSync();
    final secret = File('${sibling.path}/secret.md')
      ..writeAsStringSync('secret');
    final link = Link('${project.path}/linked.md');
    try {
      link.createSync(secret.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }

    final result = await attestRag2ProjectSource(
      caseId: 'symlink',
      project: _project(project.path),
      repoRelativePath: 'linked.md',
      gitEvidence: _trackedCleanEvidence,
    );

    expect(result.decision, 'rejected');
    expect(result.reason, 'project_read_outside_root');
  });

  test(
    'bounded classifier tolerates split UTF-8 and rejects malformed bytes',
    () async {
      final directory = Directory.systemTemp.createTempSync('rag2-text-sniff-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final splitRune = File('${directory.path}/split.txt')
        ..writeAsStringSync('a€');
      final malformed = File('${directory.path}/malformed.bin')
        ..writeAsBytesSync([0xff, 0xfe]);

      expect(
        await BoundedTextFileClassifier.looksBinary(splitRune, sniffBytes: 2),
        isFalse,
      );
      expect(await BoundedTextFileClassifier.looksBinary(malformed), isTrue);
    },
  );

  test(
    'fails closed on ambiguous Git evidence and missing project identity',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-attestation-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/source.md').writeAsStringSync('text');

      final ambiguous = await attestRag2ProjectSource(
        caseId: 'ambiguous',
        project: _project(directory.path),
        repoRelativePath: 'source.md',
        gitEvidence: const Rag2GitEvidence(
          available: true,
          lsFilesExitCode: 1,
          statusPorcelain: '',
        ),
      );
      final missingProject = await attestRag2ProjectSource(
        caseId: 'missing-project',
        project: _project(directory.path, id: ''),
        repoRelativePath: 'source.md',
        gitEvidence: _trackedCleanEvidence,
      );
      final mismatchedStatus = await attestRag2ProjectSource(
        caseId: 'mismatched-status',
        project: _project(directory.path),
        repoRelativePath: 'source.md',
        gitEvidence: const Rag2GitEvidence(
          available: true,
          lsFilesExitCode: 0,
          statusPorcelain: ' M other.md',
          headBlobRevision: '1111111111111111111111111111111111111111',
        ),
      );
      final inconsistentTypedState = await attestRag2ProjectSource(
        caseId: 'inconsistent-typed-state',
        project: _project(directory.path),
        repoRelativePath: 'source.md',
        gitEvidence: const Rag2GitEvidence(
          available: true,
          lsFilesExitCode: 1,
          statusPorcelain: '',
          headBlobRevision: '1111111111111111111111111111111111111111',
          collectedState: Rag2CollectedGitState.cleanTracked,
        ),
      );

      expect(ambiguous.reason, 'git_state_ambiguous');
      expect(missingProject.reason, 'project_identity_unavailable');
      expect(mismatchedStatus.reason, 'git_state_ambiguous');
      expect(inconsistentTypedState.reason, 'git_state_ambiguous');
    },
  );
}

const _trackedCleanEvidence = Rag2GitEvidence(
  available: true,
  lsFilesExitCode: 0,
  statusPorcelain: '',
  headBlobRevision: '1111111111111111111111111111111111111111',
);

CodingProject _project(String rootPath, {String id = 'project'}) =>
    CodingProject(
      id: id,
      name: 'Fixture project',
      rootPath: rootPath,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
