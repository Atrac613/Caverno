import 'dart:io';

import 'dart_project_tooling.dart';

/// An HTML file the companion "Run the app" section can preview.
class HtmlProjectEntry {
  const HtmlProjectEntry({
    required this.absolutePath,
    required this.relativePath,
  });

  final String absolutePath;

  /// Project-relative path used in the preview URL, e.g. `index.html`.
  final String relativePath;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HtmlProjectEntry &&
            absolutePath == other.absolutePath &&
            relativePath == other.relativePath;
  }

  @override
  int get hashCode => Object.hash(absolutePath, relativePath);
}

/// Finds a preview entry in a local project that is not a Flutter app.
///
/// Prefers a root `index.html`, then any other root `*.html`, then a few
/// conventional static-site locations. Flutter packages are ignored so their
/// `web/index.html` is not treated as a standalone HTML app.
class HtmlProjectDetector {
  const HtmlProjectDetector();

  static const _nestedIndexCandidates = [
    'public/index.html',
    'src/index.html',
    'www/index.html',
  ];

  HtmlProjectEntry? detect(String projectRoot) {
    final entries = listEntries(projectRoot);
    if (entries.isEmpty) return null;
    return preferredEntry(projectRoot) ?? entries.first;
  }

  /// The entry Run can start without asking: a root `index.html`, or the only
  /// HTML file. Null when the user needs to pick among several files.
  HtmlProjectEntry? preferredEntry(String projectRoot) {
    final entries = listEntries(projectRoot);
    if (entries.isEmpty) return null;
    for (final entry in entries) {
      if (entry.relativePath == 'index.html') return entry;
    }
    if (entries.length == 1) return entries.single;
    return null;
  }

  List<HtmlProjectEntry> listEntries(String projectRoot) {
    final trimmed = projectRoot.trim();
    if (trimmed.isEmpty) return const [];
    final root = Directory(trimmed);
    if (!root.existsSync()) return const [];
    if (DartProjectTooling.isFlutterPackage(trimmed)) return const [];

    final entries = <HtmlProjectEntry>[];
    final seen = <String>{};

    void add(HtmlProjectEntry? entry) {
      if (entry == null) return;
      if (!seen.add(entry.relativePath)) return;
      entries.add(entry);
    }

    add(_fileIfExists(root, 'index.html'));
    for (final file in _rootHtmlFiles(root)) {
      add(file);
    }
    if (entries.isEmpty) {
      for (final relative in _nestedIndexCandidates) {
        add(_fileIfExists(root, relative));
      }
    }
    return List.unmodifiable(entries);
  }

  HtmlProjectEntry? _fileIfExists(Directory root, String relativePath) {
    final file = File.fromUri(root.uri.resolve(relativePath));
    if (!file.existsSync()) return null;
    final absolute = file.absolute.path;
    if (!DartProjectPath.isInsideRoot(absolute, root.path)) return null;
    return HtmlProjectEntry(
      absolutePath: absolute,
      relativePath: DartProjectPath.relativePath(absolute, root.path),
    );
  }

  List<HtmlProjectEntry> _rootHtmlFiles(Directory root) {
    final entries = <HtmlProjectEntry>[];
    final List<FileSystemEntity> children;
    try {
      children = root.listSync(followLinks: false);
    } on FileSystemException {
      return const [];
    }
    for (final child in children) {
      if (child is! File) continue;
      final name = child.uri.pathSegments.isEmpty
          ? ''
          : child.uri.pathSegments.last;
      if (!name.toLowerCase().endsWith('.html')) continue;
      final absolute = child.absolute.path;
      if (!DartProjectPath.isInsideRoot(absolute, root.path)) continue;
      entries.add(
        HtmlProjectEntry(
          absolutePath: absolute,
          relativePath: DartProjectPath.relativePath(absolute, root.path),
        ),
      );
    }
    entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return entries;
  }
}
