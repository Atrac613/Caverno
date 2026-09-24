import 'dart:io';

import 'pub_dependency_resolver.dart';

/// Whether an installed package agrees with what the lockfile says.
///
/// KC2's block carries authority: a version it names is stated as fact. So a
/// version reaches it only when two independent sources agree, and the
/// disagreement is kept as a verdict instead of being resolved by picking one.
enum DependencyAttestation {
  /// The lockfile version equals the version the installed package declares.
  exact,

  /// Both are readable and they differ: the lockfile is stale relative to what
  /// is installed, or the reverse. Never stated as a fact.
  mismatch,

  /// One side could not be read offline, most often because the package has
  /// not been fetched. Never stated as a fact either.
  unverifiable,
}

/// One direct dependency, with where each version came from.
class DependencyRecord {
  const DependencyRecord({
    required this.name,
    required this.ecosystem,
    required this.dependencyKind,
    required this.manifestPath,
    required this.lockedVersion,
    required this.lockfilePath,
    required this.installedVersion,
    required this.installedMetadataPath,
    required this.resolvedRoot,
    required this.attestation,
  });

  final String name;
  final String ecosystem;

  /// pub's lockfile classification, e.g. `direct main` or `direct dev`.
  final String? dependencyKind;

  /// The manifest that declares the dependency, or null when the project has
  /// a lockfile without one.
  final String? manifestPath;
  final String? lockedVersion;
  final String lockfilePath;
  final String? installedVersion;

  /// The file the installed version was read from, when one was found.
  final String? installedMetadataPath;
  final String? resolvedRoot;
  final DependencyAttestation attestation;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ecosystem': ecosystem,
    'dependency': dependencyKind,
    'manifest': manifestPath,
    'locked_version': lockedVersion,
    'lockfile': lockfilePath,
    'installed_version': installedVersion,
    'installed_metadata': installedMetadataPath,
    'resolved_root': resolvedRoot,
    'attestation': attestation.name,
  };
}

class DependencyInventory {
  const DependencyInventory({required this.projectRoot, required this.records});

  final String projectRoot;

  /// Direct dependencies, sorted by name.
  final List<DependencyRecord> records;

  /// The only records a prompt may state as fact.
  Iterable<DependencyRecord> get exact => records.where(
    (record) => record.attestation == DependencyAttestation.exact,
  );
}

/// Collects the direct dependencies of a project, attested offline.
///
/// First slice of KC2 (`docs/knowledge_currency_track_design.md`): Dart only,
/// and no prompt wiring. Reads the lockfile and the installed packages through
/// [PubDependencyResolver], the same resolver LL10 uses, and never touches the
/// network or spawns a toolchain command.
class DependencyInventoryService {
  const DependencyInventoryService();

  /// Returns null when the project has no `pubspec.lock`: with nothing locked
  /// there is nothing to attest, and the block must be omitted rather than
  /// guessed.
  DependencyInventory? collect(Directory projectRoot) {
    final root = projectRoot.absolute;
    final lockfile = File.fromUri(root.uri.resolve('pubspec.lock'));
    if (!lockfile.existsSync()) return null;

    final manifest = File.fromUri(root.uri.resolve('pubspec.yaml'));
    final manifestPath = manifest.existsSync() ? manifest.path : null;
    final records = <DependencyRecord>[];
    for (final package in PubDependencyResolver.parseLockfile(lockfile)) {
      // SDK packages (flutter, flutter_test) lock as 0.0.0; their version is
      // the toolchain's and belongs to the toolchain line, not this list.
      if (!package.isDirect || package.source == 'sdk') continue;
      records.add(_attest(root, lockfile, manifestPath, package));
    }
    records.sort((a, b) => a.name.compareTo(b.name));
    return DependencyInventory(
      projectRoot: root.path,
      records: List.unmodifiable(records),
    );
  }

  DependencyRecord _attest(
    Directory root,
    File lockfile,
    String? manifestPath,
    LockedPackage package,
  ) {
    final resolvedRoot = PubDependencyResolver.resolvePackageRoot(
      root,
      package,
    );
    final metadata = resolvedRoot == null
        ? null
        : File.fromUri(Directory(resolvedRoot).uri.resolve('pubspec.yaml'));
    final installedVersion = metadata != null && metadata.existsSync()
        ? _declaredVersion(metadata)
        : null;
    final locked = package.version;
    final attestation = locked == null || installedVersion == null
        ? DependencyAttestation.unverifiable
        : locked == installedVersion
        ? DependencyAttestation.exact
        : DependencyAttestation.mismatch;
    return DependencyRecord(
      name: package.name,
      ecosystem: 'dart',
      dependencyKind: package.dependency,
      manifestPath: manifestPath,
      lockedVersion: locked,
      lockfilePath: lockfile.path,
      installedVersion: installedVersion,
      installedMetadataPath: installedVersion == null ? null : metadata!.path,
      resolvedRoot: resolvedRoot,
      attestation: attestation,
    );
  }

  static final _versionLine = RegExp(r'''^version:\s*["']?([^\s"'#]+)''');

  String? _declaredVersion(File pubspec) {
    for (final line in pubspec.readAsLinesSync()) {
      final match = _versionLine.firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }
}
