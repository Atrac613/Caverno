import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/project_read_path_fence.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:crypto/crypto.dart';

import 'rag2_knowledge_object_replay.dart' show validateRag2RepoRelativePath;
import 'rag2_source_discovery_replay.dart';
import 'rag2_source_manifest_shadow.dart'
    show
        rag2ShadowDefaultMaxCorpusBytes,
        rag2ShadowDefaultMaxFileBytes,
        rag2ShadowDefaultMaxFiles,
        rag2ShadowHardMaxCorpusBytes,
        rag2ShadowHardMaxFileBytes,
        rag2ShadowHardMaxFiles;
import 'rag2_source_scope_measurement.dart';
import 'rag2_structural_profile_candidate.dart';

const rag2SourceRoleCoverageContract = 'rag2-source-role-coverage-contract-v2';
const rag2SourceRoleCoverageFixtureSchema =
    'caverno_rag2_source_role_coverage_fixture';
const rag2SourceRoleCoverageReportSchema =
    'caverno_rag2_source_role_coverage_report';

const _maxFixtureBytes = 64 * 1024;
const _maxQuestions = 64;
const _maxEvidenceSourcesPerQuestion = 8;
const _maxMarkersPerEvidenceSource = 8;
const _maxQuestionLength = 512;
const _maxMarkerLength = 256;
const _allCandidatesControlId = 'all_candidates_control';

const _usage = r'''
Usage: dart run tool/rag2_source_role_coverage_replay.dart \
  --enable-live-replay \
  --project-id ID \
  --project-root PATH \
  --fixture PATH \
  [--max-file-bytes N]
''';

Future<void> main(List<String> args) async {
  final options = Rag2SourceRoleCoverageOptions.parse(args);
  if (options == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2SourceRoleCoverageReplay(options);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } on Object {
    stderr.writeln('RAG2 source-role coverage replay failed closed.');
    exitCode = 65;
  }
}

Future<Rag2SourceRoleCoverageReport> runRag2SourceRoleCoverageReplay(
  Rag2SourceRoleCoverageOptions options, {
  Future<void> Function()? beforeEvidenceValidation,
}) async {
  options.validate();
  final fixture = await Rag2SourceRoleCoverageFixture.load(
    File(options.fixturePath),
  );
  final project = CodingProject(
    id: options.projectId,
    name: 'RAG2 source-role coverage replay',
    rootPath: options.projectRoot,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  final inventory = await inventoryRag2SourceCandidates(
    project: project,
    maxFileBytes: options.maxFileBytes,
  );
  final candidatesByPath = {
    for (final candidate in inventory.candidates) candidate.path: candidate,
  };
  await beforeEvidenceValidation?.call();
  final evidenceFingerprints = <String>[];
  for (final question in fixture.questions) {
    for (final source in question.evidenceSources) {
      final candidate = candidatesByPath[source.evidencePath];
      if (candidate == null) {
        throw const FormatException(
          'Coverage evidence is outside the bounded source inventory.',
        );
      }
      if (rag2SourceRoleForPath(candidate.path) !=
          question.expectedSourceRole) {
        throw const FormatException('Coverage evidence source role drifted.');
      }
      evidenceFingerprints.add(
        await _validateEvidenceSource(
          projectRoot: project.normalizedRootPath,
          candidate: candidate,
          source: source,
          maxFileBytes: options.maxFileBytes,
        ),
      );
    }
  }

  final profileCandidates = <String, List<Rag2SourceCandidate>>{
    _allCandidatesControlId: inventory.candidates,
    for (final profileId in rag2SourceProfileIds)
      profileId: inventory.candidates
          .where(
            (candidate) => rag2SourceProfileContainsPath(
              profileId: profileId,
              path: candidate.path,
            ),
          )
          .toList(growable: false),
    rag2StructuralProfileId: selectRag2StructuralProfileCandidates(inventory),
  };
  final profileCoverage = <Rag2SourceProfileCoverage>[];
  for (final entry in profileCandidates.entries) {
    final admittedPaths = {for (final candidate in entry.value) candidate.path};
    profileCoverage.add(
      Rag2SourceProfileCoverage.fromQuestions(
        profileId: entry.key,
        profileKind: entry.key == _allCandidatesControlId
            ? 'oracle_control'
            : entry.key == rag2StructuralProfileId
            ? 'structural_candidate'
            : 'comparison_profile',
        candidates: entry.value,
        questions: fixture.questions,
        admittedPaths: admittedPaths,
      ),
    );
  }

  final control = profileCoverage.first;
  if (control.coveredQuestionCount != fixture.questions.length) {
    throw const FormatException('All-candidates oracle control is incomplete.');
  }
  return Rag2SourceRoleCoverageReport(
    projectIdentity: _stableIdentity('project', options.projectId),
    fixtureIdentity: fixture.identity,
    inventoryMetadataIdentity: _inventoryMetadataIdentity(
      inventory,
      options.maxFileBytes,
    ),
    validatedEvidenceIdentity: _stableIdentity(
      'evidence',
      (evidenceFingerprints..sort()).join('\u0000'),
    ),
    maxFileBytes: options.maxFileBytes,
    questionCount: fixture.questions.length,
    validatedEvidenceFileCount: fixture.questions
        .expand((question) => question.evidenceSources)
        .map((source) => source.evidencePath)
        .toSet()
        .length,
    requiredMarkerCount: fixture.questions
        .expand((question) => question.evidenceSources)
        .fold(0, (count, source) => count + source.requiredMarkers.length),
    sourceRoleQuestionCounts: _sourceRoleQuestionCounts(fixture.questions),
    profiles: List.unmodifiable(profileCoverage),
  );
}

final class Rag2SourceRoleCoverageOptions {
  const Rag2SourceRoleCoverageOptions({
    required this.enabled,
    required this.projectId,
    required this.projectRoot,
    required this.fixturePath,
    required this.maxFileBytes,
  });

  final bool enabled;
  final String projectId;
  final String projectRoot;
  final String fixturePath;
  final int maxFileBytes;

  void validate() {
    if (!enabled ||
        projectId.trim().isEmpty ||
        projectRoot.trim().isEmpty ||
        fixturePath.trim().isEmpty) {
      throw const FormatException('Live replay requires explicit inputs.');
    }
    if (maxFileBytes <= 0 || maxFileBytes > rag2ShadowHardMaxFileBytes) {
      throw const FormatException('Replay max-file-bytes is out of range.');
    }
  }

  static Rag2SourceRoleCoverageOptions? parse(List<String> args) {
    var enabled = false;
    String? projectId;
    String? projectRoot;
    String? fixturePath;
    var maxFileBytes = rag2ShadowDefaultMaxFileBytes;
    final seen = <String>{};
    for (var index = 0; index < args.length; index++) {
      final option = args[index];
      if (!seen.add(option)) return null;
      if (option == '--enable-live-replay') {
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
        case '--fixture':
          fixturePath = value;
        case '--max-file-bytes':
          final parsed = int.tryParse(value);
          if (parsed == null) return null;
          maxFileBytes = parsed;
        default:
          return null;
      }
    }
    final options = Rag2SourceRoleCoverageOptions(
      enabled: enabled,
      projectId: projectId ?? '',
      projectRoot: projectRoot ?? '',
      fixturePath: fixturePath ?? '',
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

final class Rag2SourceRoleCoverageFixture {
  const Rag2SourceRoleCoverageFixture({
    required this.fixtureId,
    required this.identity,
    required this.questions,
  });

  static Future<Rag2SourceRoleCoverageFixture> load(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > _maxFixtureBytes) {
      throw const FormatException('Coverage fixture size is out of range.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?> ||
        decoded['schemaName'] != rag2SourceRoleCoverageFixtureSchema ||
        decoded['schemaVersion'] != 2) {
      throw const FormatException('Coverage fixture schema is invalid.');
    }
    final fixtureId = decoded['fixtureId'];
    final rawQuestions = decoded['questions'];
    if (fixtureId is! String ||
        !_validId(fixtureId) ||
        rawQuestions is! List<Object?> ||
        rawQuestions.isEmpty ||
        rawQuestions.length > _maxQuestions) {
      throw const FormatException('Coverage fixture contents are invalid.');
    }
    final questions = <Rag2SourceRoleQuestion>[];
    final ids = <String>{};
    final evidencePaths = <String>{};
    for (final rawQuestion in rawQuestions) {
      if (rawQuestion is! Map<String, Object?>) {
        throw const FormatException('Coverage question is invalid.');
      }
      final question = Rag2SourceRoleQuestion.fromJson(rawQuestion);
      if (!ids.add(question.id)) {
        throw const FormatException('Coverage question IDs must be unique.');
      }
      for (final source in question.evidenceSources) {
        if (!evidencePaths.add(source.evidencePath)) {
          throw const FormatException(
            'Coverage evidence paths must be unique across questions.',
          );
        }
      }
      questions.add(question);
    }
    return Rag2SourceRoleCoverageFixture(
      fixtureId: fixtureId,
      identity: 'fixture_${sha256.convert(bytes)}',
      questions: List.unmodifiable(questions),
    );
  }

  final String fixtureId;
  final String identity;
  final List<Rag2SourceRoleQuestion> questions;
}

final class Rag2SourceRoleQuestion {
  const Rag2SourceRoleQuestion({
    required this.id,
    required this.question,
    required this.evidenceSources,
    required this.expectedSourceRole,
  });

  factory Rag2SourceRoleQuestion.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final question = json['question'];
    final rawEvidenceSources = json['evidenceSources'];
    final expectedSourceRole = json['expectedSourceRole'];
    if (id is! String ||
        !_validId(id) ||
        question is! String ||
        question.trim().isEmpty ||
        question.length > _maxQuestionLength ||
        rawEvidenceSources is! List<Object?> ||
        rawEvidenceSources.isEmpty ||
        rawEvidenceSources.length > _maxEvidenceSourcesPerQuestion ||
        expectedSourceRole is! String) {
      throw const FormatException('Coverage question fields are invalid.');
    }
    if (!const {
      'runtime_source',
      'tests',
      'documentation',
      'tooling',
      'root_sources',
      'other',
    }.contains(expectedSourceRole)) {
      throw const FormatException('Coverage question source role is invalid.');
    }
    return Rag2SourceRoleQuestion(
      id: id,
      question: question,
      evidenceSources: List.unmodifiable(
        rawEvidenceSources.map((rawSource) {
          if (rawSource is! Map<String, Object?>) {
            throw const FormatException('Coverage evidence source is invalid.');
          }
          return Rag2SourceRoleEvidenceSource.fromJson(rawSource);
        }),
      ),
      expectedSourceRole: expectedSourceRole,
    );
  }

  final String id;
  final String question;
  final List<Rag2SourceRoleEvidenceSource> evidenceSources;
  final String expectedSourceRole;
}

final class Rag2SourceRoleEvidenceSource {
  const Rag2SourceRoleEvidenceSource({
    required this.evidencePath,
    required this.requiredMarkers,
  });

  factory Rag2SourceRoleEvidenceSource.fromJson(Map<String, Object?> json) {
    final evidencePath = json['evidencePath'];
    final rawMarkers = json['requiredMarkers'];
    if (evidencePath is! String ||
        rawMarkers is! List<Object?> ||
        rawMarkers.isEmpty ||
        rawMarkers.length > _maxMarkersPerEvidenceSource ||
        rawMarkers.any(
          (marker) =>
              marker is! String ||
              marker.isEmpty ||
              marker.length > _maxMarkerLength,
        )) {
      throw const FormatException(
        'Coverage evidence source fields are invalid.',
      );
    }
    validateRag2RepoRelativePath(evidencePath);
    final markers = rawMarkers.cast<String>();
    if (markers.toSet().length != markers.length) {
      throw const FormatException('Coverage evidence markers must be unique.');
    }
    return Rag2SourceRoleEvidenceSource(
      evidencePath: evidencePath,
      requiredMarkers: List.unmodifiable(markers),
    );
  }

  final String evidencePath;
  final List<String> requiredMarkers;
}

final class Rag2SourceRoleCoverageReport {
  const Rag2SourceRoleCoverageReport({
    required this.projectIdentity,
    required this.fixtureIdentity,
    required this.inventoryMetadataIdentity,
    required this.validatedEvidenceIdentity,
    required this.maxFileBytes,
    required this.questionCount,
    required this.validatedEvidenceFileCount,
    required this.requiredMarkerCount,
    required this.sourceRoleQuestionCounts,
    required this.profiles,
  });

  final String projectIdentity;
  final String fixtureIdentity;
  final String inventoryMetadataIdentity;
  final String validatedEvidenceIdentity;
  final int maxFileBytes;
  final int questionCount;
  final int validatedEvidenceFileCount;
  final int requiredMarkerCount;
  final Map<String, int> sourceRoleQuestionCounts;
  final List<Rag2SourceProfileCoverage> profiles;

  Map<String, Object?> toJson() => {
    'schemaName': rag2SourceRoleCoverageReportSchema,
    'schemaVersion': 2,
    'contract': rag2SourceRoleCoverageContract,
    'mode': 'opt_in_live_oracle_replay',
    'evaluationMode': 'oracle_required_source_coverage_only',
    'projectSelectionAuthority': 'explicit_cli_arguments',
    'evaluationDecision': 'measured',
    'scopeDecision': 'not_selected',
    'storageDecision': 'not_evaluated',
    'productionDecision': 'no_go',
    'projectIdentity': projectIdentity,
    'fixtureIdentity': fixtureIdentity,
    'inventoryMetadataIdentity': inventoryMetadataIdentity,
    'validatedEvidenceIdentity': validatedEvidenceIdentity,
    'policy': {
      'maxFileBytes': maxFileBytes,
      'defaultMaxFiles': rag2ShadowDefaultMaxFiles,
      'defaultMaxCorpusBytes': rag2ShadowDefaultMaxCorpusBytes,
      'hardMaxFiles': rag2ShadowHardMaxFiles,
      'hardMaxCorpusBytes': rag2ShadowHardMaxCorpusBytes,
      'admittedSourceExtensions': ['.dart', '.md'],
      'unsupportedSourceFamiliesDecision': 'deferred_no_go',
    },
    'questionCount': questionCount,
    'validatedEvidenceFileCount': validatedEvidenceFileCount,
    'requiredMarkerCount': requiredMarkerCount,
    'sourceRoleQuestionCounts': sourceRoleQuestionCounts,
    'profiles': [for (final profile in profiles) profile.toJson()],
  };
}

final class Rag2SourceProfileCoverage {
  const Rag2SourceProfileCoverage({
    required this.profileId,
    required this.profileKind,
    required this.scope,
    required this.questionCount,
    required this.coveredQuestionCount,
    required this.sourceRoleCoverage,
  });

  factory Rag2SourceProfileCoverage.fromQuestions({
    required String profileId,
    required String profileKind,
    required List<Rag2SourceCandidate> candidates,
    required List<Rag2SourceRoleQuestion> questions,
    required Set<String> admittedPaths,
  }) {
    final byRole = <String, List<Rag2SourceRoleQuestion>>{};
    for (final question in questions) {
      byRole.putIfAbsent(question.expectedSourceRole, () => []).add(question);
    }
    return Rag2SourceProfileCoverage(
      profileId: profileId,
      profileKind: profileKind,
      scope: Rag2ScopeAggregate.fromCandidates(
        id: profileId,
        candidates: candidates,
      ),
      questionCount: questions.length,
      coveredQuestionCount: questions
          .where(
            (question) => question.evidenceSources.every(
              (source) => admittedPaths.contains(source.evidencePath),
            ),
          )
          .length,
      sourceRoleCoverage: [
        for (final entry
            in byRole.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key)))
          Rag2RoleQuestionCoverage(
            sourceRole: entry.key,
            questionCount: entry.value.length,
            coveredQuestionCount: entry.value
                .where(
                  (question) => question.evidenceSources.every(
                    (source) => admittedPaths.contains(source.evidencePath),
                  ),
                )
                .length,
          ),
      ],
    );
  }

  final String profileId;
  final String profileKind;
  final Rag2ScopeAggregate scope;
  final int questionCount;
  final int coveredQuestionCount;
  final List<Rag2RoleQuestionCoverage> sourceRoleCoverage;

  bool get complete => coveredQuestionCount == questionCount;
  List<String> get blockers => [
    if (!complete) 'question_coverage_incomplete',
    if (!scope.withinDefaultLimits) 'default_limits_exceeded',
    if (!scope.withinHardLimits) 'hard_limits_exceeded',
  ];

  Map<String, Object?> toJson() => {
    'id': profileId,
    'kind': profileKind,
    'candidateFileCount': scope.candidateFileCount,
    'candidateCorpusBytes': scope.candidateCorpusBytes,
    'defaultLimitsDecision': scope.withinDefaultLimits ? 'go' : 'no_go',
    'hardLimitsDecision': scope.withinHardLimits ? 'go' : 'no_go',
    'questionCount': questionCount,
    'coveredQuestionCount': coveredQuestionCount,
    'coverageRatio': questionCount == 0
        ? 0.0
        : coveredQuestionCount / questionCount,
    'scopeEligibilityDecision': blockers.isEmpty ? 'go' : 'no_go',
    'blockers': blockers,
    'sourceRoleCoverage': [
      for (final coverage in sourceRoleCoverage) coverage.toJson(),
    ],
  };
}

final class Rag2RoleQuestionCoverage {
  const Rag2RoleQuestionCoverage({
    required this.sourceRole,
    required this.questionCount,
    required this.coveredQuestionCount,
  });

  final String sourceRole;
  final int questionCount;
  final int coveredQuestionCount;

  Map<String, Object?> toJson() => {
    'sourceRole': sourceRole,
    'questionCount': questionCount,
    'coveredQuestionCount': coveredQuestionCount,
  };
}

Map<String, int> _sourceRoleQuestionCounts(
  List<Rag2SourceRoleQuestion> questions,
) {
  final counts = <String, int>{};
  for (final question in questions) {
    counts.update(
      question.expectedSourceRole,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  return Map.unmodifiable(
    Map.fromEntries(
      counts.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    ),
  );
}

bool _validId(String value) =>
    RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(value);

String _stableIdentity(String prefix, String value) =>
    '${prefix}_${sha256.convert(utf8.encode('$rag2SourceRoleCoverageContract\u0000$value'))}';

Future<String> _validateEvidenceSource({
  required String projectRoot,
  required Rag2SourceCandidate candidate,
  required Rag2SourceRoleEvidenceSource source,
  required int maxFileBytes,
}) async {
  const fence = ProjectReadPathFence();
  final before = await fence.authorize(
    projectRoot: projectRoot,
    rawPath: source.evidencePath,
  );
  if (!before.isAllowed) {
    throw const FormatException('Coverage evidence read is not authorized.');
  }
  final bytes = await _readBounded(File(before.canonicalPath!), maxFileBytes);
  if (bytes == null || bytes.length != candidate.bytes || bytes.contains(0)) {
    throw const FormatException('Coverage evidence changed after inventory.');
  }
  late final String content;
  try {
    content = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const FormatException('Coverage evidence is not UTF-8 text.');
  }
  if (source.requiredMarkers.any((marker) => !content.contains(marker))) {
    throw const FormatException('Coverage evidence marker is unavailable.');
  }
  final after = await fence.authorize(
    projectRoot: projectRoot,
    rawPath: source.evidencePath,
  );
  if (!after.isAllowed || after.canonicalPath != before.canonicalPath) {
    throw const FormatException('Coverage evidence path changed during read.');
  }
  return [source.evidencePath, sha256.convert(bytes).toString()].join('\u0000');
}

Future<List<int>?> _readBounded(File file, int maxFileBytes) async {
  final bytes = <int>[];
  await for (final chunk in file.openRead(0, maxFileBytes + 1)) {
    bytes.addAll(chunk);
    if (bytes.length > maxFileBytes) return null;
  }
  return bytes;
}

String _inventoryMetadataIdentity(
  Rag2SourceCandidateInventory inventory,
  int maxFileBytes,
) {
  final records = <String>[
    'maxFileBytes=$maxFileBytes',
    for (final candidate in inventory.candidates)
      'candidate\u0000${candidate.path}\u0000${candidate.bytes}',
    for (final exclusion in inventory.exclusions)
      'exclusion\u0000${exclusion.path}\u0000${exclusion.reason}',
  ];
  return _stableIdentity('inventory_metadata', records.join('\u0001'));
}
