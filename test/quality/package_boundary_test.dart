import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _runtimePackagePath = 'packages/caverno_execution_runtime';
const Set<String> _forbiddenDartLibraries = <String>{
  'dart:ffi',
  'dart:html',
  'dart:io',
  'dart:ui',
};
const List<String> _forbiddenPackagePrefixes = <String>[
  'package:caverno/',
  'package:flutter/',
  'package:flutter_riverpod/',
  'package:hive/',
  'package:hive_flutter/',
  'package:path_provider/',
  'package:shared_preferences/',
];

final RegExp _directivePattern = RegExp(
  r'''^(?:export|import)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

void main() {
  group('internal package boundaries', () {
    test('registers the execution runtime as a path dependency', () {
      final rootPubspec = File('pubspec.yaml').readAsStringSync();
      final packagePubspec = File(
        '$_runtimePackagePath/pubspec.yaml',
      ).readAsStringSync();

      expect(
        rootPubspec,
        contains('path: packages/caverno_execution_runtime'),
      );
      expect(packagePubspec, contains('name: caverno_execution_runtime'));
      expect(packagePubspec, contains('publish_to: none'));
      expect(packagePubspec, isNot(contains('\ndependencies:')));
    });

    test('keeps the execution runtime platform-neutral and one-way', () {
      final packageLib = Directory('$_runtimePackagePath/lib');
      expect(packageLib.existsSync(), isTrue);

      final packageLibRoot = packageLib.absolute.path;
      final dartFiles = packageLib
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList(growable: false);
      expect(dartFiles, isNotEmpty);

      for (final file in dartFiles) {
        final contents = file.readAsStringSync();
        for (final match in _directivePattern.allMatches(contents)) {
          final uri = match.group(1)!;
          expect(
            _forbiddenDartLibraries,
            isNot(contains(uri)),
            reason: '${file.path} imports platform library $uri.',
          );
          for (final prefix in _forbiddenPackagePrefixes) {
            expect(
              uri.startsWith(prefix),
              isFalse,
              reason: '${file.path} crosses the forbidden $prefix boundary.',
            );
          }
          if (uri.contains(':')) {
            continue;
          }

          final resolvedPath = File.fromUri(
            file.absolute.uri.resolve(uri),
          ).absolute.path;
          expect(
            resolvedPath.startsWith('$packageLibRoot${Platform.pathSeparator}'),
            isTrue,
            reason: '${file.path} escapes its package through $uri.',
          );
        }
      }
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
        for (final file in root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
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
  });
}
