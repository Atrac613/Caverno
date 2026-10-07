import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../chat/domain/entities/model_usage_role.dart';
import '../data/roadmap_snapshot_repository.dart';
import '../domain/entities/roadmap_snapshot.dart';
import '../domain/roadmap_next_task_contract.dart';
import '../domain/roadmap_next_task_extractor.dart';

/// Keeps each project's roadmap snapshot current.
///
/// The dashboard renders [cachedSnapshot] and never waits on a model
/// (invariant 6 in `docs/project_farm_roadmap.md`). [refresh] re-extracts only
/// when the document's content hash, the extractor version, or the model has
/// changed since the cached snapshot.
final class RoadmapSnapshotService {
  RoadmapSnapshotService({
    required RoadmapSnapshotRepositoryApi repository,
    required Future<bool> Function(String projectId) ensureAccess,
    required Future<String?> Function(String absolutePath) readFile,
    required RoadmapNextTaskExtractor Function() extractor,
    required String Function() model,
    DateTime Function()? now,
  }) : _repository = repository,
       _ensureAccess = ensureAccess,
       _readFile = readFile,
       _extractor = extractor,
       _model = model,
       _now = now ?? DateTime.now;

  /// Offered, in order, when the user has not chosen a roadmap document.
  static const defaultRoadmapPaths = [
    'docs/roadmap.md',
    'ROADMAP.md',
    'roadmap.md',
  ];

  final RoadmapSnapshotRepositoryApi _repository;
  final Future<bool> Function(String projectId) _ensureAccess;
  final Future<String?> Function(String absolutePath) _readFile;
  final RoadmapNextTaskExtractor Function() _extractor;
  final String Function() _model;
  final DateTime Function() _now;
  final Map<String, Future<RoadmapSnapshot?>> _inFlight = {};

  RoadmapSnapshot? cachedSnapshot(String projectId) =>
      _withPin(_repository.snapshotFor(projectId));

  String? roadmapPathFor(String projectId) =>
      _repository.roadmapPathFor(projectId);

  Future<void> setRoadmapPath(String projectId, String? roadmapPath) =>
      _repository.saveRoadmapPath(projectId, roadmapPath);

  String? pinnedTaskFor(String projectId) =>
      _repository.pinnedTaskFor(projectId);

  /// Pins a verified roadmap item as the next task, or clears the pin.
  Future<void> setPinnedTask(String projectId, String? taskId) =>
      _repository.savePinnedTask(projectId, taskId);

  /// Applies the user's pin: a pinned id that names a verified item of the
  /// snapshot becomes its next task. A pin the roadmap no longer contains is
  /// ignored rather than shown, so it never points at a stale line.
  RoadmapSnapshot? _withPin(RoadmapSnapshot? snapshot) {
    if (snapshot == null) return null;
    final pinnedId = _repository.pinnedTaskFor(snapshot.projectId);
    if (pinnedId == null || snapshot.status == RoadmapSnapshotStatus.failed) {
      return snapshot;
    }
    final item = [
      ?snapshot.recommended,
      ...snapshot.current,
      ...snapshot.blocked,
      ...snapshot.upcoming,
    ].where((item) => item.verified && item.id == pinnedId).firstOrNull;
    if (item == null) return snapshot;
    return snapshot.copyWith(
      recommended: item,
      status: RoadmapSnapshotStatus.verified,
      pinned: true,
      upcoming: snapshot.upcoming
          .where((candidate) => _itemKey(candidate) != _itemKey(item))
          .toList(),
    );
  }

  /// Brings the snapshot up to date. Returns null when the project has no
  /// readable roadmap document. Concurrent calls for one project share a run.
  Future<RoadmapSnapshot?> refresh({
    required String projectId,
    required String projectRoot,
    bool force = false,
  }) async => _withPin(
    await _refreshShared(
      projectId: projectId,
      projectRoot: projectRoot,
      force: force,
    ),
  );

  Future<RoadmapSnapshot?> _refreshShared({
    required String projectId,
    required String projectRoot,
    required bool force,
  }) {
    final running = _inFlight[projectId];
    if (running != null) return running;
    final run = _refresh(projectId, projectRoot, force).whenComplete(() {
      // A block body on purpose: `remove` returns this very future, and
      // `whenComplete` would wait on it, so the run would wait on itself.
      _inFlight.remove(projectId);
    });
    return _inFlight[projectId] = run;
  }

  Future<RoadmapSnapshot?> _refresh(
    String projectId,
    String projectRoot,
    bool force,
  ) async {
    if (!await _ensureAccess(projectId)) return null;
    final located = await _locateRoadmap(projectId, projectRoot);
    if (located == null) return null;

    final model = _model();
    final sha = sha256.convert(utf8.encode(located.text)).toString();
    final cached = _repository.snapshotFor(projectId);
    if (!force &&
        cached != null &&
        cached.roadmapPath == located.relativePath &&
        cached.cacheKey ==
            roadmapCacheKey(sha, roadmapExtractorVersion, model)) {
      return cached;
    }

    RoadmapSnapshot snapshot;
    try {
      final extraction = await ModelUsageRole.projectState.runWith(
        () => _extractor().extract(located.text),
      );
      snapshot = snapshotFromExtraction(
        extraction,
        projectId: projectId,
        roadmapPath: located.relativePath,
        contentSha256: sha,
        model: model,
        extractedAt: _now(),
      );
    } on Object catch (error) {
      snapshot = RoadmapSnapshot(
        projectId: projectId,
        roadmapPath: located.relativePath,
        contentSha256: sha,
        extractorVersion: roadmapExtractorVersion,
        model: model,
        extractedAt: _now(),
        status: RoadmapSnapshotStatus.failed,
        error: '$error',
      );
    }
    await _repository.saveSnapshot(snapshot);
    return snapshot;
  }

  Future<({String relativePath, String text})?> _locateRoadmap(
    String projectId,
    String projectRoot,
  ) async {
    final configured = _repository.roadmapPathFor(projectId);
    final candidates = configured == null ? defaultRoadmapPaths : [configured];
    for (final candidate in candidates) {
      final absolute = containedPath(projectRoot, candidate);
      if (absolute == null) continue;
      final text = await _readFile(absolute);
      if (text != null) return (relativePath: candidate, text: text);
    }
    return null;
  }
}

/// Resolves [relativePath] under [projectRoot], or null when it would escape
/// the project (an absolute path or a `..` walk).
String? containedPath(String projectRoot, String relativePath) {
  if (relativePath.trim().isEmpty || p.isAbsolute(relativePath)) return null;
  final root = p.normalize(p.absolute(projectRoot));
  final resolved = p.normalize(p.join(root, relativePath));
  return p.isWithin(root, resolved) ? resolved : null;
}

/// Turns an extraction into what the dashboard stores. Only verified current
/// and blocked items are kept; the recommendation is kept either way so an
/// unverified one can be shown as such.
RoadmapSnapshot snapshotFromExtraction(
  RoadmapExtraction extraction, {
  required String projectId,
  required String roadmapPath,
  required String contentSha256,
  required String model,
  required DateTime extractedAt,
}) {
  RoadmapItemSnapshot toSnapshot(VerifiedRoadmapItem entry) =>
      RoadmapItemSnapshot(
        id: entry.item.id,
        title: entry.item.title,
        quote: entry.item.quote,
        line: entry.verification.sourceLine,
        verified: entry.verification.kept,
      );
  List<RoadmapItemSnapshot> kept(List<VerifiedRoadmapItem> items) => [
    for (final entry in items)
      if (entry.verification.kept) toSnapshot(entry),
  ];

  final recommended = extraction.recommended.firstOrNull;
  final recommendedSnapshot = recommended == null
      ? null
      : toSnapshot(recommended);
  final current = kept(extraction.current);
  final blocked = kept(extraction.blocked);
  final seen = <String>{
    for (final item in [?recommendedSnapshot, ...current, ...blocked])
      _itemKey(item),
  };
  final upcoming = [
    for (final item in kept(extraction.upcoming))
      if (seen.add(_itemKey(item))) item,
  ];
  final status = extraction.parseFailed
      ? RoadmapSnapshotStatus.failed
      : recommended == null
      ? RoadmapSnapshotStatus.none
      : recommended.verification.kept
      ? RoadmapSnapshotStatus.verified
      : RoadmapSnapshotStatus.unverified;
  return RoadmapSnapshot(
    projectId: projectId,
    roadmapPath: roadmapPath,
    contentSha256: contentSha256,
    extractorVersion: roadmapExtractorVersion,
    model: model,
    extractedAt: extractedAt,
    status: status,
    recommended: recommendedSnapshot,
    recommendationSource:
        extraction.recommendationBasis == RoadmapRecommendationBasis.priority
        ? RoadmapRecommendationSource.priority
        : RoadmapRecommendationSource.explicit,
    current: current,
    blocked: blocked,
    upcoming: upcoming,
    droppedCount: extraction.droppedCount,
    error: extraction.parseFailed
        ? (extraction.truncated
              ? 'The answer was cut off at the output limit.'
              : 'The answer was not valid JSON.')
        : null,
  );
}

String _itemKey(RoadmapItemSnapshot item) => item.id.trim().isNotEmpty
    ? 'id:${item.id.trim()}'
    : 'line:${item.line ?? item.quote}';
