import 'dart:async';

import 'package:path/path.dart' as path;

/// Immutable native evidence carried with a queued turn, never through prose.
final class ProjectTaskCommitSnapshot {
  ProjectTaskCommitSnapshot({
    required this.head,
    required this.indexFingerprint,
    required Map<String, String> fileFingerprints,
    required Set<String> stagedPaths,
    required Set<String> unstagedPaths,
    this.roadmapAlreadyDone = false,
    this.roadmapEntryIdentity,
    this.roadmapReferenceCaptured = false,
  }) : fileFingerprints = Map.unmodifiable(fileFingerprints),
       stagedPaths = Set.unmodifiable(stagedPaths),
       unstagedPaths = Set.unmodifiable(unstagedPaths);
  final String head;
  final String indexFingerprint;
  final Map<String, String> fileFingerprints;
  final Set<String> stagedPaths;
  final Set<String> unstagedPaths;
  final bool roadmapAlreadyDone;
  final String? roadmapEntryIdentity;
  final bool roadmapReferenceCaptured;
}

final class ProjectTaskCommitScope {
  static final Object _enqueueKey = Object();
  static ProjectTaskCommitScope? get forEnqueue =>
      Zone.current[_enqueueKey] as ProjectTaskCommitScope?;
  static T enqueue<T>(ProjectTaskCommitScope scope, T Function() callback) =>
      runZoned(callback, zoneValues: {_enqueueKey: scope});
  ProjectTaskCommitScope({
    required this.conversationId,
    required this.projectRoot,
    required this.roadmapPath,
    required Iterable<String> reviewedPaths,
    this.sourceQuote,
    this.sourceLine,
    this.prepared,
  }) : reviewedPaths = Set.unmodifiable(reviewedPaths);

  final String conversationId;
  final String projectRoot;
  final String roadmapPath;
  final Set<String> reviewedPaths;
  final String? sourceQuote;
  final int? sourceLine;
  final ProjectTaskCommitSnapshot? prepared;
  Set<String> get paths => {...reviewedPaths, roadmapPath};
  String resolve(String value) => path.normalize(
    path.isAbsolute(value) ? value : path.join(projectRoot, value),
  );

  ProjectTaskCommitScope authorize(ProjectTaskCommitSnapshot snapshot) =>
      ProjectTaskCommitScope(
        conversationId: conversationId,
        projectRoot: projectRoot,
        roadmapPath: roadmapPath,
        reviewedPaths: reviewedPaths,
        sourceQuote: sourceQuote,
        sourceLine: sourceLine,
        prepared: snapshot,
      );

  bool sameCapturedState(
    ProjectTaskCommitSnapshot before,
    ProjectTaskCommitSnapshot after,
  ) =>
      before.head == after.head &&
      before.indexFingerprint == after.indexFingerprint &&
      before.stagedPaths.length == after.stagedPaths.length &&
      before.stagedPaths.containsAll(after.stagedPaths) &&
      paths.every(
        (file) =>
            before.unstagedPaths.contains(file) ==
            after.unstagedPaths.contains(file),
      ) &&
      before.fileFingerprints.keys.toSet().containsAll(paths) &&
      after.fileFingerprints.keys.toSet().containsAll(paths) &&
      paths.every(
        (file) => before.fileFingerprints[file] == after.fileFingerprints[file],
      );

  String? preparationProblem(
    ProjectTaskCommitSnapshot before,
    ProjectTaskCommitSnapshot after,
  ) {
    if (!before.fileFingerprints.keys.toSet().containsAll(paths) ||
        !after.fileFingerprints.keys.toSet().containsAll(paths)) {
      return 'native task file evidence is incomplete';
    }
    if (before.head != after.head) {
      return 'HEAD changed during commit preparation';
    }
    if (reviewedPaths.any(
      (file) =>
          file != roadmapPath &&
          before.fileFingerprints[file] != after.fileFingerprints[file],
    )) {
      return 'the reviewed task files changed during commit preparation';
    }
    if (before.roadmapReferenceCaptured &&
        sourceQuote != null &&
        RegExp(r'^\s*(?:[-*+]\s+)?\[[ xX]\]\s+').hasMatch(sourceQuote!) &&
        before.roadmapEntryIdentity == null) {
      return 'the cited roadmap entry could not be resolved before preparation';
    }
    if (before.roadmapEntryIdentity != null &&
        before.roadmapEntryIdentity != after.roadmapEntryIdentity) {
      return 'the cited roadmap entry changed during commit preparation';
    }
    if (after.stagedPaths.isEmpty) return 'no task changes are staged';
    if (after.stagedPaths.difference(paths).isNotEmpty) {
      return 'the index includes unrelated staged files';
    }
    if (after.unstagedPaths.intersection(paths).isNotEmpty) {
      return 'task files still have unstaged changes';
    }
    final unchangedCompletedRoadmap =
        before.roadmapAlreadyDone &&
        after.roadmapAlreadyDone &&
        before.fileFingerprints[roadmapPath] ==
            after.fileFingerprints[roadmapPath];
    if (!after.stagedPaths.contains(roadmapPath) &&
        !unchangedCompletedRoadmap) {
      return 'the roadmap update is missing from the index';
    }
    // A quote without checkbox syntax still names a checklist task once it
    // resolves to one, and that task must be marked complete too.
    if (sourceQuote != null &&
        (RegExp(r'^\s*(?:[-*+]\s+)?\[[ xX]\]\s+').hasMatch(sourceQuote!) ||
            before.roadmapEntryIdentity != null) &&
        !after.roadmapAlreadyDone) {
      return 'the cited roadmap task is not marked complete';
    }
    return null;
  }

  String? commitProblem(ProjectTaskCommitSnapshot now) {
    final expected = prepared;
    if (expected == null) return 'commit preparation has not been accepted';
    if (!expected.fileFingerprints.keys.toSet().containsAll(paths) ||
        !now.fileFingerprints.keys.toSet().containsAll(paths)) {
      return 'native task file evidence is incomplete';
    }
    if (expected.head != now.head ||
        expected.indexFingerprint != now.indexFingerprint ||
        paths.any(
          (file) =>
              expected.fileFingerprints[file] != now.fileFingerprints[file],
        )) {
      return 'HEAD, index or task files changed after commit preparation';
    }
    if (now.unstagedPaths.intersection(paths).isNotEmpty) {
      return 'task files still have unstaged changes';
    }
    return null;
  }

  static ProjectTaskCommitScope? fromObjective({
    required String conversationId,
    required String projectRoot,
    required String objective,
    required Iterable<String> reviewedPaths,
  }) {
    final citation = RegExp(
      r'^Source: (.+)$',
      multiLine: true,
    ).firstMatch(objective);
    if (citation == null) return null;
    var file = citation.group(1)!.trim();
    final numbered = RegExp(r':([0-9]+)$').firstMatch(file);
    if (numbered != null) file = file.substring(0, numbered.start);
    final root = path.normalize(projectRoot);
    String resolve(String value) =>
        path.normalize(path.isAbsolute(value) ? value : path.join(root, value));
    final roadmap = resolve(file);
    final files = reviewedPaths.map(resolve).toSet();
    if (file.isEmpty ||
        !path.isWithin(root, roadmap) ||
        files.any((file) => !path.isWithin(root, file))) {
      return null;
    }
    final rest = objective.substring(citation.end).trimLeft();
    final quote = RegExp(
      r'^"([\s\S]*?)"[ \t]*(?:\r?\n[ \t]*\r?\n|$)',
    ).firstMatch(rest)?.group(1);
    return ProjectTaskCommitScope(
      conversationId: conversationId,
      projectRoot: root,
      roadmapPath: roadmap,
      reviewedPaths: files,
      sourceQuote: quote,
      sourceLine: numbered == null ? null : int.tryParse(numbered.group(1)!),
    );
  }
}
