import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_source_discovery_replay.dart';
import '../../tool/rag2_structural_profile_candidate.dart';

void main() {
  test('selects deterministic role quotas within default limits', () {
    final inventory = _inventory();
    final selected = selectRag2StructuralProfileCandidates(inventory);
    final counts = <String, int>{};
    for (final candidate in selected) {
      final role = _roleForSyntheticPath(candidate.path);
      counts.update(role, (count) => count + 1, ifAbsent: () => 1);
    }

    expect(selected, hasLength(509));
    expect(counts, {
      'runtime_source': 256,
      'documentation': 96,
      'tests': 96,
      'tooling': 48,
      'root_sources': 6,
      'other': 7,
    });
    expect(
      selected.every((candidate) => candidate.path != 'AGENTS.md'),
      isTrue,
    );
    expect(
      selected.map((candidate) => candidate.path).toSet(),
      selectRag2StructuralProfileCandidates(
        _inventory(reverse: true),
      ).map((candidate) => candidate.path).toSet(),
    );
  });

  test('enforces independent role byte budgets', () {
    final candidates = [
      for (var index = 0; index < 256; index++)
        _candidate('lib/runtime_$index.dart', 100 * 1024),
    ];
    final selected = selectRag2StructuralProfileCandidates(
      Rag2SourceCandidateInventory(
        candidates: candidates,
        exclusions: const [],
        corpusBytes: candidates.fold(0, (sum, item) => sum + item.bytes),
      ),
    );
    final bytes = selected.fold(0, (sum, item) => sum + item.bytes);

    expect(selected, hasLength(163));
    expect(bytes, lessThanOrEqualTo(16 * 1024 * 1024));
  });

  test('emits aggregate-only frozen candidate metadata', () {
    final report = Rag2StructuralProfileReport.fromInventory(
      projectId: 'private-project-id',
      maxFileBytes: 512 * 1024,
      inventory: _inventory(),
    );
    final json = jsonEncode(report.toJson());

    expect(report.total.candidateFileCount, 509);
    expect(report.total.withinDefaultLimits, isTrue);
    expect(report.inventoryMetadataIdentity, startsWith('inventory_metadata_'));
    expect(report.toJson()['scopeDecision'], 'candidate_frozen_not_selected');
    expect(report.toJson()['holdoutDecision'], 'not_evaluated');
    expect(report.toJson()['questionFixtureUsedForSelection'], isFalse);
    for (final forbidden in [
      'private-project-id',
      'lib/runtime_0.dart',
      'private-excluded.md',
      'AGENTS.md',
    ]) {
      expect(json, isNot(contains(forbidden)));
    }
  });

  test('freezes budgets at the default file and corpus ceilings', () {
    expect(
      rag2StructuralRoleBudgets.values.fold(
        0,
        (sum, budget) => sum + budget.maxFiles,
      ),
      512,
    );
    expect(
      rag2StructuralRoleBudgets.values.fold(
        0,
        (sum, budget) => sum + budget.maxBytes,
      ),
      32 * 1024 * 1024,
    );
  });

  test('requires explicit inputs and the default per-file ceiling', () {
    expect(
      Rag2StructuralProfileOptions.parse([
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
      ]),
      isNull,
    );
    expect(
      Rag2StructuralProfileOptions.parse([
        '--enable-live-measurement',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
        '--max-file-bytes',
        '${512 * 1024 + 1}',
      ]),
      isNull,
    );
    expect(
      Rag2StructuralProfileOptions.parse([
        '--enable-live-measurement',
        '--project-id',
        'project',
        '--project-root',
        '/tmp/project',
      ]),
      isNotNull,
    );
  });
}

Rag2SourceCandidateInventory _inventory({bool reverse = false}) {
  final candidates = <Rag2SourceCandidate>[
    for (var index = 0; index < 300; index++)
      _candidate('lib/runtime_$index.dart', 10),
    for (var index = 0; index < 120; index++)
      _candidate('docs/guide_$index.md', 10),
    for (var index = 0; index < 120; index++)
      _candidate('test/runtime_${index}_test.dart', 10),
    for (var index = 0; index < 60; index++)
      _candidate('tool/measure_$index.dart', 10),
    for (var index = 0; index < 6; index++) _candidate('ROOT_$index.md', 10),
    for (var index = 0; index < 7; index++)
      _candidate('assets/note_$index.md', 10),
    _candidate('AGENTS.md', 10),
  ];
  if (reverse) {
    candidates.replaceRange(0, candidates.length, candidates.reversed);
  }
  return Rag2SourceCandidateInventory(
    candidates: candidates,
    exclusions: const [
      Rag2DiscoveryExclusion(
        path: 'private-excluded.md',
        reason: 'unsupported_extension',
      ),
    ],
    corpusBytes: candidates.fold(0, (sum, item) => sum + item.bytes),
  );
}

Rag2SourceCandidate _candidate(String path, int bytes) =>
    Rag2SourceCandidate(path: path, file: File(path), bytes: bytes);

String _roleForSyntheticPath(String path) {
  if (path.startsWith('lib/')) return 'runtime_source';
  if (path.startsWith('docs/')) return 'documentation';
  if (path.startsWith('test/')) return 'tests';
  if (path.startsWith('tool/')) return 'tooling';
  if (!path.contains('/')) return 'root_sources';
  return 'other';
}
