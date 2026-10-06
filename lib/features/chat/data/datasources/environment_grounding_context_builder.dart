import 'dart:convert';
import 'dart:io';

import 'dependency_inventory.dart';
import 'installed_change_digest.dart';
import 'project_import_census.dart';
import 'pub_dependency_resolver.dart';

/// KC2 slice 2: the environment and dependency ground-truth block.
///
/// Renders what [DependencyInventoryService] attested, plus the toolchain the
/// project was resolved with, as a short prompt block. It is not wired into
/// the prompt yet; slice 3 does that
/// (`docs/knowledge_currency_track_design.md`, KC2).
///
/// The block carries authority, so the same rule as the inventory applies to
/// every version it names: two independent sources must agree, or the version
/// is withheld.
///
/// - Flutter: `package_config.json`'s `flutterVersion` (the SDK `pub get` ran
///   with) against that SDK's own `bin/cache/flutter.version.json`.
/// - Dart: `package_config.json`'s `generatorVersion` against the same file's
///   `dartSdkVersion`.
/// - Dependencies: only `exact` inventory records carry a version. The rest
///   are named, labeled, and given no version.
///
/// Output is deterministic for the same files and cached by their size and
/// modification time, so consecutive turns in one project get byte-identical
/// bytes without re-reading the dependency tree.
class EnvironmentGroundingContextBuilder {
  EnvironmentGroundingContextBuilder({
    DependencyInventory? Function(Directory projectRoot)? collect,
    this.maxChars = defaultMaxChars,
  }) : _collect = collect ?? const DependencyInventoryService().collect;

  /// About 400 tokens at four characters per token, the KC2 target.
  static const defaultMaxChars = 1600;

  /// The cap for a model with [usableContextTokens] (LL39), or the default
  /// when that is unknown.
  ///
  /// A step function rather than a proportion, so small profile noise does not
  /// move the cap and with it the block's bytes. A small window keeps the
  /// toolchain line and drops the dependency list first, as the KC2 scope
  /// requires; a large one lifts the cut that otherwise drops dev
  /// dependencies such as freezed on a 66-dependency project.
  static int maxCharsForUsableContext(int? usableContextTokens) {
    if (usableContextTokens == null || usableContextTokens <= 0) {
      return defaultMaxChars;
    }
    if (usableContextTokens < 16384) return 400;
    if (usableContextTokens < 32768) return defaultMaxChars;
    return 3200;
  }

  /// The change digest's own budget (KC2 slice 4), stepped the same way.
  ///
  /// The digest is what KC1 measured to move API-drift claims, so it gets more
  /// room than the version list where the window allows; below 16k tokens it
  /// is dropped entirely, before the toolchain line.
  static int digestMaxCharsForUsableContext(int? usableContextTokens) {
    if (usableContextTokens == null || usableContextTokens <= 0) {
      return defaultMaxChars;
    }
    if (usableContextTokens < 16384) return 0;
    if (usableContextTokens < 32768) return defaultMaxChars;
    // The measured prototype carried ~3.8k characters for three hand-picked
    // packages; generalized to every attested package it needs more, and a
    // 64k window affords ~2.5k tokens (under 4%).
    if (usableContextTokens < 65536) return 6000;
    return 10000;
  }

  static const heading =
      'Project toolchain and dependencies, read from this project\'s lockfile '
      'and installed packages. These are the versions installed here, not '
      'the latest published releases:';

  final DependencyInventory? Function(Directory projectRoot) _collect;
  final int maxChars;
  final Map<String, _CachedBlock> _cache = {};
  final ProjectImportCensus _imports = ProjectImportCensus();
  final Map<String, (String, Set<String>)> _directNames = {};

  /// The block for [projectRootPath], or null when there is no lockfile to
  /// attest against. A missing or unreadable lockfile omits the block; it
  /// never falls back to a guessed version. [maxChars] overrides the
  /// builder's cap for this call.
  ///
  /// [mostImported] lists only the direct dependencies imported by the most
  /// files under `lib/` (ties by name), in name order, and restricts the
  /// digest to them. The selection is part of the cache key, so the bytes
  /// change only when its membership does, not on every edit.
  String? build(
    String projectRootPath, {
    int? maxChars,
    int digestMaxChars = defaultMaxChars,
    int? mostImported,
  }) {
    final cap = maxChars ?? this.maxChars;
    final root = Directory(projectRootPath).absolute;
    final selected = mostImported == null
        ? null
        : _mostImported(root, mostImported);
    final key =
        '${_canonicalPath(root)}|$cap|$digestMaxChars|'
        '${selected == null ? '*' : (selected.toList()..sort()).join(',')}';
    final cached = _cache[key];
    if (cached != null && cached.isFresh()) return cached.block;

    final watched = <File>[
      File.fromUri(root.uri.resolve('pubspec.yaml')),
      File.fromUri(root.uri.resolve('pubspec.lock')),
      File.fromUri(root.uri.resolve('.dart_tool/package_config.json')),
    ];
    String? block;
    try {
      final inventory = _collect(root);
      if (inventory != null) {
        final toolchain = _readToolchain(watched.last);
        if (toolchain.versionFile != null) watched.add(toolchain.versionFile!);
        final shown = selected == null
            ? inventory
            : DependencyInventory(
                projectRoot: inventory.projectRoot,
                records: [
                  for (final record in inventory.records)
                    if (selected.contains(record.name)) record,
                ],
              );
        block = _render(
          shown,
          toolchain,
          cap,
          unselected: inventory.records.length - shown.records.length,
        );
        final digest = _digest(shown, toolchain, digestMaxChars);
        if (digest != null) block = '$block\n$digest';
      }
    } on FileSystemException {
      block = null;
    } on FormatException {
      block = null;
    }
    _cache[key] = _CachedBlock(block, _fingerprint(watched), watched);
    return block;
  }

  /// The [count] direct dependencies most imported under `lib/`.
  Set<String> _mostImported(Directory root, int count) {
    final lockfile = File.fromUri(root.uri.resolve('pubspec.lock'));
    if (!lockfile.existsSync()) return const {};
    final stat = lockfile.statSync();
    final stamp = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    var direct = _directNames[lockfile.path];
    if (direct == null || direct.$1 != stamp) {
      direct = (
        stamp,
        {
          for (final package in PubDependencyResolver.parseLockfile(lockfile))
            if (package.isDirect && package.source != 'sdk') package.name,
        },
      );
      _directNames[lockfile.path] = direct;
    }
    final counts = _imports.count(root.path);
    final ranked =
        [
          for (final name in direct.$2)
            if ((counts[name] ?? 0) > 0) name,
        ]..sort((a, b) {
          final byCount = counts[b]!.compareTo(counts[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
    return ranked.take(count).toSet();
  }

  String _render(
    DependencyInventory inventory,
    _Toolchain toolchain,
    int maxChars, {
    int unselected = 0,
  }) {
    final main = <String>[];
    final dev = <String>[];
    final withheld = <String>[];
    for (final record in inventory.records) {
      if (record.attestation != DependencyAttestation.exact) {
        withheld.add(
          '${record.name} (${record.attestation == DependencyAttestation.mismatch ? 'lockfile and installed package disagree' : 'installed version unreadable'})',
        );
        continue;
      }
      final entry = '${record.name} ${record.lockedVersion}';
      (record.dependencyKind == 'direct dev' ? dev : main).add(entry);
    }

    final head = StringBuffer(heading);
    final sdk = [
      if (toolchain.flutter != null) 'Flutter SDK ${toolchain.flutter}',
      if (toolchain.dart != null) 'Dart SDK ${toolchain.dart}',
    ];
    if (sdk.isNotEmpty) head.write('\n- ${sdk.join(', ')}');

    var withheldLine = withheld.isEmpty
        ? ''
        : '\n- Versions withheld, not attested: ${withheld.join(', ')}';

    // Keep the longest prefix of dependencies, main before dev, that fits.
    // A deterministic cut, so the bytes stay stable while the files do.
    final ordered = [...main, ...dev];
    String render(int kept, String withheldPart) {
      final keptMain = main.take(kept).toList();
      final keptDev = dev.take(kept - keptMain.length).toList();
      final buffer = StringBuffer(head.toString());
      if (keptMain.isNotEmpty) {
        buffer.write('\n- Dependencies: ${keptMain.join(', ')}');
      }
      if (keptDev.isNotEmpty) {
        buffer.write('\n- Dev dependencies: ${keptDev.join(', ')}');
      }
      final omitted = ordered.length - kept;
      if (omitted > 0) {
        buffer.write('\n- ($omitted more direct dependencies not listed)');
      }
      if (unselected > 0) {
        buffer.write(
          '\n- ($unselected more direct dependencies, imported by fewer of '
          'this project\'s files, not listed)',
        );
      }
      buffer.write(withheldPart);
      return buffer.toString();
    }

    if (render(0, withheldLine).length > maxChars && withheld.isNotEmpty) {
      withheldLine =
          '\n- Versions withheld for ${withheld.length} dependencies that '
          'could not be attested';
    }
    var kept = ordered.length;
    while (kept > 0 && render(kept, withheldLine).length > maxChars) {
      kept--;
    }
    return render(kept, withheldLine);
  }

  String? _digest(
    DependencyInventory inventory,
    _Toolchain toolchain,
    int maxChars,
  ) {
    if (maxChars <= 0) return null;
    final sdkRoot = toolchain.sdkRoot;
    return ChangeDigestRenderer.render(
      packages: [
        for (final record in inventory.exact)
          if (InstalledChangeDigest.packageChange(record) case final change?
              when !change.isEmpty)
            change,
      ],
      // Only an attested SDK speaks for its deprecations.
      sdkDeprecations: toolchain.flutter == null || sdkRoot == null
          ? const []
          : InstalledChangeDigest.recentSdkDeprecations(
              InstalledChangeDigest.flutterSourceRoots(sdkRoot),
            ),
      flutterVersion: toolchain.flutter,
      maxChars: maxChars,
    );
  }

  _Toolchain _readToolchain(File packageConfig) {
    if (!packageConfig.existsSync()) return const _Toolchain();
    final config = jsonDecode(packageConfig.readAsStringSync());
    if (config is! Map<String, dynamic>) return const _Toolchain();
    final flutterRoot = config['flutterRoot'];
    if (flutterRoot is! String) return const _Toolchain();
    final sdkUri = Uri.parse(
      flutterRoot.endsWith('/') ? flutterRoot : '$flutterRoot/',
    );
    final sdkRoot = Directory.fromUri(
      sdkUri,
    ).path.replaceFirst(RegExp(r'/$'), '');
    final versionFile = File.fromUri(
      sdkUri.resolve('bin/cache/flutter.version.json'),
    );
    if (!versionFile.existsSync()) {
      return _Toolchain(versionFile: versionFile, sdkRoot: sdkRoot);
    }
    final sdk = jsonDecode(versionFile.readAsStringSync());
    if (sdk is! Map<String, dynamic>) {
      return _Toolchain(versionFile: versionFile, sdkRoot: sdkRoot);
    }
    String? agreed(Object? resolvedWith, Object? installed) =>
        resolvedWith is String &&
            resolvedWith.isNotEmpty &&
            resolvedWith == installed
        ? resolvedWith
        : null;
    return _Toolchain(
      flutter: agreed(config['flutterVersion'], sdk['frameworkVersion']),
      dart: agreed(config['generatorVersion'], sdk['dartSdkVersion']),
      versionFile: versionFile,
      sdkRoot: sdkRoot,
    );
  }

  static String _canonicalPath(Directory root) {
    try {
      return root.resolveSymbolicLinksSync();
    } on FileSystemException {
      return root.path;
    }
  }

  static String _fingerprint(List<File> files) => [
    for (final file in files)
      if (file.existsSync())
        '${file.path}:${file.lengthSync()}:'
            '${file.lastModifiedSync().microsecondsSinceEpoch}'
      else
        '${file.path}:missing',
  ].join('|');
}

class _Toolchain {
  const _Toolchain({this.flutter, this.dart, this.versionFile, this.sdkRoot});

  final String? flutter;
  final String? dart;
  final File? versionFile;
  final String? sdkRoot;
}

class _CachedBlock {
  _CachedBlock(this.block, this.fingerprint, this.files);

  final String? block;
  final String fingerprint;
  final List<File> files;

  bool isFresh() =>
      EnvironmentGroundingContextBuilder._fingerprint(files) == fingerprint;
}
