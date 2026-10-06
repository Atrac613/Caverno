import 'dart:io';

/// How many of a project's own Dart files import each package.
///
/// KC2's version list regressed class 4 because it named 59 dependencies and
/// the one that says how this project holds state became one entry in sixty
/// (eighth KC1 measurement). Import breadth is ground truth about which
/// libraries the code is written against, read from the code rather than
/// judged from prose: a package imported by 173 files is what a new file will
/// most likely use too.
///
/// Generated files are skipped, because they import what their generator
/// needs rather than what the author chose. Parsing is cached per file by size
/// and modification time, so a turn that edited one file re-reads one file.
class ProjectImportCensus {
  final Map<String, _FileImports> _files = {};

  static final _directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]package:([a-z0-9_]+)/''',
    multiLine: true,
  );

  /// Files under `<projectRoot>/lib` importing each package, by package name.
  Map<String, int> count(String projectRoot) {
    final lib = Directory('$projectRoot/lib');
    if (!lib.existsSync()) return const {};
    final counts = <String, int>{};
    final seen = <String>{};
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart') ||
          path.endsWith('.g.dart') ||
          path.endsWith('.freezed.dart')) {
        continue;
      }
      seen.add(path);
      final stat = entity.statSync();
      final stamp = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      var cached = _files[path];
      if (cached == null || cached.stamp != stamp) {
        cached = _FileImports(stamp, _packagesIn(entity));
        _files[path] = cached;
      }
      for (final package in cached.packages) {
        counts[package] = (counts[package] ?? 0) + 1;
      }
    }
    _files.removeWhere(
      (path, _) => path.startsWith(lib.path) && !seen.contains(path),
    );
    return counts;
  }

  static Set<String> _packagesIn(File file) {
    try {
      return {
        for (final match in _directive.allMatches(file.readAsStringSync()))
          match.group(1)!,
      };
    } on FileSystemException {
      return const {};
    } on FormatException {
      return const {};
    }
  }
}

class _FileImports {
  const _FileImports(this.stamp, this.packages);

  final String stamp;
  final Set<String> packages;
}
