import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:crypto/crypto.dart';

import 'rag2_knowledge_object_replay.dart' show validateRag2RepoRelativePath;
import 'rag2_provenance_attestation_replay.dart';

const rag2SourceDiscoveryContract = 'rag2-source-discovery-contract-v1';
const rag2SourceDiscoveryFixtureSchema =
    'caverno_rag2_source_discovery_fixture';
const rag2SourceDiscoveryReportSchema = 'caverno_rag2_source_discovery_report';

typedef Rag2GitEvidenceProvider =
    Future<Rag2GitEvidence> Function(String repoRelativePath);

Future<void> main(List<String> args) async {
  final options = Rag2SourceDiscoveryOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_source_discovery_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2SourceDiscoveryReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 source discovery replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2SourceDiscoveryReport> runRag2SourceDiscoveryReplay(
  Rag2SourceDiscoveryOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await Rag2SourceDiscoveryFixture.load(fixtureFile);
  final result = await discoverRag2FixtureSources(
    project: CodingProject(
      id: fixture.projectId,
      name: 'RAG2 discovery fixture',
      rootPath: '${fixtureFile.parent.path}/${fixture.root}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    policy: fixture.policy,
    gitEvidenceByPath: fixture.gitEvidenceByPath,
  );
  final report = Rag2SourceDiscoveryReport(
    fixtureId: fixture.fixtureId,
    result: result,
    expectedPassed: fixture.expected.matches(result),
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_source_discovery_replay.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_source_discovery_replay.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2SourceDiscoveryResult> discoverRag2FixtureSources({
  required CodingProject project,
  required Rag2SourceDiscoveryPolicy policy,
  required Map<String, Rag2GitEvidence> gitEvidenceByPath,
}) => discoverRag2Sources(
  project: project,
  policy: policy,
  gitEvidenceProvider: (path) async =>
      gitEvidenceByPath[path] ??
      const Rag2GitEvidence(
        available: false,
        lsFilesExitCode: 127,
        statusPorcelain: '',
      ),
);

Future<Rag2SourceDiscoveryResult> discoverRag2Sources({
  required CodingProject project,
  required Rag2SourceDiscoveryPolicy policy,
  required Rag2GitEvidenceProvider gitEvidenceProvider,
  bool includeChunks = true,
}) async {
  final root = Directory(project.normalizedRootPath);
  final candidates = <({String path, File file, int bytes})>[];
  final exclusions = <Rag2DiscoveryExclusion>[];
  await _walkFixtureRoot(
    root: root,
    directory: root,
    policy: policy,
    candidates: candidates,
    exclusions: exclusions,
  );
  candidates.sort((left, right) => left.path.compareTo(right.path));
  exclusions.sort((left, right) {
    final path = left.path.compareTo(right.path);
    return path != 0 ? path : left.reason.compareTo(right.reason);
  });
  final corpusBytes = candidates.fold<int>(0, (sum, item) => sum + item.bytes);
  final violations = <String>[
    if (candidates.length > policy.maxFiles) 'file_count_exceeded',
    if (corpusBytes > policy.maxCorpusBytes) 'corpus_bytes_exceeded',
  ];
  if (violations.isNotEmpty) {
    return Rag2SourceDiscoveryResult(
      candidates: const [],
      exclusions: exclusions,
      violations: violations,
      candidateFileCount: candidates.length,
      candidateCorpusBytes: corpusBytes,
    );
  }

  final sources = <Rag2DiscoveredSource>[];
  for (final candidate in candidates) {
    final evidence = await gitEvidenceProvider(candidate.path);
    final attestation = await attestRag2ProjectSource(
      caseId: candidate.path,
      project: project,
      repoRelativePath: candidate.path,
      gitEvidence: evidence,
      maxFileBytes: policy.maxFileBytes,
    );
    if (attestation.decision != 'attested') {
      exclusions.add(
        Rag2DiscoveryExclusion(
          path: candidate.path,
          reason: attestation.reason ?? 'attestation_rejected',
        ),
      );
      continue;
    }
    final chunks = includeChunks
        ? _chunkCandidate(candidate.path, await candidate.file.readAsString())
        : const <Rag2CandidateChunk>[];
    sources.add(
      Rag2DiscoveredSource(
        attestation: attestation,
        sourceKind: candidate.path.endsWith('.md') ? 'markdown' : 'code',
        bytes: candidate.bytes,
        chunks: chunks,
      ),
    );
  }
  sources.sort(
    (left, right) => left.attestation.repoRelativePath.compareTo(
      right.attestation.repoRelativePath,
    ),
  );
  exclusions.sort((left, right) {
    final path = left.path.compareTo(right.path);
    return path != 0 ? path : left.reason.compareTo(right.reason);
  });
  return Rag2SourceDiscoveryResult(
    candidates: sources,
    exclusions: exclusions,
    violations: const [],
    candidateFileCount: candidates.length,
    candidateCorpusBytes: corpusBytes,
  );
}

List<Rag2CandidateChunk> _chunkCandidate(String path, String text) {
  final normalized = _normalizeText(text);
  return path.endsWith('.md')
      ? _chunkMarkdown(path, normalized)
      : _chunkDart(path, normalized);
}

Future<void> _walkFixtureRoot({
  required Directory root,
  required Directory directory,
  required Rag2SourceDiscoveryPolicy policy,
  required List<({String path, File file, int bytes})> candidates,
  required List<Rag2DiscoveryExclusion> exclusions,
}) async {
  final entities = await directory.list(followLinks: false).toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final entity in entities) {
    final relative = _relativePath(entity.path, root.path);
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      exclusions.add(
        Rag2DiscoveryExclusion(path: relative, reason: 'symlink_rejected'),
      );
      continue;
    }
    if (entity is Directory) {
      if (_isExcludedDirectory(relative)) {
        exclusions.add(
          Rag2DiscoveryExclusion(
            path: '$relative/',
            reason: 'generated_directory',
          ),
        );
      } else {
        await _walkFixtureRoot(
          root: root,
          directory: entity,
          policy: policy,
          candidates: candidates,
          exclusions: exclusions,
        );
      }
      continue;
    }
    if (entity is! File) continue;
    if (_isGeneratedFile(relative)) {
      exclusions.add(
        Rag2DiscoveryExclusion(path: relative, reason: 'generated_file'),
      );
      continue;
    }
    if (!relative.endsWith('.md') && !relative.endsWith('.dart')) {
      exclusions.add(
        Rag2DiscoveryExclusion(path: relative, reason: 'unsupported_extension'),
      );
      continue;
    }
    final bytes = await entity.length();
    if (bytes > policy.maxFileBytes) {
      exclusions.add(
        Rag2DiscoveryExclusion(path: relative, reason: 'file_bytes_exceeded'),
      );
      continue;
    }
    candidates.add((path: relative, file: entity, bytes: bytes));
  }
}

bool _isExcludedDirectory(String path) {
  final name = path.split('/').last;
  return const {
        '.dart_tool',
        '.fvm',
        '.git',
        '.idea',
        '.symlinks',
        '.vscode',
        'build',
        'node_modules',
        'Pods',
      }.contains(name) ||
      name.startsWith('.');
}

bool _isGeneratedFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.g.dart') ||
      lower.endsWith('.freezed.dart') ||
      lower.endsWith('.mocks.dart') ||
      lower.endsWith('.gen.dart');
}

List<Rag2CandidateChunk> _chunkMarkdown(String path, String text) {
  final lines = text.split('\n');
  final starts = <int>[];
  for (var index = 0; index < lines.length; index++) {
    if (RegExp(r'^#{1,6}\s+\S').hasMatch(lines[index])) starts.add(index);
  }
  if (starts.isNotEmpty &&
      starts.first > 0 &&
      lines.take(starts.first).any((line) => line.trim().isNotEmpty)) {
    starts.insert(0, 0);
  }
  if (starts.isEmpty) starts.add(0);
  final chunks = <Rag2CandidateChunk>[];
  final headings = <String>[];
  final locators = <String>{};
  for (var index = 0; index < starts.length; index++) {
    final start = starts[index];
    final end = index + 1 < starts.length
        ? starts[index + 1] - 1
        : lines.length - 1;
    final heading = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(lines[start]);
    String locator;
    if (heading == null) {
      locator = 'markdown:root';
    } else {
      final level = heading.group(1)!.length;
      while (headings.length >= level) {
        headings.removeLast();
      }
      while (headings.length < level - 1) {
        headings.add('_');
      }
      headings.add(_locatorPart(heading.group(2)!));
      locator = 'markdown:${headings.join('/')}';
    }
    if (!locators.add(locator)) {
      throw FormatException(
        'Markdown source has a duplicate semantic locator: $path#$locator',
      );
    }
    chunks.add(_candidateChunk(path, locator, lines, start, end));
  }
  return chunks;
}

List<Rag2CandidateChunk> _chunkDart(String path, String text) {
  final lines = text.split('\n');
  final symbols = <({int line, String name})>[];
  final pattern = RegExp(
    r'^(?:const|final|var)\s+(?:[A-Za-z_]\w*(?:<[^>]+>)?[?]?\s+)?([A-Za-z_]\w*)\s*=|^(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_]\w*)|^(?:[A-Za-z_]\w*(?:<[^>]+>)?[?]?\s+)+([A-Za-z_]\w*)\s*\(',
  );
  for (var index = 0; index < lines.length; index++) {
    final match = pattern.firstMatch(lines[index]);
    if (match == null) continue;
    symbols.add((
      line: index,
      name: match.group(1) ?? match.group(2) ?? match.group(3)!,
    ));
  }
  if (symbols.isEmpty) {
    throw FormatException('Dart source has no stable symbol boundary: $path');
  }
  final locators = <String>{};
  return [
    for (var index = 0; index < symbols.length; index++)
      _candidateChunk(
        path,
        _uniqueDartLocator(path, symbols[index].name, locators),
        lines,
        symbols[index].line,
        index + 1 < symbols.length
            ? symbols[index + 1].line - 1
            : lines.length - 1,
      ),
  ];
}

Rag2CandidateChunk _candidateChunk(
  String path,
  String locator,
  List<String> lines,
  int start,
  int end,
) {
  while (end >= start && lines[end].trim().isEmpty) {
    end--;
  }
  final content = end < start ? '' : lines.sublist(start, end + 1).join('\n');
  return Rag2CandidateChunk(
    chunkId: _stableId('candidate', [path, locator, _sha256(content)]),
    locator: locator,
    lineStart: start + 1,
    lineEnd: end + 1,
    contentHash: _sha256(content),
  );
}

String _uniqueDartLocator(String path, String name, Set<String> locators) {
  final locator = 'dart:$name';
  if (!locators.add(locator)) {
    throw FormatException(
      'Dart source has a duplicate semantic locator: $path#$locator',
    );
  }
  return locator;
}

String _locatorPart(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _relativePath(String path, String root) {
  final normalizedPath = path.replaceAll('\\', '/');
  final normalizedRoot = root
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  final prefix = '$normalizedRoot/';
  final relative = normalizedPath.startsWith(prefix)
      ? normalizedPath.substring(prefix.length)
      : normalizedPath;
  validateRag2RepoRelativePath(relative);
  return relative;
}

String _normalizeText(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
String _stableId(String prefix, List<String> parts) =>
    '${prefix}_${_sha256([rag2SourceDiscoveryContract, ...parts].join('\u0000'))}';
String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

final class Rag2CandidateChunk {
  const Rag2CandidateChunk({
    required this.chunkId,
    required this.locator,
    required this.lineStart,
    required this.lineEnd,
    required this.contentHash,
  });
  final String chunkId;
  final String locator;
  final int lineStart;
  final int lineEnd;
  final String contentHash;
  Map<String, Object?> toJson() => {
    'chunkId': chunkId,
    'locator': locator,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
    'contentHash': contentHash,
  };
}

final class Rag2DiscoveredSource {
  const Rag2DiscoveredSource({
    required this.attestation,
    required this.sourceKind,
    required this.bytes,
    required this.chunks,
  });
  final Rag2SourceAttestation attestation;
  final String sourceKind;
  final int bytes;
  final List<Rag2CandidateChunk> chunks;
  Map<String, Object?> toJson() => {
    ...attestation.toJson(),
    'sourceKind': sourceKind,
    'bytes': bytes,
    'chunks': [for (final chunk in chunks) chunk.toJson()],
  };
}

final class Rag2DiscoveryExclusion {
  const Rag2DiscoveryExclusion({required this.path, required this.reason});
  final String path;
  final String reason;
  Map<String, Object?> toJson() => {'path': path, 'reason': reason};
}

final class Rag2SourceDiscoveryResult {
  const Rag2SourceDiscoveryResult({
    required this.candidates,
    required this.exclusions,
    required this.violations,
    required this.candidateFileCount,
    required this.candidateCorpusBytes,
  });
  final List<Rag2DiscoveredSource> candidates;
  final List<Rag2DiscoveryExclusion> exclusions;
  final List<String> violations;
  final int candidateFileCount;
  final int candidateCorpusBytes;
  Map<String, Object?> toJson() => {
    'candidateFileCount': candidateFileCount,
    'candidateCorpusBytes': candidateCorpusBytes,
    'violations': violations,
    'sources': [for (final source in candidates) source.toJson()],
    'exclusions': [for (final item in exclusions) item.toJson()],
  };
}

final class Rag2SourceDiscoveryPolicy {
  const Rag2SourceDiscoveryPolicy({
    required this.maxFiles,
    required this.maxFileBytes,
    required this.maxCorpusBytes,
  });
  final int maxFiles;
  final int maxFileBytes;
  final int maxCorpusBytes;
  factory Rag2SourceDiscoveryPolicy.fromJson(Map<String, Object?> json) {
    final policy = Rag2SourceDiscoveryPolicy(
      maxFiles: json['maxFiles'] as int,
      maxFileBytes: json['maxFileBytes'] as int,
      maxCorpusBytes: json['maxCorpusBytes'] as int,
    );
    if (policy.maxFiles <= 0 ||
        policy.maxFileBytes <= 0 ||
        policy.maxCorpusBytes <= 0) {
      throw const FormatException(
        'Source discovery limits must be positive integers.',
      );
    }
    return policy;
  }
}

final class Rag2SourceDiscoveryFixture {
  const Rag2SourceDiscoveryFixture({
    required this.fixtureId,
    required this.projectId,
    required this.root,
    required this.policy,
    required this.gitEvidenceByPath,
    required this.expected,
  });
  final String fixtureId;
  final String projectId;
  final String root;
  final Rag2SourceDiscoveryPolicy policy;
  final Map<String, Rag2GitEvidence> gitEvidenceByPath;
  final Rag2SourceDiscoveryExpected expected;
  static Future<Rag2SourceDiscoveryFixture> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != rag2SourceDiscoveryFixtureSchema ||
        json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported source discovery fixture.');
    }
    validateRag2RepoRelativePath(json['root'] as String);
    return Rag2SourceDiscoveryFixture(
      fixtureId: json['fixtureId'] as String,
      projectId: json['projectId'] as String,
      root: json['root'] as String,
      policy: Rag2SourceDiscoveryPolicy.fromJson(
        (json['policy'] as Map).cast<String, Object?>(),
      ),
      gitEvidenceByPath: (json['gitEvidenceByPath'] as Map).map(
        (key, value) => MapEntry(
          key as String,
          Rag2GitEvidence.fromJson((value as Map).cast<String, Object?>()),
        ),
      ),
      expected: Rag2SourceDiscoveryExpected.fromJson(
        (json['expected'] as Map).cast<String, Object?>(),
      ),
    );
  }
}

final class Rag2SourceDiscoveryExpected {
  const Rag2SourceDiscoveryExpected(this.result);
  final Map<String, Object?> result;
  factory Rag2SourceDiscoveryExpected.fromJson(Map<String, Object?> json) =>
      Rag2SourceDiscoveryExpected(
        (json['result'] as Map).cast<String, Object?>(),
      );
  bool matches(Rag2SourceDiscoveryResult actual) =>
      jsonEncode(result) == jsonEncode(actual.toJson());
}

final class Rag2SourceDiscoveryReport {
  const Rag2SourceDiscoveryReport({
    required this.fixtureId,
    required this.result,
    required this.expectedPassed,
  });
  final String fixtureId;
  final Rag2SourceDiscoveryResult result;
  final bool expectedPassed;
  bool get contractPassed => expectedPassed && result.violations.isEmpty;
  Map<String, Object?> toJson() => {
    'schemaName': rag2SourceDiscoveryReportSchema,
    'schemaVersion': 1,
    'contract': rag2SourceDiscoveryContract,
    'fixtureId': fixtureId,
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'productionDiscoveryDecision': 'no_go',
    'storageDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'result': result.toJson(),
  };
  String toMarkdown() =>
      '# RAG2 Source Discovery Replay\n\n- Contract: `$rag2SourceDiscoveryContract`\n- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n- Production discovery decision: `no_go`\n- Storage decision: `not_evaluated`\n- Production decision: `no_go`\n- Selected sources: `${result.candidates.length}`\n- Candidate chunks: `${result.candidates.expand((source) => source.chunks).length}`\n- Exclusions: `${result.exclusions.length}`\n- Limit violations: `${result.violations.length}`\n';
}

final class Rag2SourceDiscoveryOptions {
  const Rag2SourceDiscoveryOptions({
    required this.fixturePath,
    required this.outDir,
  });
  final String fixturePath;
  final String outDir;
  static Rag2SourceDiscoveryOptions? parse(List<String> args) {
    String? fixturePath;
    String? outDir;
    for (var index = 0; index < args.length; index++) {
      if (index + 1 >= args.length) return null;
      switch (args[index]) {
        case '--fixture':
          fixturePath = args[++index];
        case '--out-dir':
          outDir = args[++index];
        default:
          return null;
      }
    }
    return fixturePath == null || outDir == null
        ? null
        : Rag2SourceDiscoveryOptions(fixturePath: fixturePath, outDir: outDir);
  }
}
