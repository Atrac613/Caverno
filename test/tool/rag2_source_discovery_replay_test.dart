import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_provenance_attestation_replay.dart';
import '../../tool/rag2_source_discovery_replay.dart';

void main() {
  const fixturePath = 'tool/fixtures/rag2_source_discovery_replay/fixture.json';

  test('pins bounded discovery, exclusions, and semantic chunks', () async {
    final output = Directory.systemTemp.createTempSync('rag2-discovery-');
    addTearDown(() => output.deleteSync(recursive: true));

    final report = await runRag2SourceDiscoveryReplay(
      Rag2SourceDiscoveryOptions(fixturePath: fixturePath, outDir: output.path),
    );

    expect(report.contractPassed, isTrue);
    expect(report.result.candidateFileCount, 2);
    expect(report.result.candidateCorpusBytes, 276);
    expect(report.result.candidates, hasLength(2));
    expect(
      report.result.candidates.expand((source) => source.chunks),
      hasLength(5),
    );
    expect(
      report.result.candidates
          .expand((source) => source.chunks)
          .map((chunk) => chunk.locator),
      [
        'markdown:guide',
        'markdown:guide/endpoint',
        'markdown:guide/retry-policy',
        'dart:defaultEndpoint',
        'dart:RetryPolicy',
      ],
    );
    expect(report.result.exclusions.map((item) => item.toJson()), [
      {'path': 'assets/note.txt', 'reason': 'unsupported_extension'},
      {'path': 'build/', 'reason': 'generated_directory'},
      {'path': 'lib/config.g.dart', 'reason': 'generated_file'},
    ]);
  });

  test('writes deterministic reports without roots or source text', () async {
    final output = Directory.systemTemp.createTempSync('rag2-discovery-');
    addTearDown(() => output.deleteSync(recursive: true));
    final report = await runRag2SourceDiscoveryReplay(
      Rag2SourceDiscoveryOptions(fixturePath: fixturePath, outDir: output.path),
    );
    final jsonReport = File(
      '${output.path}/rag2_source_discovery_replay.json',
    ).readAsStringSync();
    final markdownReport = File(
      '${output.path}/rag2_source_discovery_replay.md',
    ).readAsStringSync();

    expect(jsonDecode(jsonReport), report.toJson());
    expect(markdownReport, report.toMarkdown());
    for (final forbidden in [
      Directory.current.path,
      '/Users/',
      'Use the local project configuration.',
      "const defaultEndpoint = 'http://localhost:1234/v1';",
    ]) {
      expect(jsonReport, isNot(contains(forbidden)));
      expect(markdownReport, isNot(contains(forbidden)));
    }
  });

  test('fails closed when file or corpus limits are exceeded', () async {
    final root = Directory.systemTemp.createTempSync('rag2-discovery-limits-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.md').writeAsStringSync('# A\n\nAlpha.\n');
    File('${root.path}/b.md').writeAsStringSync('# B\n\nBeta.\n');

    final fileLimited = await _discover(
      root,
      const Rag2SourceDiscoveryPolicy(
        maxFiles: 1,
        maxFileBytes: 1024,
        maxCorpusBytes: 1024,
      ),
    );
    final corpusLimited = await _discover(
      root,
      const Rag2SourceDiscoveryPolicy(
        maxFiles: 2,
        maxFileBytes: 1024,
        maxCorpusBytes: 5,
      ),
    );

    expect(fileLimited.violations, ['file_count_exceeded']);
    expect(fileLimited.candidates, isEmpty);
    expect(corpusLimited.violations, ['corpus_bytes_exceeded']);
    expect(corpusLimited.candidates, isEmpty);
  });

  test('excludes individual oversized files before attestation', () async {
    final root = Directory.systemTemp.createTempSync('rag2-discovery-size-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/large.md').writeAsStringSync('# Large\n\nToo large.\n');

    final result = await _discover(
      root,
      const Rag2SourceDiscoveryPolicy(
        maxFiles: 1,
        maxFileBytes: 4,
        maxCorpusBytes: 1024,
      ),
    );

    expect(result.candidateFileCount, 0);
    expect(result.candidates, isEmpty);
    expect(result.exclusions.map((item) => item.toJson()), [
      {'path': 'large.md', 'reason': 'file_bytes_exceeded'},
    ]);
  });

  test('rejects symlinks and sources without Git evidence', () async {
    final root = Directory.systemTemp.createTempSync('rag2-discovery-trust-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/missing.md').writeAsStringSync('# Missing\n');
    final target = File('${root.path}/target.md')
      ..writeAsStringSync('# Target\n');
    final link = Link('${root.path}/linked.md');
    try {
      link.createSync(target.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }

    final result = await _discover(root, _defaultPolicy);

    expect(result.candidates, isEmpty);
    expect(
      result.exclusions.map((item) => item.toJson()),
      containsAll([
        {'path': 'linked.md', 'reason': 'symlink_rejected'},
        {'path': 'missing.md', 'reason': 'git_evidence_unavailable'},
        {'path': 'target.md', 'reason': 'git_evidence_unavailable'},
      ]),
    );
  });

  test('fails closed on duplicate Markdown and Dart locators', () async {
    final markdownRoot = Directory.systemTemp.createTempSync(
      'rag2-discovery-markdown-',
    );
    final dartRoot = Directory.systemTemp.createTempSync(
      'rag2-discovery-dart-',
    );
    addTearDown(() => markdownRoot.deleteSync(recursive: true));
    addTearDown(() => dartRoot.deleteSync(recursive: true));
    File(
      '${markdownRoot.path}/duplicate.md',
    ).writeAsStringSync('# Same\n\nOne.\n\n# Same\n\nTwo.\n');
    File(
      '${dartRoot.path}/duplicate.dart',
    ).writeAsStringSync('const repeated = 1;\nconst repeated = 2;\n');

    await expectLater(
      _discover(
        markdownRoot,
        _defaultPolicy,
        evidenceByPath: {'duplicate.md': _trackedEvidence},
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      _discover(
        dartRoot,
        _defaultPolicy,
        evidenceByPath: {'duplicate.dart': _trackedEvidence},
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('resolves Git evidence lazily through the project provider', () async {
    final root = Directory.systemTemp.createTempSync(
      'rag2-discovery-provider-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/docs').createSync();
    Directory('${root.path}/lib').createSync();
    File('${root.path}/docs/guide.md').writeAsStringSync('# Guide\n');
    File(
      '${root.path}/lib/config.dart',
    ).writeAsStringSync("const endpoint = 'local';\n");
    final requestedPaths = <String>[];

    final result = await discoverRag2Sources(
      project: _project(root),
      policy: _defaultPolicy,
      gitEvidenceProvider: (path) async {
        requestedPaths.add(path);
        return _trackedEvidence;
      },
    );

    expect(requestedPaths, ['docs/guide.md', 'lib/config.dart']);
    expect(result.candidates, hasLength(2));
  });

  test(
    'hashes chunks from attested text and omits that text from reports',
    () async {
      final output = Directory.systemTemp.createTempSync(
        'rag2-discovery-bound-',
      );
      addTearDown(() => output.deleteSync(recursive: true));
      final report = await runRag2SourceDiscoveryReplay(
        Rag2SourceDiscoveryOptions(
          fixturePath: fixturePath,
          outDir: output.path,
        ),
      );

      for (final source in report.result.candidates) {
        expect(source.attestation.hasBoundText, isTrue);
        final lines = source.attestation.attestedText!.split('\n');
        for (final chunk in source.chunks) {
          final content = lines
              .sublist(chunk.lineStart - 1, chunk.lineEnd)
              .join('\n');
          expect(
            sha256.convert(utf8.encode(content)).toString(),
            chunk.contentHash,
          );
        }
      }

      final jsonReport = File(
        '${output.path}/rag2_source_discovery_replay.json',
      ).readAsStringSync();
      expect(jsonReport, isNot(contains('attestedText')));
      expect(
        jsonReport,
        isNot(contains('Use the local project configuration.')),
      );
    },
  );
}

const _defaultPolicy = Rag2SourceDiscoveryPolicy(
  maxFiles: 8,
  maxFileBytes: 1024,
  maxCorpusBytes: 4096,
);

const _trackedEvidence = Rag2GitEvidence(
  available: true,
  lsFilesExitCode: 0,
  statusPorcelain: '',
  headBlobRevision: '1111111111111111111111111111111111111111',
);

Future<Rag2SourceDiscoveryResult> _discover(
  Directory root,
  Rag2SourceDiscoveryPolicy policy, {
  Map<String, Rag2GitEvidence> evidenceByPath = const {},
}) => discoverRag2FixtureSources(
  project: _project(root),
  policy: policy,
  gitEvidenceByPath: evidenceByPath,
);

CodingProject _project(Directory root) => CodingProject(
  id: 'test-project',
  name: 'Test project',
  rootPath: root.path,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
);
