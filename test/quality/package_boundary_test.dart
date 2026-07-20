import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

const String _catalogPath = 'tool/internal_package_catalog.json';
const Set<String> _supportedCodegenModes = <String>{'none', 'build_runner'};
const Map<String, _PackageProfilePolicy> _profilePolicies =
    <String, _PackageProfilePolicy>{
      'pure_dart': _PackageProfilePolicy(
        forbiddenDartLibraries: <String>{
          'dart:ffi',
          'dart:html',
          'dart:io',
          'dart:js',
          'dart:js_interop',
          'dart:ui',
        },
        forbiddenPackagePrefixes: <String>{
          'package:flutter/',
          'package:flutter_riverpod/',
          'package:hive/',
          'package:hive_flutter/',
          'package:path_provider/',
          'package:shared_preferences/',
        },
      ),
      'dart_io': _PackageProfilePolicy(
        forbiddenDartLibraries: <String>{
          'dart:ffi',
          'dart:html',
          'dart:js',
          'dart:js_interop',
          'dart:ui',
        },
        forbiddenPackagePrefixes: <String>{
          'package:flutter/',
          'package:flutter_riverpod/',
          'package:hive_flutter/',
          'package:path_provider/',
          'package:shared_preferences/',
        },
      ),
      'flutter_ui': _PackageProfilePolicy(
        forbiddenDartLibraries: <String>{
          'dart:ffi',
          'dart:html',
          'dart:io',
          'dart:js',
          'dart:js_interop',
        },
        forbiddenPackagePrefixes: <String>{
          'package:hive/',
          'package:hive_flutter/',
          'package:path_provider/',
          'package:shared_preferences/',
        },
      ),
      'platform_adapter': _PackageProfilePolicy(
        forbiddenDartLibraries: <String>{
          'dart:html',
          'dart:js',
          'dart:js_interop',
        },
        forbiddenPackagePrefixes: <String>{
          'package:flutter_riverpod/',
          'package:hive/',
          'package:hive_flutter/',
          'package:shared_preferences/',
        },
      ),
    };

final RegExp _directivePattern = RegExp(
  r'''^\s*(?:export|import|part)\s+(?!of\b)(.*?);''',
  multiLine: true,
  dotAll: true,
);
final RegExp _quotedUriPattern = RegExp(r'''['"]([^'"]+)['"]''');

void main() {
  final catalog = _InternalPackageCatalog.load();
  final rootPubspec = _parsePubspec(File('pubspec.yaml'));

  group('internal package catalog', () {
    test('matches discovered packages and root workspace members', () {
      final discoveredPaths = _discoverInternalPackagePaths();
      final catalogPaths = catalog.packages
          .map((package) => package.path)
          .toSet();
      final workspacePaths = (rootPubspec.workspace ?? const <String>[])
          .map(_normalizePath)
          .toSet();

      expect(
        catalogPaths,
        discoveredPaths,
        reason:
            'Every direct package under packages/ must be registered in '
            '$_catalogPath.',
      );
      expect(
        workspacePaths,
        catalogPaths,
        reason:
            'The root workspace and $_catalogPath must list the same package '
            'paths.',
      );
    });

    test('declares valid package metadata and public libraries', () {
      final names = <String>{};
      final paths = <String>{};

      for (final package in catalog.packages) {
        expect(
          names.add(package.name),
          isTrue,
          reason: 'Duplicate internal package name: ${package.name}.',
        );
        expect(
          paths.add(package.path),
          isTrue,
          reason: 'Duplicate internal package path: ${package.path}.',
        );
        expect(
          _profilePolicies.containsKey(package.profile),
          isTrue,
          reason:
              '${package.name} declares unsupported profile '
              '${package.profile}.',
        );
        expect(
          _supportedCodegenModes,
          contains(package.codegen),
          reason:
              '${package.name} declares unsupported codegen mode '
              '${package.codegen}.',
        );
        expect(
          package.owner.trim(),
          isNotEmpty,
          reason: '${package.name} must declare an owner.',
        );
        expect(
          package.purpose.trim(),
          isNotEmpty,
          reason: '${package.name} must declare its purpose.',
        );
        expect(
          package.consumers,
          isNotEmpty,
          reason: '${package.name} must declare its current consumers.',
        );
        expect(
          package.consumers.toSet().length,
          package.consumers.length,
          reason: '${package.name} contains duplicate consumers.',
        );
        expect(
          package.path,
          'packages/${package.name}',
          reason: 'Internal package paths must follow packages/<name>.',
        );

        final pubspecFile = File('${package.path}/pubspec.yaml');
        expect(
          pubspecFile.existsSync(),
          isTrue,
          reason: '${package.name} is missing pubspec.yaml.',
        );
        expect(
          File('${package.path}/README.md').existsSync(),
          isTrue,
          reason: '${package.name} is missing README.md.',
        );
        final pubspec = _parsePubspec(pubspecFile);
        expect(pubspec.name, package.name);
        expect(
          pubspec.publishTo,
          'none',
          reason: '${package.name} must not be published independently.',
        );
        expect(
          pubspec.resolution,
          'workspace',
          reason: '${package.name} must use the root Pub workspace.',
        );
        expect(
          pubspec.version,
          isNotNull,
          reason: '${package.name} must declare a version.',
        );

        final declaredLibraries = package.publicLibraries.toSet();
        expect(
          declaredLibraries.length,
          package.publicLibraries.length,
          reason: '${package.name} contains duplicate public libraries.',
        );
        expect(
          declaredLibraries,
          isNotEmpty,
          reason: '${package.name} must expose at least one public library.',
        );
        for (final library in declaredLibraries) {
          expect(
            library.startsWith('lib/') &&
                library.endsWith('.dart') &&
                !library.startsWith('lib/src/'),
            isTrue,
            reason:
                '$library must be a public Dart library below '
                '${package.path}/lib.',
          );
          expect(
            File('${package.path}/$library').existsSync(),
            isTrue,
            reason: '${package.name} declares missing library $library.',
          );
        }

        expect(
          _discoverPublicLibraries(package.path),
          declaredLibraries,
          reason:
              'Every exposed Dart library in ${package.path}/lib must be '
              'declared in $_catalogPath.',
        );
      }
    });

    test('uses versioned root dependencies for root package imports', () {
      final packagesByName = <String, _InternalPackage>{
        for (final package in catalog.packages) package.name: package,
      };
      final importedInternalPackages = <String>{};

      for (final file in _dartFilesUnder(Directory('lib'))) {
        for (final uri in _directiveUris(file.readAsStringSync())) {
          final packageName = _packageNameFromUri(uri);
          if (packageName != null && packagesByName.containsKey(packageName)) {
            importedInternalPackages.add(packageName);
          }
        }
      }

      for (final packageName in importedInternalPackages) {
        final dependency = rootPubspec.dependencies[packageName];
        expect(
          dependency,
          isA<HostedDependency>(),
          reason:
              'Root production code imports $packageName, so pubspec.yaml '
              'must declare a version constraint for it in dependencies.',
        );
        if (dependency is! HostedDependency) {
          continue;
        }

        expect(
          dependency.version.toString(),
          isNot('any'),
          reason: 'The root dependency on $packageName must be versioned.',
        );
        final packagePubspec = _parsePubspec(
          File('${packagesByName[packageName]!.path}/pubspec.yaml'),
        );
        final packageVersion = packagePubspec.version;
        expect(
          packageVersion,
          isNotNull,
          reason: '$packageName must declare a version.',
        );
        if (packageVersion != null) {
          expect(
            dependency.version.allows(packageVersion),
            isTrue,
            reason:
                'The root constraint ${dependency.version} does not allow '
                '$packageName $packageVersion.',
          );
        }
      }
    });

    test('keeps the internal production dependency graph acyclic', () {
      final packagesByName = <String, _InternalPackage>{
        for (final package in catalog.packages) package.name: package,
      };
      final graph = <String, Set<String>>{};

      for (final package in catalog.packages) {
        final pubspec = _parsePubspec(File('${package.path}/pubspec.yaml'));
        graph[package.name] = pubspec.dependencies.keys
            .where(packagesByName.containsKey)
            .toSet();
      }

      final cycle = _findDependencyCycle(graph);
      expect(
        cycle,
        isNull,
        reason: cycle == null
            ? null
            : 'Internal production dependency cycle: ${cycle.join(' -> ')}.',
      );
    });
  });

  group('internal package source boundaries', () {
    test('enforces declared profile and package privacy rules', () {
      final internalNames = catalog.packages
          .map((package) => package.name)
          .toSet();
      final violations = <String>[];

      for (final package in catalog.packages) {
        final policy = _profilePolicies[package.profile]!;
        final packageDirectory = Directory(package.path);
        final productionRoots = <Directory>[
          Directory('${package.path}/lib'),
          Directory('${package.path}/bin'),
        ];

        for (final root in productionRoots.where(
          (directory) => directory.existsSync(),
        )) {
          for (final file in _dartFilesUnder(root)) {
            for (final uri in _directiveUris(file.readAsStringSync())) {
              if (uri == 'package:caverno' ||
                  uri.startsWith('package:caverno/')) {
                violations.add(
                  '${file.path} crosses the package:caverno boundary through '
                  '$uri.',
                );
              }

              final importedPackage = _packageNameFromUri(uri);
              if (importedPackage != null &&
                  importedPackage != package.name &&
                  internalNames.contains(importedPackage) &&
                  uri.startsWith('package:$importedPackage/src/')) {
                violations.add(
                  '${file.path} imports private internal library $uri.',
                );
              }

              if (policy.forbiddenDartLibraries.contains(uri)) {
                violations.add(
                  '${file.path} imports $uri, which is forbidden for the '
                  '${package.profile} profile.',
                );
              }
              for (final prefix in policy.forbiddenPackagePrefixes) {
                if (uri.startsWith(prefix)) {
                  violations.add(
                    '${file.path} imports $uri, which is forbidden for the '
                    '${package.profile} profile.',
                  );
                }
              }

              if (!_hasUriScheme(uri) &&
                  !_isWithinLibraryRoot(file, uri, packageDirectory)) {
                violations.add(
                  '${file.path} escapes ${package.path}/lib through $uri.',
                );
              }
            }
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('does not expose private internal libraries to other consumers', () {
      final internalNames = catalog.packages
          .map((package) => package.name)
          .toSet();
      final sourceRoots = <Directory>[
        Directory('lib'),
        Directory('test'),
        Directory('integration_test'),
        Directory('tool'),
        Directory('packages'),
      ];
      final violations = <String>[];

      for (final root in sourceRoots.where(
        (directory) => directory.existsSync(),
      )) {
        for (final file in _dartFilesUnder(root)) {
          final owningPackage = _owningInternalPackage(file, catalog.packages);
          for (final uri in _directiveUris(file.readAsStringSync())) {
            final importedPackage = _packageNameFromUri(uri);
            if (importedPackage == null ||
                importedPackage == owningPackage ||
                !internalNames.contains(importedPackage) ||
                !uri.startsWith('package:$importedPackage/src/')) {
              continue;
            }
            violations.add('${file.path} imports private library $uri.');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('removes legacy runtime imports from the root application', () {
      final roots = <Directory>[
        Directory('lib'),
        Directory('test'),
        Directory('integration_test'),
        Directory('tool'),
      ];
      final legacyImport = RegExp(
        r'application/runtime/(?:caverno_execution_runtime|'
        r'caverno_runtime_event|caverno_runtime_failure_classifier|'
        r'caverno_runtime_ports)\.dart',
      );
      final offenders = <String>[];

      for (final root in roots.where((directory) => directory.existsSync())) {
        for (final file in _dartFilesUnder(root)) {
          if (legacyImport.hasMatch(file.readAsStringSync())) {
            offenders.add(file.path);
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Runtime consumers must import '
            'package:caverno_execution_runtime.',
      );
    });

    test('removes legacy content parser imports from the root application', () {
      final roots = <Directory>[
        Directory('lib'),
        Directory('test'),
        Directory('integration_test'),
        Directory('tool'),
      ];
      final legacyImport = RegExp(r'core/utils/content_parser\.dart');
      final offenders = <String>[];

      for (final root in roots.where((directory) => directory.existsSync())) {
        for (final file in _dartFilesUnder(root)) {
          if (legacyImport.hasMatch(file.readAsStringSync())) {
            offenders.add(file.path);
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Content parser consumers must import '
            'package:caverno_content_protocol.',
      );
    });

    test(
      'removes legacy tool contract ownership from the root application',
      () {
        final roots = <Directory>[
          Directory('lib'),
          Directory('test'),
          Directory('integration_test'),
          Directory('tool'),
        ];
        final legacyImport = RegExp(
          r'(?:core/security/tool_capability_classifier|'
          r'features/chat/domain/services/tool_approval_gate)\.dart',
        );
        final offenders = <String>[];

        for (final root in roots.where((directory) => directory.existsSync())) {
          for (final file in _dartFilesUnder(root)) {
            final source = file.readAsStringSync();
            if (legacyImport.hasMatch(source)) {
              offenders.add('${file.path} imports a legacy tool contract.');
            }
            if (file.path.endsWith('app_settings.dart') &&
                RegExp(r'enum\s+ToolApprovalMode\b').hasMatch(source)) {
              offenders.add('${file.path} owns ToolApprovalMode.');
            }
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'Tool contract consumers must import '
              'package:caverno_tool_contracts.',
        );
      },
    );
  });
}

Pubspec _parsePubspec(File file) {
  return Pubspec.parse(file.readAsStringSync(), sourceUrl: file.absolute.uri);
}

Set<String> _discoverInternalPackagePaths() {
  final packagesDirectory = Directory('packages');
  if (!packagesDirectory.existsSync()) {
    return const <String>{};
  }
  return packagesDirectory
      .listSync(followLinks: false)
      .whereType<Directory>()
      .where((directory) => File('${directory.path}/pubspec.yaml').existsSync())
      .map((directory) => _normalizePath(directory.path))
      .toSet();
}

Set<String> _discoverPublicLibraries(String packagePath) {
  final libDirectory = Directory('$packagePath/lib');
  if (!libDirectory.existsSync()) {
    return const <String>{};
  }
  final packageRoot = Directory(packagePath).absolute.path;
  return _dartFilesUnder(libDirectory)
      .map((file) => _relativePath(packageRoot, file.absolute.path))
      .where((path) => !path.startsWith('lib/src/'))
      .map(_normalizePath)
      .toSet();
}

List<File> _dartFilesUnder(Directory directory) {
  if (!directory.existsSync()) {
    return const <File>[];
  }
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}

Iterable<String> _directiveUris(String contents) sync* {
  for (final directive in _directivePattern.allMatches(contents)) {
    final body = directive.group(1)!;
    for (final uri in _quotedUriPattern.allMatches(body)) {
      yield uri.group(1)!;
    }
  }
}

String? _packageNameFromUri(String uri) {
  if (!uri.startsWith('package:')) {
    return null;
  }
  final slash = uri.indexOf('/', 'package:'.length);
  if (slash == -1) {
    return uri.substring('package:'.length);
  }
  return uri.substring('package:'.length, slash);
}

bool _hasUriScheme(String uri) => Uri.parse(uri).hasScheme;

bool _isWithinLibraryRoot(
  File source,
  String relativeUri,
  Directory packageDirectory,
) {
  final libraryRoot = Directory('${packageDirectory.path}/lib').absolute.path;
  final resolved = File.fromUri(
    source.absolute.uri.resolve(relativeUri),
  ).absolute.path;
  return resolved == libraryRoot ||
      resolved.startsWith('$libraryRoot${Platform.pathSeparator}');
}

String? _owningInternalPackage(File file, List<_InternalPackage> packages) {
  final filePath = file.absolute.path;
  for (final package in packages) {
    final packagePath = Directory(package.path).absolute.path;
    if (filePath.startsWith('$packagePath${Platform.pathSeparator}')) {
      return package.name;
    }
  }
  return null;
}

List<String>? _findDependencyCycle(Map<String, Set<String>> graph) {
  final visited = <String>{};
  final active = <String>[];
  final activeSet = <String>{};

  List<String>? visit(String package) {
    if (activeSet.contains(package)) {
      final cycleStart = active.indexOf(package);
      return <String>[...active.sublist(cycleStart), package];
    }
    if (!visited.add(package)) {
      return null;
    }

    active.add(package);
    activeSet.add(package);
    for (final dependency in graph[package] ?? const <String>{}) {
      final cycle = visit(dependency);
      if (cycle != null) {
        return cycle;
      }
    }
    active.removeLast();
    activeSet.remove(package);
    return null;
  }

  for (final package in graph.keys) {
    final cycle = visit(package);
    if (cycle != null) {
      return cycle;
    }
  }
  return null;
}

String _relativePath(String parent, String child) {
  final prefix = '$parent${Platform.pathSeparator}';
  if (!child.startsWith(prefix)) {
    throw ArgumentError.value(child, 'child', 'Path is outside $parent.');
  }
  return child.substring(prefix.length);
}

String _normalizePath(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

class _PackageProfilePolicy {
  const _PackageProfilePolicy({
    required this.forbiddenDartLibraries,
    required this.forbiddenPackagePrefixes,
  });

  final Set<String> forbiddenDartLibraries;
  final Set<String> forbiddenPackagePrefixes;
}

class _InternalPackageCatalog {
  const _InternalPackageCatalog({required this.packages});

  factory _InternalPackageCatalog.load() {
    final file = File(_catalogPath);
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (decoded['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported internal package catalog schema version.',
      );
    }
    final packages = (decoded['packages'] as List<dynamic>)
        .map(
          (entry) => _InternalPackage.fromJson(entry as Map<String, dynamic>),
        )
        .toList(growable: false);
    return _InternalPackageCatalog(packages: packages);
  }

  final List<_InternalPackage> packages;
}

class _InternalPackage {
  const _InternalPackage({
    required this.name,
    required this.path,
    required this.profile,
    required this.codegen,
    required this.owner,
    required this.purpose,
    required this.consumers,
    required this.publicLibraries,
  });

  factory _InternalPackage.fromJson(Map<String, dynamic> json) {
    return _InternalPackage(
      name: json['name'] as String,
      path: _normalizePath(json['path'] as String),
      profile: json['profile'] as String,
      codegen: json['codegen'] as String,
      owner: json['owner'] as String,
      purpose: json['purpose'] as String,
      consumers: (json['consumers'] as List<dynamic>).cast<String>(),
      publicLibraries: (json['publicLibraries'] as List<dynamic>)
          .cast<String>()
          .map(_normalizePath)
          .toList(growable: false),
    );
  }

  final String name;
  final String path;
  final String profile;
  final String codegen;
  final String owner;
  final String purpose;
  final List<String> consumers;
  final List<String> publicLibraries;
}
