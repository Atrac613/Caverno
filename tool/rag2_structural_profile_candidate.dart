import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:crypto/crypto.dart';

import 'rag2_source_discovery_replay.dart';
import 'rag2_source_manifest_shadow.dart'
    show
        rag2ShadowDefaultMaxCorpusBytes,
        rag2ShadowDefaultMaxFileBytes,
        rag2ShadowDefaultMaxFiles;
import 'rag2_source_scope_measurement.dart';

const rag2StructuralProfileContract =
    'rag2-structural-profile-candidate-contract-v1';
const rag2StructuralProfileId = 'structural_stratified_v1';
const rag2StructuralProfileReportSchema =
    'caverno_rag2_structural_profile_candidate_report';

const rag2StructuralRoleBudgets = <String, Rag2StructuralRoleBudget>{
  'runtime_source': Rag2StructuralRoleBudget(
    maxFiles: 256,
    maxBytes: 16 * 1024 * 1024,
  ),
  'documentation': Rag2StructuralRoleBudget(
    maxFiles: 96,
    maxBytes: 4 * 1024 * 1024,
  ),
  'tests': Rag2StructuralRoleBudget(maxFiles: 96, maxBytes: 6 * 1024 * 1024),
  'tooling': Rag2StructuralRoleBudget(maxFiles: 48, maxBytes: 4 * 1024 * 1024),
  'root_sources': Rag2StructuralRoleBudget(maxFiles: 8, maxBytes: 1024 * 1024),
  'other': Rag2StructuralRoleBudget(maxFiles: 8, maxBytes: 1024 * 1024),
};

const _usage = r'''
Usage: dart run tool/rag2_structural_profile_candidate.dart \
  --enable-live-measurement \
  --project-id ID \
  --project-root PATH \
  [--max-file-bytes N]
''';

Future<void> main(List<String> args) async {
  final options = Rag2StructuralProfileOptions.parse(args);
  if (options == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2StructuralProfileCandidate(options);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } on Object {
    stderr.writeln('RAG2 structural profile measurement failed closed.');
    exitCode = 65;
  }
}

Future<Rag2StructuralProfileReport> runRag2StructuralProfileCandidate(
  Rag2StructuralProfileOptions options,
) async {
  options.validate();
  final project = CodingProject(
    id: options.projectId,
    name: 'RAG2 structural profile candidate',
    rootPath: options.projectRoot,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final inventory = await inventoryRag2SourceCandidates(
    project: project,
    maxFileBytes: options.maxFileBytes,
  );
  return Rag2StructuralProfileReport.fromInventory(
    projectId: options.projectId,
    maxFileBytes: options.maxFileBytes,
    inventory: inventory,
  );
}

List<Rag2SourceCandidate> selectRag2StructuralProfileCandidates(
  Rag2SourceCandidateInventory inventory,
) {
  final selected = <Rag2SourceCandidate>[];
  for (final entry in rag2StructuralRoleBudgets.entries) {
    final ranked =
        inventory.candidates
            .where(
              (candidate) => rag2SourceRoleForPath(candidate.path) == entry.key,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final score = _selectionScore(
              entry.key,
              left.path,
            ).compareTo(_selectionScore(entry.key, right.path));
            return score != 0 ? score : left.path.compareTo(right.path);
          });
    var selectedBytes = 0;
    var selectedFiles = 0;
    for (final candidate in ranked) {
      if (selectedFiles >= entry.value.maxFiles) break;
      if (selectedBytes + candidate.bytes > entry.value.maxBytes) continue;
      selected.add(candidate);
      selectedFiles++;
      selectedBytes += candidate.bytes;
    }
  }
  selected.sort((left, right) => left.path.compareTo(right.path));
  final aggregate = Rag2ScopeAggregate.fromCandidates(
    id: rag2StructuralProfileId,
    candidates: selected,
  );
  if (!aggregate.withinDefaultLimits) {
    throw StateError('Structural profile exceeded the default source limits.');
  }
  return List.unmodifiable(selected);
}

final class Rag2StructuralRoleBudget {
  const Rag2StructuralRoleBudget({
    required this.maxFiles,
    required this.maxBytes,
  });

  final int maxFiles;
  final int maxBytes;

  Map<String, Object?> toJson() => {'maxFiles': maxFiles, 'maxBytes': maxBytes};
}

final class Rag2StructuralProfileOptions {
  const Rag2StructuralProfileOptions({
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
      throw const FormatException(
        'Structural profile measurement requires explicit opt-in.',
      );
    }
    if (maxFileBytes <= 0 || maxFileBytes > rag2ShadowDefaultMaxFileBytes) {
      throw const FormatException(
        'Structural profile max-file-bytes exceeds the default limit.',
      );
    }
  }

  static Rag2StructuralProfileOptions? parse(List<String> args) {
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
    final options = Rag2StructuralProfileOptions(
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

final class Rag2StructuralProfileReport {
  const Rag2StructuralProfileReport({
    required this.projectIdentity,
    required this.inventoryMetadataIdentity,
    required this.maxFileBytes,
    required this.selectionIdentity,
    required this.total,
    required this.roleSelections,
  });

  factory Rag2StructuralProfileReport.fromInventory({
    required String projectId,
    required int maxFileBytes,
    required Rag2SourceCandidateInventory inventory,
  }) {
    final selected = selectRag2StructuralProfileCandidates(inventory);
    final byRole = <String, List<Rag2SourceCandidate>>{};
    for (final candidate in selected) {
      final role = rag2SourceRoleForPath(candidate.path);
      byRole.putIfAbsent(role, () => []).add(candidate);
    }
    return Rag2StructuralProfileReport(
      projectIdentity: _stableIdentity('project', projectId),
      inventoryMetadataIdentity: _stableIdentity(
        'inventory_metadata',
        [
          'maxFileBytes=$maxFileBytes',
          for (final candidate in inventory.candidates)
            'candidate\u0000${candidate.path}\u0000${candidate.bytes}',
          for (final exclusion in inventory.exclusions)
            'exclusion\u0000${exclusion.path}\u0000${exclusion.reason}',
        ].join('\u0001'),
      ),
      maxFileBytes: maxFileBytes,
      selectionIdentity: _stableIdentity(
        'selection',
        [
          for (final candidate in selected)
            '${candidate.path}\u0000${candidate.bytes}',
        ].join('\u0001'),
      ),
      total: Rag2ScopeAggregate.fromCandidates(
        id: rag2StructuralProfileId,
        candidates: selected,
      ),
      roleSelections: [
        for (final role in rag2StructuralRoleBudgets.keys)
          Rag2ScopeAggregate.fromCandidates(
            id: role,
            candidates: byRole[role] ?? const [],
          ),
      ],
    );
  }

  final String projectIdentity;
  final String inventoryMetadataIdentity;
  final int maxFileBytes;
  final String selectionIdentity;
  final Rag2ScopeAggregate total;
  final List<Rag2ScopeAggregate> roleSelections;

  Map<String, Object?> toJson() => {
    'schemaName': rag2StructuralProfileReportSchema,
    'schemaVersion': 1,
    'contract': rag2StructuralProfileContract,
    'mode': 'opt_in_live_measurement',
    'selectionBasis': 'source_role_quota_then_stable_path_hash',
    'questionFixtureUsedForSelection': false,
    'instructionBearingDecision': 'excluded',
    'scopeDecision': 'candidate_frozen_not_selected',
    'holdoutDecision': 'not_evaluated',
    'storageDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'projectIdentity': projectIdentity,
    'inventoryMetadataIdentity': inventoryMetadataIdentity,
    'selectionIdentity': selectionIdentity,
    'policy': {
      'maxFileBytes': maxFileBytes,
      'defaultMaxFiles': rag2ShadowDefaultMaxFiles,
      'defaultMaxCorpusBytes': rag2ShadowDefaultMaxCorpusBytes,
      'roleBudgets': {
        for (final entry in rag2StructuralRoleBudgets.entries)
          entry.key: entry.value.toJson(),
      },
    },
    'total': _scopeJson(total),
    'roleSelections': [for (final role in roleSelections) _scopeJson(role)],
  };
}

Map<String, Object?> _scopeJson(Rag2ScopeAggregate scope) => {
  'id': scope.id,
  'candidateFileCount': scope.candidateFileCount,
  'candidateCorpusBytes': scope.candidateCorpusBytes,
  'defaultLimitsDecision': scope.withinDefaultLimits ? 'go' : 'no_go',
};

String _selectionScore(String role, String path) => sha256
    .convert(
      utf8.encode('$rag2StructuralProfileContract\u0000$role\u0000$path'),
    )
    .toString();

String _stableIdentity(String prefix, String value) =>
    '${prefix}_${sha256.convert(utf8.encode('$rag2StructuralProfileContract\u0000$value'))}';
