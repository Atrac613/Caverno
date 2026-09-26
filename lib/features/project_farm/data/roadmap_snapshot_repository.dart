import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/project_farm_policy.dart';
import '../domain/entities/project_proposal.dart';
import '../domain/entities/roadmap_snapshot.dart';

/// Persists each project's chosen roadmap path and its latest snapshot.
///
/// Kept apart from `CodingProject` on purpose: these are dashboard
/// projections, not project identity, and a field on the entity would tie the
/// dashboard's schema to every screen that reads projects.
abstract interface class RoadmapSnapshotRepositoryApi {
  String? roadmapPathFor(String projectId);

  Future<void> saveRoadmapPath(String projectId, String? roadmapPath);

  RoadmapSnapshot? snapshotFor(String projectId);

  Future<void> saveSnapshot(RoadmapSnapshot snapshot);

  ProjectProposal? proposalFor(String projectId);

  Future<void> saveProposal(ProjectProposal proposal);

  ProjectFarmPolicy? policyFor(String projectId);

  Future<void> savePolicy(ProjectFarmPolicy policy);

  /// The roadmap item id the user pinned as next, if any.
  String? pinnedTaskFor(String projectId);

  Future<void> savePinnedTask(String projectId, String? taskId);
}

class RoadmapSnapshotRepository implements RoadmapSnapshotRepositoryApi {
  RoadmapSnapshotRepository(this._prefs);

  static const _pathsKey = 'project_farm_roadmap_paths';
  static const _snapshotsKey = 'project_farm_roadmap_snapshots';
  static const _proposalsKey = 'project_farm_proposals';
  static const _policiesKey = 'project_farm_policies';
  static const _pinsKey = 'project_farm_pinned_tasks';

  final SharedPreferences _prefs;

  @override
  String? roadmapPathFor(String projectId) {
    final value = _readMap(_pathsKey)[projectId];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  @override
  Future<void> saveRoadmapPath(String projectId, String? roadmapPath) {
    final paths = _readMap(_pathsKey);
    final trimmed = roadmapPath?.trim() ?? '';
    if (trimmed.isEmpty) {
      paths.remove(projectId);
    } else {
      paths[projectId] = trimmed;
    }
    return _prefs.setString(_pathsKey, jsonEncode(paths));
  }

  @override
  RoadmapSnapshot? snapshotFor(String projectId) {
    final value = _readMap(_snapshotsKey)[projectId];
    if (value is! Map<String, dynamic>) return null;
    try {
      return RoadmapSnapshot.fromJson(value);
    } on Object {
      // A snapshot from an older schema is a cache miss, not an error.
      return null;
    }
  }

  @override
  Future<void> saveSnapshot(RoadmapSnapshot snapshot) {
    final snapshots = _readMap(_snapshotsKey);
    snapshots[snapshot.projectId] = jsonDecode(jsonEncode(snapshot));
    return _prefs.setString(_snapshotsKey, jsonEncode(snapshots));
  }

  @override
  ProjectProposal? proposalFor(String projectId) {
    final value = _readMap(_proposalsKey)[projectId];
    if (value is! Map<String, dynamic>) return null;
    try {
      return ProjectProposal.fromJson(value);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveProposal(ProjectProposal proposal) {
    final proposals = _readMap(_proposalsKey);
    proposals[proposal.projectId] = proposal.toJson();
    return _prefs.setString(_proposalsKey, jsonEncode(proposals));
  }

  @override
  ProjectFarmPolicy? policyFor(String projectId) {
    final value = _readMap(_policiesKey)[projectId];
    if (value is! Map<String, dynamic>) return null;
    try {
      return ProjectFarmPolicy.fromJson(value);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> savePolicy(ProjectFarmPolicy policy) {
    final policies = _readMap(_policiesKey);
    policies[policy.projectId] = policy.toJson();
    return _prefs.setString(_policiesKey, jsonEncode(policies));
  }

  @override
  String? pinnedTaskFor(String projectId) {
    final value = _readMap(_pinsKey)[projectId];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  @override
  Future<void> savePinnedTask(String projectId, String? taskId) {
    final pins = _readMap(_pinsKey);
    final trimmed = taskId?.trim() ?? '';
    if (trimmed.isEmpty) {
      pins.remove(projectId);
    } else {
      pins[projectId] = trimmed;
    }
    return _prefs.setString(_pinsKey, jsonEncode(pins));
  }

  Map<String, dynamic> _readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}
