import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/repo_map_precompute_cache.dart';
import 'package:caverno/features/chat/domain/services/repo_map_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('repo_map_precompute_test_');
    _writeFile(tempDir, 'pubspec.yaml', 'name: example\n');
    _writeFile(tempDir, 'lib/main.dart', 'class AppRoot {}\n');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('RepoMapService.computeSignatureForProject', () {
    test('returns null for an empty or missing root', () {
      expect(RepoMapService.computeSignatureForProject(rootPath: null), isNull);
      expect(RepoMapService.computeSignatureForProject(rootPath: ''), isNull);
      expect(
        RepoMapService.computeSignatureForProject(
          rootPath: '${tempDir.path}/does-not-exist',
        ),
        isNull,
      );
    });

    test('is stable across calls when the project is unchanged', () {
      final first = RepoMapService.computeSignatureForProject(
        rootPath: tempDir.path,
      );
      final second = RepoMapService.computeSignatureForProject(
        rootPath: tempDir.path,
      );
      expect(first, isNotNull);
      expect(second, first);
    });

    test('changes when a tracked file is edited', () {
      final before = RepoMapService.computeSignatureForProject(
        rootPath: tempDir.path,
      );
      _writeFile(
        tempDir,
        'lib/main.dart',
        'class AppRoot {}\nclass Extra {}\n',
      );
      final after = RepoMapService.computeSignatureForProject(
        rootPath: tempDir.path,
      );
      expect(after, isNot(before));
    });

    test('changes when the effective context budget changes', () {
      final small = RepoMapService.computeSignatureForProject(
        rootPath: tempDir.path,
        usableContextTokens: 2000,
      );
      final large = RepoMapService.computeSignatureForProject(
        rootPath: tempDir.path,
        usableContextTokens: 32000,
      );
      expect(small, isNot(large));
    });
  });

  group('RepoMapPrecomputeCache', () {
    test('precompute reports computed then alreadyWarm without changes', () {
      final cache = RepoMapPrecomputeCache();
      expect(
        cache.precompute(rootPath: tempDir.path),
        RepoMapPrecomputeResult.computed,
      );
      expect(
        cache.precompute(rootPath: tempDir.path),
        RepoMapPrecomputeResult.alreadyWarm,
      );
    });

    test('getOrBuild returns the same map a precompute warmed', () {
      final cache = RepoMapPrecomputeCache();
      cache.precompute(rootPath: tempDir.path);
      final built = RepoMapService.buildForProject(rootPath: tempDir.path);
      expect(cache.getOrBuild(rootPath: tempDir.path), built);
    });

    test('invalidates and rebuilds after a file edit', () {
      final cache = RepoMapPrecomputeCache();
      final before = cache.getOrBuild(rootPath: tempDir.path);

      _writeFile(
        tempDir,
        'lib/feature.dart',
        'class BrandNewFeature {}\nclass AnotherFeature {}\n',
      );

      // The signature now differs, so a precompute does real work again.
      expect(
        cache.precompute(rootPath: tempDir.path),
        RepoMapPrecomputeResult.computed,
      );
      final after = cache.getOrBuild(rootPath: tempDir.path);
      expect(after, isNot(before));
      expect(after, contains('BrandNewFeature'));
    });

    test('reports noProject and caches nothing for a missing root', () {
      final cache = RepoMapPrecomputeCache();
      expect(
        cache.precompute(rootPath: '${tempDir.path}/missing'),
        RepoMapPrecomputeResult.noProject,
      );
      expect(cache.getOrBuild(rootPath: '${tempDir.path}/missing'), isNull);
    });

    test('invalidate drops a warmed entry so the next call recomputes', () {
      final cache = RepoMapPrecomputeCache();
      expect(
        cache.precompute(rootPath: tempDir.path),
        RepoMapPrecomputeResult.computed,
      );
      cache.invalidate(tempDir.path);
      expect(
        cache.precompute(rootPath: tempDir.path),
        RepoMapPrecomputeResult.computed,
      );
    });
  });
}

void _writeFile(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
