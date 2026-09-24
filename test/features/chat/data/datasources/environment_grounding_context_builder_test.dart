import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/dependency_inventory.dart';
import 'package:caverno/features/chat/data/datasources/environment_grounding_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// KC2 slice 2: the block a coding prompt will carry. Defended here: every
/// version it states is attested by two sources, its bytes are stable while
/// the files are, and it stays inside the ~400-token budget.
void main() {
  late Directory root;
  late Directory app;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kc2_block_test_');
    app = Directory.fromUri(root.uri.resolve('app/'))
      ..createSync(recursive: true);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  String lockEntry(
    String name,
    String version, {
    String dependency = 'direct main',
  }) =>
      '''
  $name:
    dependency: "$dependency"
    description:
      name: $name
      url: "https://pub.dev"
    source: hosted
    version: "$version"
''';

  /// Writes a project resolved by a fake SDK: the lockfile, the installed
  /// packages with their declared versions, package_config.json, and the
  /// SDK's own version file.
  void project({
    required Map<String, (String locked, String? installed, String kind)>
    packages,
    String resolvedFlutter = '3.47.4',
    String sdkFlutter = '3.47.4',
    String resolvedDart = '3.13.3',
    String sdkDart = '3.13.3',
  }) {
    File.fromUri(
      app.uri.resolve('pubspec.yaml'),
    ).writeAsStringSync('name: app\n');
    File.fromUri(app.uri.resolve('pubspec.lock')).writeAsStringSync(
      'packages:\n${[for (final e in packages.entries) lockEntry(e.key, e.value.$1, dependency: e.value.$3)].join()}'
      'sdks:\n  dart: ">=3.0.0"\n',
    );
    final entries = <Map<String, Object>>[];
    packages.forEach((name, spec) {
      final dir = Directory.fromUri(root.uri.resolve('pkgs/$name/'))
        ..createSync(recursive: true);
      File.fromUri(dir.uri.resolve('pubspec.yaml')).writeAsStringSync(
        'name: $name\n${spec.$2 == null ? '' : 'version: ${spec.$2}\n'}',
      );
      entries.add({'name': name, 'rootUri': '../../pkgs/$name/'});
    });
    final sdk = Directory.fromUri(root.uri.resolve('sdk/'));
    File.fromUri(sdk.uri.resolve('bin/cache/flutter.version.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'frameworkVersion': sdkFlutter, 'dartSdkVersion': sdkDart}),
      );
    File.fromUri(app.uri.resolve('.dart_tool/package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': entries,
          'generatorVersion': resolvedDart,
          'flutterRoot': sdk.uri.toString(),
          'flutterVersion': resolvedFlutter,
        }),
      );
  }

  test('renders only attested versions, in a fixed shape', () {
    project(
      packages: {
        'zeta': ('2.0.0', '2.0.0', 'direct main'),
        'alpha': ('1.0.0', '1.0.0', 'direct main'),
        'lint_kit': ('5.0.0', '5.0.0', 'direct dev'),
        'drifted': ('1.0.0', '1.1.0', 'direct main'),
        'hidden': ('9.9.9', '9.9.9', 'transitive'),
      },
    );

    expect(
      EnvironmentGroundingContextBuilder().build(app.path),
      '${EnvironmentGroundingContextBuilder.heading}\n'
      '- Flutter SDK 3.47.4, Dart SDK 3.13.3\n'
      '- Dependencies: alpha 1.0.0, zeta 2.0.0\n'
      '- Dev dependencies: lint_kit 5.0.0\n'
      '- Versions withheld, not attested: drifted (lockfile and installed '
      'package disagree)',
    );
  });

  test('no lockfile, no block', () {
    expect(EnvironmentGroundingContextBuilder().build(app.path), isNull);
  });

  test('a mismatched version is named but never stated', () {
    project(packages: {'drifted': ('1.0.0', '1.1.0', 'direct main')});
    final block = EnvironmentGroundingContextBuilder().build(app.path)!;
    expect(
      block,
      contains('drifted (lockfile and installed package disagree)'),
    );
    expect(block, isNot(contains('1.0.0')));
    expect(block, isNot(contains('1.1.0')));
  });

  test('an unfetched package is labeled unreadable, with no version', () {
    File.fromUri(app.uri.resolve('pubspec.lock')).writeAsStringSync(
      'packages:\n${lockEntry('kc2_never_fetched_package', '1.0.0')}',
    );
    final block = EnvironmentGroundingContextBuilder().build(app.path)!;
    expect(
      block,
      contains('kc2_never_fetched_package (installed version unreadable)'),
    );
    expect(block, isNot(contains('1.0.0')));
    expect(
      block,
      isNot(contains('Flutter SDK')),
      reason: 'no package_config.json means no toolchain attestation',
    );
  });

  test('an SDK that disagrees with what pub resolved withholds its line', () {
    project(
      packages: {'alpha': ('1.0.0', '1.0.0', 'direct main')},
      resolvedFlutter: '3.47.4',
      sdkFlutter: '3.47.5',
    );
    final block = EnvironmentGroundingContextBuilder().build(app.path)!;
    expect(block, isNot(contains('Flutter SDK')));
    expect(block, contains('- Dart SDK 3.13.3'));
  });

  test('two builds are byte-identical and the second reads nothing', () {
    project(packages: {'alpha': ('1.0.0', '1.0.0', 'direct main')});
    var collected = 0;
    final builder = EnvironmentGroundingContextBuilder(
      collect: (dir) {
        collected++;
        return const DependencyInventoryService().collect(dir);
      },
    );
    final first = builder.build(app.path);
    final second = builder.build(app.path);
    expect(second, first);
    expect(collected, 1);
  });

  test('a lockfile change rebuilds the block', () {
    project(packages: {'alpha': ('1.0.0', '1.0.0', 'direct main')});
    var collected = 0;
    final builder = EnvironmentGroundingContextBuilder(
      collect: (dir) {
        collected++;
        return const DependencyInventoryService().collect(dir);
      },
    );
    final before = builder.build(app.path)!;
    // A longer version, so the lockfile's size changes as well as its mtime.
    project(packages: {'alpha': ('1.10.0', '1.10.0', 'direct main')});
    final after = builder.build(app.path)!;
    expect(collected, 2);
    expect(before, contains('alpha 1.0.0'));
    expect(after, contains('alpha 1.10.0'));
  });

  test('stays inside the budget and says what it cut', () {
    project(
      packages: {
        for (var i = 0; i < 200; i++)
          'package_number_${i.toString().padLeft(3, '0')}': (
            '1.0.0',
            '1.0.0',
            i.isEven ? 'direct main' : 'direct dev',
          ),
      },
    );
    final block = EnvironmentGroundingContextBuilder().build(app.path)!;
    expect(block.length, lessThanOrEqualTo(1600));
    expect(
      block,
      matches(RegExp(r'\(\d+ more direct dependencies not listed\)')),
    );
    expect(
      block,
      contains('package_number_000 1.0.0'),
      reason: 'the cut keeps a prefix, main dependencies first',
    );
  });

  test('this repository fits the budget and names its resolved SDK', () {
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final block = EnvironmentGroundingContextBuilder().build(
      Directory.current.path,
    )!;
    expect(block.length, lessThanOrEqualTo(1600));
    expect(block, contains('Flutter SDK ${config['flutterVersion']}'));
    expect(block, isNot(contains('Versions withheld')));
  });
}
