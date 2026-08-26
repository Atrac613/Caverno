import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:crypto/crypto.dart';

import 'rag2_source_discovery_replay.dart';
import 'rag2_source_manifest_shadow.dart'
    show
        rag2ShadowDefaultMaxCorpusBytes,
        rag2ShadowDefaultMaxFileBytes,
        rag2ShadowDefaultMaxFiles,
        rag2ShadowHardMaxCorpusBytes,
        rag2ShadowHardMaxFileBytes,
        rag2ShadowHardMaxFiles;

const rag2SourceScopeMeasurementContract =
    'rag2-source-scope-measurement-contract-v1';
const rag2SourceScopeMeasurementSchema =
    'caverno_rag2_source_scope_measurement';

const _usage = r'''
Usage: dart run tool/rag2_source_scope_measurement.dart \
  --enable-live-measurement \
  --project-id ID \
  --project-root PATH \
  [--max-file-bytes N]
''';

const _instructionBearingNames = <String>{
  'AGENTS.md',
  'CLAUDE.md',
  'CODEX.md',
  'FOR_ME.md',
};

const rag2SourceProfileIds = <String>[
  'runtime_only',
  'runtime_and_top_level_docs',
  'runtime_tests_and_top_level_docs',
];

Future<void> main(List<String> args) async {
  final options = Rag2SourceScopeMeasurementOptions.parse(args);
  if (options == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2SourceScopeMeasurement(options);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } on Object {
    stderr.writeln('RAG2 source scope measurement failed closed.');
    exitCode = 65;
  }
}

Future<Rag2SourceScopeMeasurementReport> runRag2SourceScopeMeasurement(
  Rag2SourceScopeMeasurementOptions options,
) async {
  options.validate();
  final project = CodingProject(
    id: options.projectId,
    name: 'RAG2 source scope measurement',
    rootPath: options.projectRoot,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final inventory = await inventoryRag2SourceCandidates(
    project: project,
    maxFileBytes: options.maxFileBytes,
  );
  return Rag2SourceScopeMeasurementReport.fromInventory(
    projectId: options.projectId,
    maxFileBytes: options.maxFileBytes,
    inventory: inventory,
  );
}

final class Rag2SourceScopeMeasurementOptions {
  const Rag2SourceScopeMeasurementOptions({
    required this.enabled,
    required this.projectId,
    required this.projectRoot,
    required this.maxFileBytes,
  });

  final bool enabled;
  final String projectId;
  final String projectRoot;
  final int maxFileBytes;

  void validate() {
    if (!enabled || projectId.trim().isEmpty || projectRoot.trim().isEmpty) {
      throw const FormatException('Live measurement requires explicit opt-in.');
    }
    if (maxFileBytes <= 0 || maxFileBytes > rag2ShadowHardMaxFileBytes) {
      throw const FormatException(
        'Live measurement max-file-bytes is out of range.',
      );
    }
  }

  static Rag2SourceScopeMeasurementOptions? parse(List<String> args) {
    var enabled = false;
    String? projectId;
    String? projectRoot;
    var maxFileBytes = rag2ShadowDefaultMaxFileBytes;
    final seen = <String>{};
    for (var index = 0; index < args.length; index++) {
      final option = args[index];
      if (!seen.add(option)) return null;
      if (option == '--enable-live-measurement') {
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
        case '--max-file-bytes':
          final parsed = int.tryParse(value);
          if (parsed == null) return null;
          maxFileBytes = parsed;
        default:
          return null;
      }
    }
    final options = Rag2SourceScopeMeasurementOptions(
      enabled: enabled,
      projectId: projectId ?? '',
      projectRoot: projectRoot ?? '',
      maxFileBytes: maxFileBytes,
    );
    try {
      options.validate();
      return options;
    } on FormatException {
      return null;
    }
  }
}

final class Rag2SourceScopeMeasurementReport {
  const Rag2SourceScopeMeasurementReport({
    required this.projectIdentity,
    required this.maxFileBytes,
    required this.total,
    required this.topLevelScopes,
    required this.sourceRoles,
    required this.comparisonProfiles,
    required this.exclusionCounts,
  });

  factory Rag2SourceScopeMeasurementReport.fromInventory({
    required String projectId,
    required int maxFileBytes,
    required Rag2SourceCandidateInventory inventory,
  }) {
    final topLevel = <String, List<Rag2SourceCandidate>>{};
    final roles = <String, List<Rag2SourceCandidate>>{};
    for (final candidate in inventory.candidates) {
      topLevel
          .putIfAbsent(_topLevelScope(candidate.path), () => [])
          .add(candidate);
      roles
          .putIfAbsent(rag2SourceRoleForPath(candidate.path), () => [])
          .add(candidate);
    }
    final exclusions = <String, int>{};
    for (final exclusion in inventory.exclusions) {
      exclusions.update(
        exclusion.reason,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return Rag2SourceScopeMeasurementReport(
      projectIdentity: _stableProjectIdentity(projectId),
      maxFileBytes: maxFileBytes,
      total: Rag2ScopeAggregate.fromCandidates(
        id: 'all_candidates',
        candidates: inventory.candidates,
      ),
      topLevelScopes: _sortedAggregates(topLevel),
      sourceRoles: _sortedAggregates(roles),
      comparisonProfiles: [
        Rag2ScopeAggregate.fromCandidates(
          id: 'runtime_only',
          candidates: inventory.candidates.where(
            (candidate) => rag2SourceProfileContainsPath(
              profileId: 'runtime_only',
              path: candidate.path,
            ),
          ),
        ),
        Rag2ScopeAggregate.fromCandidates(
          id: 'runtime_and_top_level_docs',
          candidates: inventory.candidates.where(
            (candidate) => rag2SourceProfileContainsPath(
              profileId: 'runtime_and_top_level_docs',
              path: candidate.path,
            ),
          ),
        ),
        Rag2ScopeAggregate.fromCandidates(
          id: 'runtime_tests_and_top_level_docs',
          candidates: inventory.candidates.where(
            (candidate) => rag2SourceProfileContainsPath(
              profileId: 'runtime_tests_and_top_level_docs',
              path: candidate.path,
            ),
          ),
        ),
      ],
      exclusionCounts: Map.unmodifiable(
        Map.fromEntries(
          exclusions.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        ),
      ),
    );
  }

  final String projectIdentity;
  final int maxFileBytes;
  final Rag2ScopeAggregate total;
  final List<Rag2ScopeAggregate> topLevelScopes;
  final List<Rag2ScopeAggregate> sourceRoles;
  final List<Rag2ScopeAggregate> comparisonProfiles;
  final Map<String, int> exclusionCounts;

  Map<String, Object?> toJson() => {
    'schemaName': rag2SourceScopeMeasurementSchema,
    'schemaVersion': 1,
    'contract': rag2SourceScopeMeasurementContract,
    'mode': 'opt_in_live_measurement',
    'projectSelectionAuthority': 'explicit_cli_arguments',
    'measurementDecision': 'measured',
    'scopeDecision': 'not_selected',
    'storageDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'projectIdentity': projectIdentity,
    'policy': {
      'maxFileBytes': maxFileBytes,
      'defaultMaxFiles': rag2ShadowDefaultMaxFiles,
      'defaultMaxCorpusBytes': rag2ShadowDefaultMaxCorpusBytes,
      'hardMaxFiles': rag2ShadowHardMaxFiles,
      'hardMaxCorpusBytes': rag2ShadowHardMaxCorpusBytes,
    },
    'total': total.toJson(),
    'topLevelScopes': [for (final scope in topLevelScopes) scope.toJson()],
    'sourceRoles': [for (final role in sourceRoles) role.toJson()],
    'comparisonProfiles': [
      for (final profile in comparisonProfiles) profile.toJson(),
    ],
    'exclusionCounts': exclusionCounts,
  };
}

final class Rag2ScopeAggregate {
  const Rag2ScopeAggregate({
    required this.id,
    required this.candidateFileCount,
    required this.candidateCorpusBytes,
  });

  factory Rag2ScopeAggregate.fromCandidates({
    required String id,
    required Iterable<Rag2SourceCandidate> candidates,
  }) {
    var count = 0;
    var bytes = 0;
    for (final candidate in candidates) {
      count++;
      bytes += candidate.bytes;
    }
    return Rag2ScopeAggregate(
      id: id,
      candidateFileCount: count,
      candidateCorpusBytes: bytes,
    );
  }

  final String id;
  final int candidateFileCount;
  final int candidateCorpusBytes;

  bool get withinDefaultLimits =>
      candidateFileCount <= rag2ShadowDefaultMaxFiles &&
      candidateCorpusBytes <= rag2ShadowDefaultMaxCorpusBytes;
  bool get withinHardLimits =>
      candidateFileCount <= rag2ShadowHardMaxFiles &&
      candidateCorpusBytes <= rag2ShadowHardMaxCorpusBytes;

  Map<String, Object?> toJson() => {
    'id': id,
    'candidateFileCount': candidateFileCount,
    'candidateCorpusBytes': candidateCorpusBytes,
    'defaultLimitsDecision': withinDefaultLimits ? 'go' : 'no_go',
    'hardLimitsDecision': withinHardLimits ? 'go' : 'no_go',
    'estimatedCurrentCollectorProcesses': {
      'minimumIncludingPreflight': candidateFileCount == 0
          ? 0
          : candidateFileCount * 2 + 1,
      'maximumIncludingPreflight': candidateFileCount == 0
          ? 0
          : candidateFileCount * 3 + 1,
    },
  };
}

List<Rag2ScopeAggregate> _sortedAggregates(
  Map<String, List<Rag2SourceCandidate>> grouped,
) {
  final entries = grouped.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return [
    for (final entry in entries)
      Rag2ScopeAggregate.fromCandidates(id: entry.key, candidates: entry.value),
  ];
}

String _topLevelScope(String path) {
  final separator = path.indexOf('/');
  return separator == -1 ? 'root' : path.substring(0, separator);
}

String rag2SourceRoleForPath(String path) {
  final parts = path.split('/');
  if (_instructionBearingNames.contains(parts.last)) {
    return 'instruction_bearing';
  }
  if (_isRuntimeSource(path)) return 'runtime_source';
  if (_isTestSource(path)) return 'tests';
  if (_isTopLevelDocs(path)) return 'documentation';
  if (const {'tool', 'test_driver', 'services'}.contains(parts.first)) {
    return 'tooling';
  }
  if (parts.length == 1) return 'root_sources';
  return 'other';
}

bool rag2SourceProfileContainsPath({
  required String profileId,
  required String path,
}) => switch (profileId) {
  'runtime_only' => _isRuntimeSource(path),
  'runtime_and_top_level_docs' =>
    _isRuntimeSource(path) || _isTopLevelDocs(path),
  'runtime_tests_and_top_level_docs' =>
    _isRuntimeSource(path) || _isTestSource(path) || _isTopLevelDocs(path),
  _ => throw ArgumentError.value(profileId, 'profileId'),
};

bool _isRuntimeSource(String path) {
  final parts = path.split('/');
  return parts.first == 'lib' ||
      (parts.length >= 3 && parts.first == 'packages' && parts[2] == 'lib');
}

bool _isTestSource(String path) {
  final parts = path.split('/');
  return const {'test', 'integration_test'}.contains(parts.first) ||
      (parts.length >= 3 && parts.first == 'packages' && parts[2] == 'test');
}

bool _isTopLevelDocs(String path) => path.startsWith('docs/');

String _stableProjectIdentity(String projectId) =>
    'project_${sha256.convert(utf8.encode('$rag2SourceScopeMeasurementContract\u0000$projectId'))}';
