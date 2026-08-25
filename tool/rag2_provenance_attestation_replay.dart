import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/bounded_text_file_classifier.dart';
import 'package:caverno/features/chat/data/datasources/project_read_path_fence.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import 'rag2_knowledge_object_replay.dart' show validateRag2RepoRelativePath;

const rag2ProvenanceAttestationContract =
    'rag2-provenance-attestation-contract-v1';
const rag2ProvenanceAttestationFixtureSchema =
    'caverno_rag2_provenance_attestation_fixture';
const rag2ProvenanceAttestationReportSchema =
    'caverno_rag2_provenance_attestation_report';

Future<void> main(List<String> args) async {
  final options = Rag2ProvenanceReplayOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_provenance_attestation_replay.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2ProvenanceAttestationReplay(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 provenance attestation replay failed: $error');
    exitCode = 65;
  }
}

Future<Rag2ProvenanceAttestationReport> runRag2ProvenanceAttestationReplay(
  Rag2ProvenanceReplayOptions options,
) async {
  final fixtureFile = File(options.fixturePath);
  final fixture = await Rag2ProvenanceAttestationFixture.load(fixtureFile);
  final results = <Rag2SourceAttestation>[];
  for (final spec in fixture.cases) {
    results.add(
      await attestRag2ProjectSource(
        caseId: spec.id,
        project: CodingProject(
          id: fixture.projectId,
          name: 'RAG2 provenance fixture',
          rootPath: '${fixtureFile.parent.path}/${spec.root}',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
        repoRelativePath: spec.path,
        gitEvidence: spec.gitEvidence,
      ),
    );
  }
  final byCase = {for (final result in results) result.caseId: result};
  final identityPairsStable = fixture.identityPairs.every((pair) {
    final left = byCase[pair.leftCaseId];
    final right = byCase[pair.rightCaseId];
    return left?.decision == 'attested' &&
        right?.decision == 'attested' &&
        left!.sourceIdentity == right!.sourceIdentity;
  });
  final report = Rag2ProvenanceAttestationReport(
    fixtureId: fixture.fixtureId,
    results: results,
    identityPairsStable: identityPairsStable,
    expectedPassed: fixture.expected.matches(
      results: results,
      identityPairsStable: identityPairsStable,
    ),
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_provenance_attestation_replay.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_provenance_attestation_replay.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2SourceAttestation> attestRag2ProjectSource({
  required String caseId,
  required CodingProject project,
  required String repoRelativePath,
  required Rag2GitEvidence gitEvidence,
  int maxFileBytes = 1024 * 1024,
  ProjectReadPathFence pathFence = const ProjectReadPathFence(),
}) async {
  if (project.id.trim().isEmpty) {
    return Rag2SourceAttestation.rejected(
      caseId: caseId,
      repoRelativePath: repoRelativePath,
      reason: 'project_identity_unavailable',
    );
  }
  try {
    validateRag2RepoRelativePath(repoRelativePath);
  } on FormatException {
    return Rag2SourceAttestation.rejected(
      caseId: caseId,
      repoRelativePath: repoRelativePath,
      reason: 'repo_relative_path_invalid',
    );
  }
  final authorization = await pathFence.authorize(
    projectRoot: project.normalizedRootPath,
    rawPath: repoRelativePath,
  );
  if (!authorization.isAllowed) {
    return Rag2SourceAttestation.rejected(
      caseId: caseId,
      repoRelativePath: repoRelativePath,
      reason: authorization.denial?.code ?? 'project_read_denied',
    );
  }
  final file = File(authorization.canonicalPath!);
  try {
    final bytes = await _readBounded(file, maxFileBytes);
    if (bytes == null) {
      return Rag2SourceAttestation.rejected(
        caseId: caseId,
        repoRelativePath: repoRelativePath,
        reason: 'source_too_large',
      );
    }
    if (await BoundedTextFileClassifier.looksBinary(file)) {
      return Rag2SourceAttestation.rejected(
        caseId: caseId,
        repoRelativePath: repoRelativePath,
        reason: 'binary_source_not_supported',
      );
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    final contentHash = _sha256(_normalizeText(text));
    final derived = _deriveGitState(
      repoRelativePath: repoRelativePath,
      evidence: gitEvidence,
      contentHash: contentHash,
    );
    if (derived == null) {
      return Rag2SourceAttestation.rejected(
        caseId: caseId,
        repoRelativePath: repoRelativePath,
        reason: gitEvidence.available
            ? 'git_state_ambiguous'
            : 'git_evidence_unavailable',
      );
    }
    const capabilityClassifier = ToolCapabilityClassifier();
    final capability = capabilityClassifier.classify('inspect_file');
    if (capability.capabilityClass != ToolCapabilityClass.readOnlyInspection) {
      throw StateError('Source attestation must remain read-only inspection.');
    }
    return Rag2SourceAttestation.attested(
      caseId: caseId,
      repoRelativePath: repoRelativePath,
      sourceIdentity: _stableId('source', [project.id, repoRelativePath]),
      sourceTrust: derived.sourceTrust,
      worktreeState: derived.worktreeState,
      revisionKind: derived.revisionKind,
      revision: derived.revision,
      contentHash: contentHash,
      capabilityClass: capability.capabilityClass.name,
      capabilityRisk: capability.riskTier.name,
    );
  } on FormatException {
    return Rag2SourceAttestation.rejected(
      caseId: caseId,
      repoRelativePath: repoRelativePath,
      reason: 'binary_source_not_supported',
    );
  } on FileSystemException {
    return Rag2SourceAttestation.rejected(
      caseId: caseId,
      repoRelativePath: repoRelativePath,
      reason: 'source_unavailable',
    );
  }
}

Future<List<int>?> _readBounded(File file, int maxFileBytes) async {
  if (maxFileBytes <= 0) {
    throw ArgumentError.value(
      maxFileBytes,
      'maxFileBytes',
      'Must be positive.',
    );
  }
  final bytes = <int>[];
  await for (final chunk in file.openRead(0, maxFileBytes + 1)) {
    bytes.addAll(chunk);
    if (bytes.length > maxFileBytes) return null;
  }
  return bytes;
}

({
  String sourceTrust,
  String worktreeState,
  String revisionKind,
  String revision,
})?
_deriveGitState({
  required String repoRelativePath,
  required Rag2GitEvidence evidence,
  required String contentHash,
}) {
  if (!evidence.available) return null;
  final status = evidence.statusPorcelain.trimRight();
  if (evidence.lsFilesExitCode == 0) {
    if (status.isEmpty) {
      final blob = evidence.headBlobRevision?.trim() ?? '';
      if (blob.isEmpty) return null;
      return (
        sourceTrust: 'workspace_tracked',
        worktreeState: 'clean',
        revisionKind: 'git_blob',
        revision: 'git_blob:$blob',
      );
    }
    if (!_statusTargetsOnly(status, repoRelativePath)) return null;
    return (
      sourceTrust: 'workspace_tracked',
      worktreeState: 'modified',
      revisionKind: 'working_tree_content',
      revision: 'working_tree_sha256:$contentHash',
    );
  }
  if (evidence.lsFilesExitCode == 1 &&
      status
          .split('\n')
          .any(
            (line) =>
                line.startsWith('?? ') &&
                line.substring(3).trim() == repoRelativePath,
          )) {
    return (
      sourceTrust: 'workspace_untracked',
      worktreeState: 'untracked',
      revisionKind: 'working_tree_content',
      revision: 'working_tree_sha256:$contentHash',
    );
  }
  return null;
}

bool _statusTargetsOnly(String status, String repoRelativePath) {
  final lines = status.split('\n').where((line) => line.trim().isNotEmpty);
  return lines.isNotEmpty &&
      lines.every((line) {
        if (line.length < 4) return false;
        final body = line.substring(3).trim();
        final target = body.contains(' -> ') ? body.split(' -> ').last : body;
        return target == repoRelativePath;
      });
}

String _normalizeText(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _stableId(String prefix, List<String> parts) =>
    '${prefix}_${_sha256([rag2ProvenanceAttestationContract, ...parts].join('\u0000'))}';

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

final class Rag2SourceAttestation {
  const Rag2SourceAttestation._({
    required this.caseId,
    required this.decision,
    required this.repoRelativePath,
    this.reason,
    this.sourceIdentity,
    this.sourceTrust,
    this.worktreeState,
    this.revisionKind,
    this.revision,
    this.contentHash,
    this.capabilityClass,
    this.capabilityRisk,
  });

  factory Rag2SourceAttestation.attested({
    required String caseId,
    required String repoRelativePath,
    required String sourceIdentity,
    required String sourceTrust,
    required String worktreeState,
    required String revisionKind,
    required String revision,
    required String contentHash,
    required String capabilityClass,
    required String capabilityRisk,
  }) => Rag2SourceAttestation._(
    caseId: caseId,
    decision: 'attested',
    repoRelativePath: repoRelativePath,
    sourceIdentity: sourceIdentity,
    sourceTrust: sourceTrust,
    worktreeState: worktreeState,
    revisionKind: revisionKind,
    revision: revision,
    contentHash: contentHash,
    capabilityClass: capabilityClass,
    capabilityRisk: capabilityRisk,
  );

  factory Rag2SourceAttestation.rejected({
    required String caseId,
    required String repoRelativePath,
    required String reason,
  }) => Rag2SourceAttestation._(
    caseId: caseId,
    decision: 'rejected',
    repoRelativePath: repoRelativePath,
    reason: reason,
  );

  final String caseId;
  final String decision;
  final String repoRelativePath;
  final String? reason;
  final String? sourceIdentity;
  final String? sourceTrust;
  final String? worktreeState;
  final String? revisionKind;
  final String? revision;
  final String? contentHash;
  final String? capabilityClass;
  final String? capabilityRisk;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'decision': decision,
    'repoRelativePath': repoRelativePath,
    if (reason != null) 'reason': reason,
    if (sourceIdentity != null) 'sourceIdentity': sourceIdentity,
    if (sourceTrust != null) 'sourceTrust': sourceTrust,
    if (worktreeState != null) 'worktreeState': worktreeState,
    if (revisionKind != null) 'revisionKind': revisionKind,
    if (revision != null) 'revision': revision,
    if (contentHash != null) 'contentHash': contentHash,
    if (capabilityClass != null) 'capabilityClass': capabilityClass,
    if (capabilityRisk != null) 'capabilityRisk': capabilityRisk,
    if (decision == 'attested') 'canonicalContainment': 'inside_project',
  };
}

final class Rag2GitEvidence {
  const Rag2GitEvidence({
    required this.available,
    required this.lsFilesExitCode,
    required this.statusPorcelain,
    this.headBlobRevision,
  });

  final bool available;
  final int lsFilesExitCode;
  final String statusPorcelain;
  final String? headBlobRevision;

  factory Rag2GitEvidence.fromJson(Map<String, Object?> json) =>
      Rag2GitEvidence(
        available: json['available'] as bool,
        lsFilesExitCode: json['lsFilesExitCode'] as int,
        statusPorcelain: json['statusPorcelain'] as String,
        headBlobRevision: json['headBlobRevision'] as String?,
      );
}

final class Rag2ProvenanceCaseSpec {
  const Rag2ProvenanceCaseSpec({
    required this.id,
    required this.root,
    required this.path,
    required this.gitEvidence,
  });

  final String id;
  final String root;
  final String path;
  final Rag2GitEvidence gitEvidence;

  factory Rag2ProvenanceCaseSpec.fromJson(Map<String, Object?> json) =>
      Rag2ProvenanceCaseSpec(
        id: json['id'] as String,
        root: json['root'] as String,
        path: json['path'] as String,
        gitEvidence: Rag2GitEvidence.fromJson(
          (json['gitEvidence'] as Map).cast<String, Object?>(),
        ),
      );
}

final class Rag2IdentityPair {
  const Rag2IdentityPair(this.leftCaseId, this.rightCaseId);

  final String leftCaseId;
  final String rightCaseId;
}

final class Rag2ProvenanceAttestationFixture {
  const Rag2ProvenanceAttestationFixture({
    required this.fixtureId,
    required this.projectId,
    required this.cases,
    required this.identityPairs,
    required this.expected,
  });

  final String fixtureId;
  final String projectId;
  final List<Rag2ProvenanceCaseSpec> cases;
  final List<Rag2IdentityPair> identityPairs;
  final Rag2ProvenanceExpected expected;

  static Future<Rag2ProvenanceAttestationFixture> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != rag2ProvenanceAttestationFixtureSchema ||
        json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported provenance fixture.');
    }
    return Rag2ProvenanceAttestationFixture(
      fixtureId: json['fixtureId'] as String,
      projectId: json['projectId'] as String,
      cases: (json['cases'] as List)
          .map(
            (item) => Rag2ProvenanceCaseSpec.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(),
      identityPairs: (json['identityPairs'] as List)
          .map(
            (item) => Rag2IdentityPair(
              (item as List)[0] as String,
              item[1] as String,
            ),
          )
          .toList(),
      expected: Rag2ProvenanceExpected.fromJson(
        (json['expected'] as Map).cast<String, Object?>(),
      ),
    );
  }
}

final class Rag2ProvenanceExpected {
  const Rag2ProvenanceExpected({
    required this.identityPairsStable,
    required this.results,
  });

  final bool identityPairsStable;
  final List<Map<String, Object?>> results;

  factory Rag2ProvenanceExpected.fromJson(Map<String, Object?> json) =>
      Rag2ProvenanceExpected(
        identityPairsStable: json['identityPairsStable'] as bool,
        results: (json['results'] as List)
            .map((item) => (item as Map).cast<String, Object?>())
            .toList(),
      );

  bool matches({
    required List<Rag2SourceAttestation> results,
    required bool identityPairsStable,
  }) =>
      this.identityPairsStable == identityPairsStable &&
      jsonEncode(this.results) ==
          jsonEncode([for (final result in results) result.toJson()]);
}

final class Rag2ProvenanceAttestationReport {
  const Rag2ProvenanceAttestationReport({
    required this.fixtureId,
    required this.results,
    required this.identityPairsStable,
    required this.expectedPassed,
  });

  final String fixtureId;
  final List<Rag2SourceAttestation> results;
  final bool identityPairsStable;
  final bool expectedPassed;
  bool get contractPassed => identityPairsStable && expectedPassed;

  Map<String, Object?> toJson() => {
    'schemaName': rag2ProvenanceAttestationReportSchema,
    'schemaVersion': 1,
    'contract': rag2ProvenanceAttestationContract,
    'fixtureId': fixtureId,
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'sourceDiscoveryDecision': 'no_go',
    'storageDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'identityPairsStable': identityPairsStable,
    'results': [for (final result in results) result.toJson()],
  };

  String toMarkdown() {
    final attested = results
        .where((item) => item.decision == 'attested')
        .length;
    return '# RAG2 Provenance Attestation Replay\n\n'
        '- Contract: `$rag2ProvenanceAttestationContract`\n'
        '- Contract decision: `${contractPassed ? 'go' : 'no_go'}`\n'
        '- Source discovery decision: `no_go`\n'
        '- Storage decision: `not_evaluated`\n'
        '- Production decision: `no_go`\n'
        '- Attested / rejected cases: `$attested` / `${results.length - attested}`\n'
        '- Root-move identity pairs stable: `$identityPairsStable`\n';
  }
}

final class Rag2ProvenanceReplayOptions {
  const Rag2ProvenanceReplayOptions({
    required this.fixturePath,
    required this.outDir,
  });

  final String fixturePath;
  final String outDir;

  static Rag2ProvenanceReplayOptions? parse(List<String> args) {
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
    if (fixturePath == null || outDir == null) return null;
    return Rag2ProvenanceReplayOptions(
      fixturePath: fixturePath,
      outDir: outDir,
    );
  }
}
