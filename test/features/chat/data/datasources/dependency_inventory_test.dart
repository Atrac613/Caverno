import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/dependency_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

/// KC2 slice 1: the dependency inventory that a prompt block may later state
/// as fact. What is defended here is the authority rule: only a version two
/// independent sources agree on is `exact`, and nothing else may be read as
/// one.
void main() {
  late Directory root;
  const service = DependencyInventoryService();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dependency_inventory_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Directory project() =>
      Directory.fromUri(root.uri.resolve('app/'))..createSync(recursive: true);

  void writeLock(Directory project, String packages) {
    File.fromUri(
      project.uri.resolve('pubspec.lock'),
    ).writeAsStringSync('packages:\n$packages\nsdks:\n  dart: ">=3.0.0"\n');
  }

  String lockEntry(
    String name,
    String version, {
    String dependency = 'direct main',
    String source = 'hosted',
  }) =>
      '''
  $name:
    dependency: "$dependency"
    description:
      name: $name
      url: "https://pub.dev"
    source: $source
    version: "$version"
''';

  /// Installs [name] under `pkgs/` declaring [version], and registers it in
  /// package_config.json the way `pub get` does.
  void install(Directory project, Map<String, String?> packages) {
    final entries = <Map<String, Object>>[];
    packages.forEach((name, version) {
      final dir = Directory.fromUri(root.uri.resolve('pkgs/$name/'))
        ..createSync(recursive: true);
      File.fromUri(dir.uri.resolve('pubspec.yaml')).writeAsStringSync(
        'name: $name\n${version == null ? '' : 'version: $version\n'}',
      );
      entries.add({'name': name, 'rootUri': '../../pkgs/$name/'});
    });
    final config = File.fromUri(
      project.uri.resolve('.dart_tool/package_config.json'),
    )..createSync(recursive: true);
    config.writeAsStringSync(
      jsonEncode({'configVersion': 2, 'packages': entries}),
    );
  }

  test('no lockfile means no inventory, never a guess', () {
    expect(service.collect(project()), isNull);
  });

  test('a version both sources agree on is exact', () {
    final app = project();
    writeLock(app, lockEntry('kc2_sample', '1.2.3'));
    install(app, {'kc2_sample': '1.2.3'});

    final record = service.collect(app)!.records.single;
    expect(record.attestation, DependencyAttestation.exact);
    expect(record.lockedVersion, '1.2.3');
    expect(record.installedVersion, '1.2.3');
    expect(
      record.installedMetadataPath,
      endsWith('pkgs/kc2_sample/pubspec.yaml'),
    );
    expect(record.lockfilePath, endsWith('app/pubspec.lock'));
    expect(record.manifestPath, isNull, reason: 'no pubspec.yaml was written');
  });

  test('records the manifest that declares the dependency', () {
    final app = project();
    File.fromUri(
      app.uri.resolve('pubspec.yaml'),
    ).writeAsStringSync('name: app\n');
    writeLock(app, lockEntry('kc2_sample', '1.2.3'));
    install(app, {'kc2_sample': '1.2.3'});

    expect(
      service.collect(app)!.records.single.manifestPath,
      endsWith('app/pubspec.yaml'),
    );
  });

  test('a lockfile that disagrees with the installed package is a mismatch, '
      'and is not exact', () {
    final app = project();
    writeLock(app, lockEntry('kc2_sample', '2.0.0'));
    install(app, {'kc2_sample': '2.1.0'});

    final inventory = service.collect(app)!;
    expect(
      inventory.records.single.attestation,
      DependencyAttestation.mismatch,
    );
    expect(inventory.exact, isEmpty);
  });

  test('a package that is locked but not fetched is unverifiable', () {
    final app = project();
    writeLock(app, lockEntry('kc2_never_fetched_package', '1.0.0'));

    final record = service.collect(app)!.records.single;
    expect(record.attestation, DependencyAttestation.unverifiable);
    expect(record.installedVersion, isNull);
    expect(record.installedMetadataPath, isNull);
  });

  test('an installed package that declares no version is unverifiable', () {
    final app = project();
    writeLock(app, lockEntry('kc2_sample', '1.0.0'));
    install(app, {'kc2_sample': null});

    expect(
      service.collect(app)!.records.single.attestation,
      DependencyAttestation.unverifiable,
    );
  });

  test('only direct, non-SDK dependencies are listed, sorted by name', () {
    final app = project();
    writeLock(
      app,
      [
        lockEntry('zeta', '1.0.0'),
        lockEntry('alpha', '1.0.0', dependency: 'direct dev'),
        lockEntry('hidden', '1.0.0', dependency: 'transitive'),
        lockEntry('flutter', '0.0.0', source: 'sdk'),
      ].join(),
    );
    install(app, {'zeta': '1.0.0', 'alpha': '1.0.0', 'hidden': '1.0.0'});

    final inventory = service.collect(app)!;
    expect(inventory.records.map((r) => r.name), ['alpha', 'zeta']);
    expect(inventory.records.first.dependencyKind, 'direct dev');
    expect(inventory.exact.length, 2);
  });

  test('reads this repository, where riverpod is fetched and exact', () {
    final inventory = service.collect(Directory.current)!;
    final riverpod = inventory.records.firstWhere(
      (record) => record.name == 'flutter_riverpod',
    );
    expect(riverpod.attestation, DependencyAttestation.exact);
    expect(riverpod.installedVersion, riverpod.lockedVersion);
    expect(
      inventory.records.any((record) => record.name == 'flutter'),
      isFalse,
    );
  });
}
