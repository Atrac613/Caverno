import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/services/dart_project_tooling.dart';
import 'package:crypto/crypto.dart';

import 'rag2_batch_git_inventory_replay.dart';
import 'rag2_git_evidence_collector.dart';
import 'rag2_provenance_attestation_replay.dart';
import 'rag2_source_discovery_replay.dart';
import 'rag2_source_manifest_shadow.dart'
    show
        rag2ShadowDefaultMaxCorpusBytes,
        rag2ShadowDefaultMaxFileBytes,
        rag2ShadowDefaultMaxFiles;
import 'rag2_source_scope_measurement.dart' show rag2SourceRoleForPath;

const rag2ExplicitSourceRootsContract =
    'rag2-explicit-complete-source-roots-v1';
const rag2ExplicitSourceRootsReportSchema =
    'caverno_rag2_explicit_source_roots_replay';
const int rag2ExplicitSourceRootsMaxRoots = 16;

const rag2ExplicitSourceRootsPolicy = Rag2SourceDiscoveryPolicy(
  maxFiles: rag2ShadowDefaultMaxFiles,
  maxFileBytes: rag2ShadowDefaultMaxFileBytes,
  maxCorpusBytes: rag2ShadowDefaultMaxCorpusBytes,
);

const _usage = r'''
Usage: dart run tool/rag2_explicit_source_roots_replay.dart \
  --enable-replay \
  --project-id ID \
  --project-root PATH \
  --source-root REPO_RELATIVE_DIRECTORY \
  [--source-root REPO_RELATIVE_DIRECTORY ...]
''';

Future<void> main(List<String> args) async {
  final options = Rag2ExplicitSourceRootsOptions.parse(args);
  if (options == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  try {
    final replay = await runRag2ExplicitSourceRootsReplay(options: options);
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(replay.report.toJson()),
    );
  } on Object {
    stderr.writeln('RAG2 explicit source-roots replay failed closed.');
    exitCode = 65;
  }
}

Future<Rag2ExplicitSourceRootsReplayResult> runRag2ExplicitSourceRootsReplay({
  required Rag2ExplicitSourceRootsOptions options,
  Rag2GitProcessRunner processRunner = runRag2GitCommand,
}) async {
  options.validate();
  final project = CodingProject(
    id: options.projectId,
    name: 'RAG2 explicit source-roots replay',
    rootPath: options.projectRoot,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final base = _ReportState(
    projectIdentity: _stableIdentity('project', options.projectId),
    declarationIdentity: rag2ExplicitSourceRootsDeclarationIdentity(
      options.sourceRoots,
    ),
    sourceRootCount: options.sourceRoots.length,
  );

  late final String canonicalProjectRoot;
  try {
    final rootType = await FileSystemEntity.type(
      project.normalizedRootPath,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.directory &&
        rootType != FileSystemEntityType.link) {
      return base.report(blockers: const ['project_root_unavailable']);
    }
    canonicalProjectRoot = await Directory(
      project.normalizedRootPath,
    ).resolveSymbolicLinks();
  } on FileSystemException {
    return base.report(blockers: const ['project_root_unavailable']);
  }

  final inventory = await inventoryRag2SourceCandidates(
    project: project,
    maxFileBytes: rag2ExplicitSourceRootsPolicy.maxFileBytes,
  );
  final inventoryState = base.withInventory(inventory);
  final roots = await validateRag2ExplicitSourceRoots(
    canonicalProjectRoot: canonicalProjectRoot,
    sourceRoots: options.sourceRoots,
  );
  if (roots.blocker != null) {
    return inventoryState.report(blockers: [roots.blocker!]);
  }

  final selected = <Rag2SourceCandidate>[];
  var instructionBearingExcludedCount = 0;
  for (final candidate in inventory.candidates) {
    if (!rag2PathIsWithinExplicitRoots(candidate.path, roots.normalizedRoots)) {
      continue;
    }
    if (rag2SourceRoleForPath(candidate.path) == 'instruction_bearing') {
      instructionBearingExcludedCount++;
      continue;
    }
    selected.add(candidate);
  }
  final policyExclusionCounts = <String, int>{};
  for (final exclusion in inventory.exclusions) {
    if (!rag2PathIsWithinExplicitRoots(exclusion.path, roots.normalizedRoots)) {
      continue;
    }
    policyExclusionCounts.update(
      exclusion.reason,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final selectedInventory = Rag2SourceCandidateInventory(
    candidates: List.unmodifiable(selected),
    exclusions: const [],
    corpusBytes: selected.fold(0, (sum, candidate) => sum + candidate.bytes),
  );
  final selectedState = inventoryState.withSelection(
    inventory: selectedInventory,
    instructionBearingExcludedCount: instructionBearingExcludedCount,
    policyExclusionCounts: policyExclusionCounts,
  );
  final blockers = <String>[
    if (selected.isEmpty) 'eligible_sources_unavailable',
    ...rag2SourceInventoryViolations(
      inventory: selectedInventory,
      policy: rag2ExplicitSourceRootsPolicy,
    ),
  ];
  if (blockers.isNotEmpty) {
    return selectedState.report(blockers: blockers);
  }

  final gitCollection = await Rag2BatchGitInventoryCollector(
    project: project,
    processRunner: processRunner,
  ).collect(selected.map((candidate) => candidate.path));
  final gitState = selectedState.withGitCommandCount(
    gitCollection.commandCount,
  );
  if (gitCollection.decision != 'collected') {
    return gitState.report(
      blockers: [gitCollection.reason ?? 'batch_git_evidence_unavailable'],
    );
  }

  final discovered = await discoverRag2SourcesFromInventory(
    project: project,
    policy: rag2ExplicitSourceRootsPolicy,
    inventory: selectedInventory,
    includeChunks: false,
    gitEvidenceProvider: (path) async =>
        gitCollection.evidenceByPath[path] ??
        const Rag2GitEvidence(
          available: false,
          lsFilesExitCode: 127,
          statusPorcelain: '',
        ),
  );
  if (discovered.violations.isNotEmpty ||
      discovered.candidates.length != selected.length ||
      discovered.exclusions.isNotEmpty) {
    return gitState.report(blockers: const ['source_attestation_incomplete']);
  }
  return gitState.report(
    blockers: const [],
    admittedSourceCount: discovered.candidates.length,
    admittedSourcePaths: [
      for (final source in discovered.candidates)
        source.attestation.repoRelativePath,
    ],
  );
}

final class Rag2ExplicitSourceRootsOptions {
  const Rag2ExplicitSourceRootsOptions({
    required this.enabled,
    required this.projectId,
    required this.projectRoot,
    required this.sourceRoots,
  });

  final bool enabled;
  final String projectId;
  final String projectRoot;
  final List<String> sourceRoots;

  void validate() {
    if (!enabled || projectId.trim().isEmpty || projectRoot.trim().isEmpty) {
      throw const FormatException(
        'Explicit source-roots replay requires opt-in.',
      );
    }
    if (sourceRoots.isEmpty ||
        sourceRoots.length > rag2ExplicitSourceRootsMaxRoots) {
      throw const FormatException(
        'Explicit source-root count is out of range.',
      );
    }
  }

  static Rag2ExplicitSourceRootsOptions? parse(List<String> args) {
    var enabled = false;
    String? projectId;
    String? projectRoot;
    final sourceRoots = <String>[];
    final seenSingletons = <String>{};
    for (var index = 0; index < args.length; index++) {
      final option = args[index];
      if (option == '--enable-replay') {
        if (!seenSingletons.add(option)) return null;
        enabled = true;
        continue;
      }
      if (index + 1 >= args.length) return null;
      final value = args[++index];
      switch (option) {
        case '--project-id':
          if (!seenSingletons.add(option)) return null;
          projectId = value;
        case '--project-root':
          if (!seenSingletons.add(option)) return null;
          projectRoot = value;
        case '--source-root':
          sourceRoots.add(value);
        default:
          return null;
      }
    }
    final options = Rag2ExplicitSourceRootsOptions(
      enabled: enabled,
      projectId: projectId ?? '',
      projectRoot: projectRoot ?? '',
      sourceRoots: List.unmodifiable(sourceRoots),
    );
    try {
      options.validate();
      return options;
    } on FormatException {
      return null;
    }
  }
}

final class Rag2ExplicitSourceRootsReport {
  const Rag2ExplicitSourceRootsReport({
    required this.projectIdentity,
    required this.declarationIdentity,
    required this.inventoryMetadataIdentity,
    required this.selectedMetadataIdentity,
    required this.sourceRootCount,
    required this.inventoryCandidateFileCount,
    required this.inventoryCandidateCorpusBytes,
    required this.eligibleCandidateFileCount,
    required this.eligibleCandidateCorpusBytes,
    required this.admittedSourceCount,
    required this.instructionBearingExcludedCount,
    required this.policyExclusionCounts,
    required this.gitCommandCount,
    required this.blockers,
  });

  final String projectIdentity;
  final String declarationIdentity;
  final String? inventoryMetadataIdentity;
  final String? selectedMetadataIdentity;
  final int sourceRootCount;
  final int inventoryCandidateFileCount;
  final int inventoryCandidateCorpusBytes;
  final int eligibleCandidateFileCount;
  final int eligibleCandidateCorpusBytes;
  final int admittedSourceCount;
  final int instructionBearingExcludedCount;
  final Map<String, int> policyExclusionCounts;
  final int gitCommandCount;
  final List<String> blockers;

  bool get contractPassed => blockers.isEmpty && admittedSourceCount > 0;

  Map<String, Object?> toJson() => {
    'schemaName': rag2ExplicitSourceRootsReportSchema,
    'schemaVersion': 1,
    'contract': rag2ExplicitSourceRootsContract,
    'mode': 'opt_in_explicit_source_roots_replay',
    'evaluationMode': 'synthetic_contract_only',
    'projectSelectionAuthority': 'explicit_cli_arguments',
    'sourceScopeAuthority': 'explicit_cli_source_roots',
    'contractDecision': contractPassed ? 'go' : 'no_go',
    'scopeDecision': 'not_selected',
    'storageDecision': 'not_evaluated',
    'retrievalDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'projectIdentity': projectIdentity,
    'declarationIdentity': declarationIdentity,
    'inventoryMetadataIdentity': inventoryMetadataIdentity,
    'selectedMetadataIdentity': selectedMetadataIdentity,
    'policy': {
      'maxSourceRoots': rag2ExplicitSourceRootsMaxRoots,
      'maxFiles': rag2ExplicitSourceRootsPolicy.maxFiles,
      'maxFileBytes': rag2ExplicitSourceRootsPolicy.maxFileBytes,
      'maxCorpusBytes': rag2ExplicitSourceRootsPolicy.maxCorpusBytes,
      'instructionBearingDecision': 'excluded',
      'intraRootSamplingDecision': 'forbidden',
    },
    'sourceRootCount': sourceRootCount,
    'inventoryCandidateFileCount': inventoryCandidateFileCount,
    'inventoryCandidateCorpusBytes': inventoryCandidateCorpusBytes,
    'eligibleCandidateFileCount': eligibleCandidateFileCount,
    'eligibleCandidateCorpusBytes': eligibleCandidateCorpusBytes,
    'admittedSourceCount': admittedSourceCount,
    'instructionBearingExcludedCount': instructionBearingExcludedCount,
    'policyExclusionCounts': policyExclusionCounts,
    'gitCommandCount': gitCommandCount,
    'blockers': blockers,
  };
}

final class Rag2ExplicitSourceRootsReplayResult {
  const Rag2ExplicitSourceRootsReplayResult({
    required this.report,
    this.inventoryCandidatePaths = const [],
    this.admittedSourcePaths = const [],
  });

  final Rag2ExplicitSourceRootsReport report;
  // In-memory only. The metadata report omits inventory and admitted paths.
  final List<String> inventoryCandidatePaths;
  final List<String> admittedSourcePaths;
}

final class _ReportState {
  const _ReportState({
    required this.projectIdentity,
    required this.declarationIdentity,
    required this.sourceRootCount,
    this.inventoryMetadataIdentity,
    this.selectedMetadataIdentity,
    this.inventoryCandidateFileCount = 0,
    this.inventoryCandidateCorpusBytes = 0,
    this.eligibleCandidateFileCount = 0,
    this.eligibleCandidateCorpusBytes = 0,
    this.instructionBearingExcludedCount = 0,
    this.policyExclusionCounts = const {},
    this.gitCommandCount = 0,
    this.inventoryCandidatePaths = const [],
  });

  final String projectIdentity;
  final String declarationIdentity;
  final int sourceRootCount;
  final String? inventoryMetadataIdentity;
  final String? selectedMetadataIdentity;
  final int inventoryCandidateFileCount;
  final int inventoryCandidateCorpusBytes;
  final int eligibleCandidateFileCount;
  final int eligibleCandidateCorpusBytes;
  final int instructionBearingExcludedCount;
  final Map<String, int> policyExclusionCounts;
  final int gitCommandCount;
  final List<String> inventoryCandidatePaths;

  _ReportState withInventory(Rag2SourceCandidateInventory inventory) =>
      _ReportState(
        projectIdentity: projectIdentity,
        declarationIdentity: declarationIdentity,
        sourceRootCount: sourceRootCount,
        inventoryMetadataIdentity: _inventoryIdentity(inventory),
        inventoryCandidateFileCount: inventory.candidates.length,
        inventoryCandidateCorpusBytes: inventory.corpusBytes,
        inventoryCandidatePaths: List.unmodifiable([
          for (final candidate in inventory.candidates) candidate.path,
        ]),
      );

  _ReportState withSelection({
    required Rag2SourceCandidateInventory inventory,
    required int instructionBearingExcludedCount,
    required Map<String, int> policyExclusionCounts,
  }) => _ReportState(
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    sourceRootCount: sourceRootCount,
    inventoryMetadataIdentity: inventoryMetadataIdentity,
    selectedMetadataIdentity: _selectedIdentity(inventory),
    inventoryCandidateFileCount: inventoryCandidateFileCount,
    inventoryCandidateCorpusBytes: inventoryCandidateCorpusBytes,
    eligibleCandidateFileCount: inventory.candidates.length,
    eligibleCandidateCorpusBytes: inventory.corpusBytes,
    instructionBearingExcludedCount: instructionBearingExcludedCount,
    policyExclusionCounts: Map.unmodifiable(
      Map.fromEntries(
        policyExclusionCounts.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)),
      ),
    ),
    inventoryCandidatePaths: inventoryCandidatePaths,
  );

  _ReportState withGitCommandCount(int value) => _ReportState(
    projectIdentity: projectIdentity,
    declarationIdentity: declarationIdentity,
    sourceRootCount: sourceRootCount,
    inventoryMetadataIdentity: inventoryMetadataIdentity,
    selectedMetadataIdentity: selectedMetadataIdentity,
    inventoryCandidateFileCount: inventoryCandidateFileCount,
    inventoryCandidateCorpusBytes: inventoryCandidateCorpusBytes,
    eligibleCandidateFileCount: eligibleCandidateFileCount,
    eligibleCandidateCorpusBytes: eligibleCandidateCorpusBytes,
    instructionBearingExcludedCount: instructionBearingExcludedCount,
    policyExclusionCounts: policyExclusionCounts,
    gitCommandCount: value,
    inventoryCandidatePaths: inventoryCandidatePaths,
  );

  Rag2ExplicitSourceRootsReplayResult report({
    required List<String> blockers,
    int admittedSourceCount = 0,
    List<String> admittedSourcePaths = const [],
  }) => Rag2ExplicitSourceRootsReplayResult(
    report: Rag2ExplicitSourceRootsReport(
      projectIdentity: projectIdentity,
      declarationIdentity: declarationIdentity,
      inventoryMetadataIdentity: inventoryMetadataIdentity,
      selectedMetadataIdentity: selectedMetadataIdentity,
      sourceRootCount: sourceRootCount,
      inventoryCandidateFileCount: inventoryCandidateFileCount,
      inventoryCandidateCorpusBytes: inventoryCandidateCorpusBytes,
      eligibleCandidateFileCount: eligibleCandidateFileCount,
      eligibleCandidateCorpusBytes: eligibleCandidateCorpusBytes,
      admittedSourceCount: blockers.isEmpty ? admittedSourceCount : 0,
      instructionBearingExcludedCount: instructionBearingExcludedCount,
      policyExclusionCounts: policyExclusionCounts,
      gitCommandCount: gitCommandCount,
      blockers: List.unmodifiable(blockers),
    ),
    inventoryCandidatePaths: inventoryCandidatePaths,
    admittedSourcePaths: blockers.isEmpty
        ? List.unmodifiable(admittedSourcePaths)
        : const [],
  );
}

final class Rag2ValidatedSourceRoots {
  const Rag2ValidatedSourceRoots({required this.normalizedRoots, this.blocker});

  final List<String> normalizedRoots;
  final String? blocker;
}

Future<Rag2ValidatedSourceRoots> validateRag2ExplicitSourceRoots({
  required String canonicalProjectRoot,
  required List<String> sourceRoots,
}) async {
  final normalized = <String>[];
  for (final value in sourceRoots) {
    final root = _normalizeSourceRoot(value);
    if (root == null) {
      return const Rag2ValidatedSourceRoots(
        normalizedRoots: [],
        blocker: 'source_root_invalid',
      );
    }
    normalized.add(root);
  }
  normalized.sort();
  if (normalized.toSet().length != normalized.length) {
    return const Rag2ValidatedSourceRoots(
      normalizedRoots: [],
      blocker: 'source_root_duplicate',
    );
  }
  for (var index = 0; index < normalized.length; index++) {
    for (var other = index + 1; other < normalized.length; other++) {
      if (_rootContainsRoot(normalized[index], normalized[other])) {
        return const Rag2ValidatedSourceRoots(
          normalizedRoots: [],
          blocker: 'source_root_overlap',
        );
      }
    }
  }
  for (final root in normalized) {
    final components = root == '.' ? const <String>[] : root.split('/');
    var current = canonicalProjectRoot;
    for (final component in components) {
      current = '$current${Platform.pathSeparator}$component';
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        return const Rag2ValidatedSourceRoots(
          normalizedRoots: [],
          blocker: 'source_root_symlink_rejected',
        );
      }
      if (type == FileSystemEntityType.notFound) {
        return const Rag2ValidatedSourceRoots(
          normalizedRoots: [],
          blocker: 'source_root_unavailable',
        );
      }
      if (type != FileSystemEntityType.directory) {
        return const Rag2ValidatedSourceRoots(
          normalizedRoots: [],
          blocker: 'source_root_not_directory',
        );
      }
    }
    try {
      final canonical = await Directory(current).resolveSymbolicLinks();
      if (!DartProjectPath.isInsideRoot(canonical, canonicalProjectRoot)) {
        return const Rag2ValidatedSourceRoots(
          normalizedRoots: [],
          blocker: 'source_root_outside_project',
        );
      }
    } on FileSystemException {
      return const Rag2ValidatedSourceRoots(
        normalizedRoots: [],
        blocker: 'source_root_unavailable',
      );
    }
  }
  return Rag2ValidatedSourceRoots(
    normalizedRoots: List.unmodifiable(normalized),
  );
}

String? _normalizeSourceRoot(String value) {
  if (value != value.trim() || value.isEmpty || value.contains('\\')) {
    return null;
  }
  if (value == '.') return value;
  if (DartProjectPath.isAbsolutePath(value) ||
      value.contains(RegExp(r'[\x00\r\n]'))) {
    return null;
  }
  final parts = value.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  return value;
}

bool _rootContainsRoot(String ancestor, String descendant) =>
    ancestor == '.' || descendant.startsWith('$ancestor/');

String rag2ExplicitSourceRootsDeclarationIdentity(List<String> sourceRoots) {
  final sorted = List<String>.from(sourceRoots)..sort();
  return _stableIdentity('declaration', sorted.join('\u0000'));
}

bool rag2PathIsWithinExplicitRoots(String path, List<String> roots) {
  final normalizedPath = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  return roots.any(
    (root) =>
        root == '.' ||
        normalizedPath == root ||
        normalizedPath.startsWith('$root/'),
  );
}

String _inventoryIdentity(Rag2SourceCandidateInventory inventory) =>
    _stableIdentity(
      'inventory_metadata',
      [
        for (final candidate in inventory.candidates)
          'candidate\u0000${candidate.path}\u0000${candidate.bytes}',
        for (final exclusion in inventory.exclusions)
          'exclusion\u0000${exclusion.path}\u0000${exclusion.reason}',
      ].join('\u0001'),
    );

String _selectedIdentity(Rag2SourceCandidateInventory inventory) =>
    _stableIdentity(
      'selected_metadata',
      [
        for (final candidate in inventory.candidates)
          '${candidate.path}\u0000${candidate.bytes}',
      ].join('\u0001'),
    );

String _stableIdentity(String prefix, String value) =>
    '${prefix}_${sha256.convert(utf8.encode('$rag2ExplicitSourceRootsContract\u0000$value'))}';
