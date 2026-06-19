import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/installed_dependency_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late InstalledDependencyGroundingService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'installed_dependency_grounding_test_',
    );
    service = const InstalledDependencyGroundingService();
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'resolves a Dart package from pubspec.lock and package_config',
    () async {
      final packageRoot = Directory.fromUri(
        root.uri.resolve('cache/sample_dep-1.2.3/'),
      )..createSync(recursive: true);
      File.fromUri(packageRoot.uri.resolve('README.md')).writeAsStringSync(
        '# sample_dep\n\nInstalled documentation for SampleApi.',
      );
      File.fromUri(packageRoot.uri.resolve('lib/sample_dep.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class SampleApi {}\n');
      Directory.fromUri(root.uri.resolve('.dart_tool/')).createSync();
      File.fromUri(
        root.uri.resolve('.dart_tool/package_config.json'),
      ).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'sample_dep',
              'rootUri': packageRoot.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.0',
            },
          ],
        }),
      );
      File.fromUri(root.uri.resolve('pubspec.lock')).writeAsStringSync('''
packages:
  sample_dep:
    dependency: "direct main"
    description:
      name: sample_dep
      sha256: abc
      url: "https://pub.dev"
    source: hosted
    version: "1.2.3"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');

      final decoded =
          jsonDecode(
                await service.resolve({
                  'project_path': root.path,
                  'ecosystem': 'dart',
                  'package_name': 'sample_dep',
                  'symbol': 'SampleApi',
                }),
              )
              as Map<String, dynamic>;

      expect(decoded['ok'], isTrue);
      expect(decoded['ecosystem'], 'dart');
      expect(decoded['lockfile_accuracy'], 'pubspec.lock');
      expect(decoded['offline_only'], isTrue);
      expect((decoded['package'] as Map<String, dynamic>)['version'], '1.2.3');
      expect(
        (decoded['documentation'] as Map<String, dynamic>)['excerpt'],
        contains('Installed documentation'),
      );
      final matches = decoded['matches'] as List<dynamic>;
      expect(
        matches.any(
          (match) =>
              (match as Map<String, dynamic>)['relative_path'] ==
                  'lib/sample_dep.dart' &&
              (match['text'] as String).contains('SampleApi'),
        ),
        isTrue,
      );
    },
  );

  test('finds a Dart symbol across locked packages', () async {
    final packageRoot = Directory.fromUri(
      root.uri.resolve('cache/alpha-1.0.0/'),
    )..createSync(recursive: true);
    File.fromUri(packageRoot.uri.resolve('lib/alpha.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void lockedOnlyApi() {}\n');
    Directory.fromUri(root.uri.resolve('.dart_tool/')).createSync();
    File.fromUri(
      root.uri.resolve('.dart_tool/package_config.json'),
    ).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'alpha',
            'rootUri': packageRoot.uri.toString(),
            'packageUri': 'lib/',
          },
        ],
      }),
    );
    File.fromUri(root.uri.resolve('pubspec.lock')).writeAsStringSync('''
packages:
  alpha:
    dependency: transitive
    description:
      name: alpha
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');

    final decoded =
        jsonDecode(
              await service.resolve({
                'project_path': root.path,
                'ecosystem': 'dart',
                'symbol': 'lockedOnlyApi',
              }),
            )
            as Map<String, dynamic>;

    expect(decoded['ok'], isTrue);
    expect((decoded['package'] as Map<String, dynamic>)['name'], 'alpha');
    expect((decoded['matches'] as List<dynamic>), isNotEmpty);
  });

  test('resolves a Node package from package-lock and node_modules', () async {
    final packageRoot = Directory.fromUri(
      root.uri.resolve('node_modules/@scope/tool/'),
    )..createSync(recursive: true);
    File.fromUri(packageRoot.uri.resolve('package.json')).writeAsStringSync(
      jsonEncode({'name': '@scope/tool', 'version': '2.0.0'}),
    );
    File.fromUri(
      packageRoot.uri.resolve('index.d.ts'),
    ).writeAsStringSync('export class ToolClient {}\n');
    File.fromUri(root.uri.resolve('package-lock.json')).writeAsStringSync(
      jsonEncode({
        'name': 'app',
        'lockfileVersion': 3,
        'packages': {
          '': {'name': 'app', 'version': '1.0.0'},
          'node_modules/@scope/tool': {
            'version': '2.0.0',
            'resolved': 'https://registry.npmjs.org/@scope/tool/-/tool.tgz',
            'integrity': 'sha512-test',
          },
        },
      }),
    );

    final decoded =
        jsonDecode(
              await service.resolve({
                'project_path': root.path,
                'ecosystem': 'node',
                'package_name': '@scope/tool',
                'symbol': 'ToolClient',
              }),
            )
            as Map<String, dynamic>;

    expect(decoded['ok'], isTrue);
    expect(decoded['lockfile_accuracy'], 'package-lock.json');
    expect((decoded['package'] as Map<String, dynamic>)['version'], '2.0.0');
    expect(
      ((decoded['matches'] as List<dynamic>).single
          as Map<String, dynamic>)['text'],
      contains('ToolClient'),
    );
  });

  test(
    'resolves a Python package from requirements and site-packages',
    () async {
      File.fromUri(
        root.uri.resolve('requirements.txt'),
      ).writeAsStringSync('requests==2.31.0\n');
      final sitePackages = Directory.fromUri(
        root.uri.resolve('.venv/lib/python3.11/site-packages/'),
      )..createSync(recursive: true);
      final packageRoot = Directory.fromUri(
        sitePackages.uri.resolve('requests/'),
      )..createSync(recursive: true);
      File.fromUri(
        packageRoot.uri.resolve('README.md'),
      ).writeAsStringSync('Installed requests docs mention Session.');
      File.fromUri(
        packageRoot.uri.resolve('api.py'),
      ).writeAsStringSync('class Session:\n    pass\n');
      final distInfo = Directory.fromUri(
        sitePackages.uri.resolve('requests-2.31.0.dist-info/'),
      )..createSync();
      File.fromUri(
        distInfo.uri.resolve('top_level.txt'),
      ).writeAsStringSync('requests\n');

      final decoded =
          jsonDecode(
                await service.resolve({
                  'project_path': root.path,
                  'ecosystem': 'python',
                  'package_name': 'requests',
                  'symbol': 'Session',
                }),
              )
              as Map<String, dynamic>;

      expect(decoded['ok'], isTrue);
      expect(decoded['lockfile_accuracy'], 'requirements.txt');
      expect((decoded['package'] as Map<String, dynamic>)['version'], '2.31.0');
      final matches = decoded['matches'] as List<dynamic>;
      expect(
        matches.any(
          (match) =>
              (match as Map<String, dynamic>)['relative_path'] == 'api.py' &&
              (match['text'] as String).contains('Session'),
        ),
        isTrue,
      );
    },
  );

  test(
    'returns an error instead of using online docs for missing packages',
    () async {
      File.fromUri(root.uri.resolve('pubspec.lock')).writeAsStringSync('''
packages:
  locked_dep:
    dependency: transitive
    description:
      name: locked_dep
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');

      final decoded =
          jsonDecode(
                await service.resolve({
                  'project_path': root.path,
                  'ecosystem': 'dart',
                  'package_name': 'missing_dep',
                }),
              )
              as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['code'], 'dependency_not_resolved');
      final attempts = decoded['attempted_ecosystems'] as List<dynamic>;
      expect(
        (attempts.single as Map<String, dynamic>)['code'],
        'locked_package_not_found',
      );
    },
  );
}
