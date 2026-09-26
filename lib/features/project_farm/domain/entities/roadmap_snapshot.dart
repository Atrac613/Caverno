import 'package:freezed_annotation/freezed_annotation.dart';

part 'roadmap_snapshot.freezed.dart';
part 'roadmap_snapshot.g.dart';

/// What the dashboard can say about a project's next task.
enum RoadmapSnapshotStatus {
  /// The roadmap names a next task and its quote was found in the source.
  verified,

  /// The model named a next task, but its quote does not support it. Shown as
  /// unverified, never as a guess.
  unverified,

  /// The roadmap does not single out a next task.
  none,

  /// Extraction did not produce a usable answer.
  failed,
}

/// One roadmap item as the dashboard shows it. [line] comes from the verifier,
/// not the model, so the citation points at the source.
@freezed
abstract class RoadmapItemSnapshot with _$RoadmapItemSnapshot {
  const factory RoadmapItemSnapshot({
    required String id,
    required String title,
    required String quote,
    int? line,
    @Default(true) bool verified,
  }) = _RoadmapItemSnapshot;

  factory RoadmapItemSnapshot.fromJson(Map<String, dynamic> json) =>
      _$RoadmapItemSnapshotFromJson(json);
}

/// A cited projection of one project's roadmap document.
///
/// The repository file is the source of truth; this records what was derived
/// from it and against which content, so the dashboard renders it without a
/// model call and re-extracts only when [cacheKey] changes.
@freezed
abstract class RoadmapSnapshot with _$RoadmapSnapshot {
  const RoadmapSnapshot._();

  const factory RoadmapSnapshot({
    required String projectId,
    required String roadmapPath,
    required String contentSha256,
    required int extractorVersion,
    required String model,
    required DateTime extractedAt,
    required RoadmapSnapshotStatus status,
    RoadmapItemSnapshot? recommended,
    @Default(<RoadmapItemSnapshot>[]) List<RoadmapItemSnapshot> current,
    @Default(<RoadmapItemSnapshot>[]) List<RoadmapItemSnapshot> blocked,
    @Default(0) int droppedCount,
    String? error,

    /// The user pinned [recommended] over what the extractor chose. Applied
    /// at read time by the service; the stored snapshot stays as extracted.
    @Default(false) bool pinned,
  }) = _RoadmapSnapshot;

  factory RoadmapSnapshot.fromJson(Map<String, dynamic> json) =>
      _$RoadmapSnapshotFromJson(json);

  String get cacheKey =>
      roadmapCacheKey(contentSha256, extractorVersion, model);
}

String roadmapCacheKey(
  String contentSha256,
  int extractorVersion,
  String model,
) => '$contentSha256|$extractorVersion|$model';
