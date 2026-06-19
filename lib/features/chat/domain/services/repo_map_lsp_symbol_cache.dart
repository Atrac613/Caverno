import 'dart:io';

import 'dart_project_tooling.dart';
import 'lsp_diagnostic_feedback_provider.dart';
import 'repo_map_service.dart';

class RepoMapLspSymbolCache {
  final Map<String, Map<String, RepoMapSymbolEntry>> _entriesByRoot = {};

  List<RepoMapSymbolEntry> entriesForRoot(String? projectRoot) {
    final key = _rootKey(projectRoot);
    if (key == null) {
      return const [];
    }
    final entries = _entriesByRoot[key];
    if (entries == null || entries.isEmpty) {
      return const [];
    }
    final values = entries.values.toList(growable: false)
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return List<RepoMapSymbolEntry>.unmodifiable(values);
  }

  void updateFromLsp({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required Iterable<LspDocumentSymbol> symbols,
  }) {
    final key = _rootKey(projectRoot);
    if (key == null) {
      return;
    }
    final root = Directory(projectRoot).absolute.path;
    final entries = _entriesByRoot.putIfAbsent(
      key,
      () => <String, RepoMapSymbolEntry>{},
    );
    for (final relativePath in _relativeChangedPaths(
      projectRoot: root,
      changedPaths: changedPaths,
    )) {
      entries.remove(relativePath);
    }
    for (final entry in RepoMapService.symbolEntriesFromLsp(
      projectRoot: root,
      symbols: symbols,
    )) {
      entries[entry.relativePath] = entry;
    }
    if (entries.isEmpty) {
      _entriesByRoot.remove(key);
    }
  }

  void clearRoot(String? projectRoot) {
    final key = _rootKey(projectRoot);
    if (key == null) {
      return;
    }
    _entriesByRoot.remove(key);
  }

  void clear() => _entriesByRoot.clear();

  String? _rootKey(String? projectRoot) {
    final trimmed = projectRoot?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return DartProjectPath.pathKey(Directory(trimmed).absolute.path);
  }

  Iterable<String> _relativeChangedPaths({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) sync* {
    final seen = <String>{};
    for (final rawPath in changedPaths) {
      final absolutePath = DartProjectPath.resolvePath(
        rawPath,
        projectRoot: projectRoot,
      );
      if (absolutePath == null ||
          !DartProjectPath.isInsideRoot(absolutePath, projectRoot)) {
        continue;
      }
      final relativePath = DartProjectPath.relativePath(
        absolutePath,
        projectRoot,
      ).replaceAll('\\', '/');
      if (seen.add(relativePath)) {
        yield relativePath;
      }
    }
  }
}
