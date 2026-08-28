import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:crypto/crypto.dart';

import 'rag2_batch_git_inventory_replay.dart';
import 'rag2_git_evidence_collector.dart';
import 'rag2_provenance_attestation_replay.dart';
import 'rag2_source_discovery_replay.dart';

const rag2SourceManifestShadowContract =
    'rag2-source-manifest-shadow-contract-v1';
const rag2SourceManifestShadowSchema = 'caverno_rag2_source_manifest_shadow';
const int rag2ShadowDefaultMaxFiles = 512;
const int rag2ShadowDefaultMaxFileBytes = 512 * 1024;
const int rag2ShadowDefaultMaxCorpusBytes = 32 * 1024 * 1024;
const int rag2ShadowHardMaxFiles = 2048;
const int rag2ShadowHardMaxFileBytes = 1024 * 1024;
const int rag2ShadowHardMaxCorpusBytes = 128 * 1024 * 1024;

const _usage = '''
Usage: dart run tool/rag2_source_manifest_shadow.dart \\
  --enable-live-shadow \\
  --project-id ID \\
  --project-root PATH \\
  [--max-files N] \\
  [--max-file-bytes N] \\
  [--max-corpus-bytes N]
''';

Future<void> main(List<String> args) async {
  final options = Rag2SourceManifestShadowOptions.parse(args);
  if (options == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2SourceManifestShadow(options: options);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } on Object {
    stderr.writeln('RAG2 source manifest shadow failed closed.');
    exitCode = 65;
  }
}

Future<Rag2SourceManifestShadowReport> runRag2SourceManifestShadow({
  required Rag2SourceManifestShadowOptions options,
  Rag2GitProcessRunner processRunner = runRag2GitCommand,
}) async {
  options.validate();
  final project = CodingProject(
    id: options.projectId,
    name: 'RAG2 source manifest shadow',
    rootPath: options.projectRoot,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final inventory = await inventoryRag2SourceCandidates(
    project: project,
    maxFileBytes: options.policy.maxFileBytes,
  );
  final evidenceFailures = <String, String>{};
  final evidenceByPath = <String, Rag2GitEvidence>{};
  final violations = rag2SourceInventoryViolations(
    inventory: inventory,
    policy: options.policy,
  );
  if (violations.isEmpty && inventory.candidates.isNotEmpty) {
    final collection = await Rag2BatchGitInventoryCollector(
      project: project,
      processRunner: processRunner,
    ).collect(inventory.candidates.map((candidate) => candidate.path));
    if (collection.decision == 'collected') {
      evidenceByPath.addAll(collection.evidenceByPath);
    } else {
      final reason = collection.reason ?? 'batch_git_evidence_unavailable';
      for (final candidate in inventory.candidates) {
        evidenceFailures[candidate.path] = reason;
      }
    }
  }
  final result = await discoverRag2SourcesFromInventory(
    project: project,
    policy: options.policy,
    inventory: inventory,
    includeChunks: false,
    gitEvidenceProvider: (path) async {
      final evidence = evidenceByPath[path];
      if (evidence != null) return evidence;
      evidenceFailures.putIfAbsent(path, () => 'batch_git_evidence_missing');
      return const Rag2GitEvidence(
        available: false,
        lsFilesExitCode: 127,
        statusPorcelain: '',
      );
    },
  );
  return Rag2SourceManifestShadowReport(
    projectIdentity: _stableProjectIdentity(options.projectId),
    policy: options.policy,
    result: result,
    evidenceFailures: evidenceFailures,
  );
}

final class Rag2SourceManifestShadowOptions {
  const Rag2SourceManifestShadowOptions({
    required this.enabled,
    required this.projectId,
    required this.projectRoot,
    required this.policy,
  });

  final bool enabled;
  final String projectId;
  final String projectRoot;
  final Rag2SourceDiscoveryPolicy policy;

  void validate() {
    if (!enabled || projectId.trim().isEmpty || projectRoot.trim().isEmpty) {
      throw const FormatException('Live shadow requires explicit opt-in.');
    }
    if (policy.maxFiles <= 0 || policy.maxFiles > rag2ShadowHardMaxFiles) {
      throw const FormatException('Live shadow max-files is out of range.');
    }
    if (policy.maxFileBytes <= 0 ||
        policy.maxFileBytes > rag2ShadowHardMaxFileBytes) {
      throw const FormatException(
        'Live shadow max-file-bytes is out of range.',
      );
    }
    if (policy.maxCorpusBytes <= 0 ||
        policy.maxCorpusBytes > rag2ShadowHardMaxCorpusBytes) {
      throw const FormatException(
        'Live shadow max-corpus-bytes is out of range.',
      );
    }
  }

  static Rag2SourceManifestShadowOptions? parse(List<String> args) {
    var enabled = false;
    String? projectId;
    String? projectRoot;
    var maxFiles = rag2ShadowDefaultMaxFiles;
    var maxFileBytes = rag2ShadowDefaultMaxFileBytes;
    var maxCorpusBytes = rag2ShadowDefaultMaxCorpusBytes;
    final seen = <String>{};
    for (var index = 0; index < args.length; index++) {
      final option = args[index];
      if (!seen.add(option)) return null;
      if (option == '--enable-live-shadow') {
        enabled = true;
        continue;
      }
      if (index + 1 >= args.length) return null;
      final value = args[++index];
      switch (option) {
        case '--project-id':
          projectId = value;
        case '--project-root':
          projectRoot = value;
        case '--max-files':
          final parsed = int.tryParse(value);
          if (parsed == null) return null;
          maxFiles = parsed;
        case '--max-file-bytes':
          final parsed = int.tryParse(value);
          if (parsed == null) return null;
          maxFileBytes = parsed;
        case '--max-corpus-bytes':
          final parsed = int.tryParse(value);
          if (parsed == null) return null;
          maxCorpusBytes = parsed;
        default:
          return null;
      }
    }
    final options = Rag2SourceManifestShadowOptions(
      enabled: enabled,
      projectId: projectId ?? '',
      projectRoot: projectRoot ?? '',
      policy: Rag2SourceDiscoveryPolicy(
        maxFiles: maxFiles,
        maxFileBytes: maxFileBytes,
        maxCorpusBytes: maxCorpusBytes,
      ),
    );
    try {
      options.validate();
      return options;
    } on FormatException {
      return null;
    }
  }
}

final class Rag2SourceManifestShadowReport {
  const Rag2SourceManifestShadowReport({
    required this.projectIdentity,
    required this.policy,
    required this.result,
    required this.evidenceFailures,
  });

  final String projectIdentity;
  final Rag2SourceDiscoveryPolicy policy;
  final Rag2SourceDiscoveryResult result;
  final Map<String, String> evidenceFailures;

  bool get manifestPassed =>
      result.violations.isEmpty &&
      result.exclusions.every(
        (item) => _policyExclusionReasons.contains(item.reason),
      );

  Map<String, Object?> toJson() => {
    'schemaName': rag2SourceManifestShadowSchema,
    'schemaVersion': 1,
    'contract': rag2SourceManifestShadowContract,
    'mode': 'opt_in_live_shadow',
    'projectSelectionAuthority': 'explicit_cli_arguments',
    'manifestDecision': manifestPassed ? 'go' : 'no_go',
    'storageDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'projectIdentity': projectIdentity,
    'policy': {
      'maxFiles': policy.maxFiles,
      'maxFileBytes': policy.maxFileBytes,
      'maxCorpusBytes': policy.maxCorpusBytes,
    },
    'candidateFileCount': result.candidateFileCount,
    'candidateCorpusBytes': result.candidateCorpusBytes,
    'selectedSourceCount': result.candidates.length,
    'sources': [for (final source in result.candidates) _sourceJson(source)],
    'exclusions': [
      for (final item in result.exclusions)
        {...item.toJson(), 'evidenceFailure': ?evidenceFailures[item.path]},
    ],
    'violations': result.violations,
  };
}

const _policyExclusionReasons = <String>{
  'file_bytes_exceeded',
  'generated_directory',
  'generated_file',
  'symlink_rejected',
  'unsupported_extension',
};

Map<String, Object?> _sourceJson(Rag2DiscoveredSource source) => {
  'repoRelativePath': source.attestation.repoRelativePath,
  'sourceIdentity': source.attestation.sourceIdentity,
  'sourceKind': source.sourceKind,
  'sourceTrust': source.attestation.sourceTrust,
  'worktreeState': source.attestation.worktreeState,
  'revisionKind': source.attestation.revisionKind,
  'revision': source.attestation.revision,
  'contentHash': source.attestation.contentHash,
  'bytes': source.bytes,
};

String _stableProjectIdentity(String projectId) =>
    'project_${sha256.convert(utf8.encode('$rag2SourceManifestShadowContract\u0000$projectId'))}';
