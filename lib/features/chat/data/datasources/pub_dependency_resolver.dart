import 'dart:convert';
import 'dart:io';

/// One package record read from a lockfile.
///
/// Shared by LL10's `resolve_installed_dependency` and the KC2 dependency
/// inventory so both read a lockfile the same way. Every ecosystem parser in
/// LL10 produces this shape; the pub-specific parsing lives in
/// [PubDependencyResolver].
class LockedPackage {
  const LockedPackage({
    required this.name,
    required this.version,
    required this.source,
    required this.dependency,
    required this.url,
    required this.path,
    required this.resolvedRef,
  });

  final String name;
  final String? version;
  final String? source;

  /// pub's `dependency:` field: `direct main`, `direct dev`,
  /// `direct overridden`, or `transitive`. Null for ecosystems that do not
  /// record it.
  final String? dependency;
  final String? url;
  final String? path;
  final String? resolvedRef;

  bool get isDirect => dependency?.startsWith('direct') ?? false;

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'source': source,
    'dependency': dependency,
    if (url != null) 'url': url,
    if (path != null) 'path': path,
    if (resolvedRef != null) 'resolved_ref': resolvedRef,
  };
}

/// Reads `pubspec.lock` and resolves an installed package's root offline.
///
/// Moved out of LL10's grounding service unchanged so the KC2 inventory does
/// not grow a second pub parser: the KC2 design requires one resolver, because
/// two would disagree about the same lockfile sooner or later.
abstract final class PubDependencyResolver {
  static List<LockedPackage> parseLockfile(File lockfile) {
    final packages = <LockedPackage>[];
    String? currentName;
    final block = <String>[];

    void flush() {
      final packageName = currentName;
      if (packageName == null) return;
      packages.add(_lockedPackageFromBlock(packageName, block));
      block.clear();
    }

    var inPackages = false;
    for (final line in lockfile.readAsLinesSync()) {
      if (line.trim() == 'packages:') {
        inPackages = true;
        continue;
      }
      if (inPackages &&
          line.isNotEmpty &&
          !line.startsWith(' ') &&
          line.trim() != 'packages:') {
        flush();
        currentName = null;
        break;
      }
      if (!inPackages) {
        continue;
      }
      final match = RegExp(r'^  ([^\s:#][^:#]*):\s*$').firstMatch(line);
      if (match != null) {
        flush();
        currentName = match.group(1)!.trim();
      } else if (currentName != null) {
        block.add(line);
      }
    }
    flush();
    return packages;
  }

  static LockedPackage _lockedPackageFromBlock(
    String packageName,
    List<String> block,
  ) {
    String? dependency;
    String? source;
    String? version;
    String? descriptionName;
    String? descriptionUrl;
    String? descriptionPath;
    String? resolvedRef;

    for (final line in block) {
      final trimmed = line.trim();
      if (trimmed.startsWith('dependency:')) {
        dependency = _stripYamlScalar(trimmed.substring('dependency:'.length));
      } else if (trimmed.startsWith('source:')) {
        source = _stripYamlScalar(trimmed.substring('source:'.length));
      } else if (trimmed.startsWith('version:')) {
        version = _stripYamlScalar(trimmed.substring('version:'.length));
      } else if (trimmed.startsWith('name:')) {
        descriptionName = _stripYamlScalar(trimmed.substring('name:'.length));
      } else if (trimmed.startsWith('url:')) {
        descriptionUrl = _stripYamlScalar(trimmed.substring('url:'.length));
      } else if (trimmed.startsWith('path:')) {
        descriptionPath = _stripYamlScalar(trimmed.substring('path:'.length));
      } else if (trimmed.startsWith('resolved-ref:')) {
        resolvedRef = _stripYamlScalar(
          trimmed.substring('resolved-ref:'.length),
        );
      }
    }

    return LockedPackage(
      name: descriptionName?.isNotEmpty == true
          ? descriptionName!
          : packageName,
      version: version,
      source: source,
      dependency: dependency,
      url: descriptionUrl,
      path: descriptionPath,
      resolvedRef: resolvedRef,
    );
  }

  static String? resolvePackageRoot(
    Directory projectRoot,
    LockedPackage package,
  ) {
    final packageConfigRoot = _resolveFromPackageConfig(
      projectRoot,
      package.name,
    );
    if (packageConfigRoot != null) return packageConfigRoot;

    if (package.source == 'path' && package.path != null) {
      final path = _resolveProjectPath(projectRoot, package.path!);
      if (Directory(path).existsSync()) return path;
    }

    if (package.source == 'hosted' && package.version != null) {
      for (final cacheRoot in _pubCacheRoots()) {
        for (final host in const ['pub.dev', 'pub.dartlang.org']) {
          final candidate = Directory.fromUri(
            cacheRoot.uri.resolve(
              'hosted/$host/${package.name}-${package.version}/',
            ),
          );
          if (candidate.existsSync()) return candidate.path;
        }
      }
    }
    return null;
  }

  static String? _resolveFromPackageConfig(
    Directory projectRoot,
    String packageName,
  ) {
    final config = File.fromUri(
      projectRoot.uri.resolve('.dart_tool/package_config.json'),
    );
    if (!config.existsSync()) return null;
    final decoded = jsonDecode(config.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return null;
    final packages = decoded['packages'];
    if (packages is! List<dynamic>) return null;
    for (final entry in packages) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['name'] != packageName) continue;
      final rootUri = entry['rootUri'] as String?;
      if (rootUri == null || rootUri.isEmpty) return null;
      final resolved = Uri.parse(rootUri);
      if (resolved.scheme == 'file') {
        return Directory.fromUri(resolved).absolute.path;
      }
      if (resolved.scheme.isEmpty) {
        return Directory.fromUri(
          config.parent.uri.resolve(rootUri),
        ).absolute.path;
      }
    }
    return null;
  }

  static List<Directory> _pubCacheRoots() {
    final roots = <Directory>[];
    final pubCache = Platform.environment['PUB_CACHE']?.trim();
    if (pubCache != null && pubCache.isNotEmpty) {
      roots.add(Directory(pubCache).absolute);
    }
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      roots.add(Directory.fromUri(Directory(home).uri.resolve('.pub-cache/')));
    }
    return roots;
  }

  static String _resolveProjectPath(Directory projectRoot, String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      return Directory.fromUri(uri).absolute.path;
    }
    if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return Directory(path).absolute.path;
    }
    return Directory.fromUri(projectRoot.uri.resolve(path)).absolute.path;
  }

  static String _stripYamlScalar(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2) {
      final first = trimmed.codeUnitAt(0);
      final last = trimmed.codeUnitAt(trimmed.length - 1);
      if ((first == 34 && last == 34) || (first == 39 && last == 39)) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }
}
