import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/agents_md_loader.dart';

void main() {
  group('AgentsMdLoader', () {
    late Directory tempDir;
    late AgentsMdLoader loader;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('agents_md_loader_test_');
      loader = AgentsMdLoader();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns null when rootPath is null or empty', () {
      expect(loader.loadForProject(null), isNull);
      expect(loader.loadForProject(''), isNull);
      expect(loader.loadForProject('   '), isNull);
    });

    test('returns null when AGENTS.md is absent', () {
      expect(loader.loadForProject(tempDir.path), isNull);
    });

    test('returns AGENTS.md content when present', () {
      File('${tempDir.path}/AGENTS.md')
          .writeAsStringSync('Use pnpm, never npm.');
      expect(loader.loadForProject(tempDir.path), 'Use pnpm, never npm.');
    });

    test('AGENTS.override.md wins over AGENTS.md', () {
      File('${tempDir.path}/AGENTS.md').writeAsStringSync('Base rules.');
      File('${tempDir.path}/AGENTS.override.md')
          .writeAsStringSync('Override rules.');
      expect(loader.loadForProject(tempDir.path), 'Override rules.');
    });

    test('empty AGENTS.md is treated as absent', () {
      File('${tempDir.path}/AGENTS.md').writeAsStringSync('');
      expect(loader.loadForProject(tempDir.path), isNull);
    });

    test('content over 32 KiB is truncated with a marker', () {
      final huge = 'A' * (AgentsMdLoader.maxBytes + 1024);
      File('${tempDir.path}/AGENTS.md').writeAsStringSync(huge);

      final result = loader.loadForProject(tempDir.path);
      expect(result, isNotNull);
      expect(result!.startsWith('A' * 100), isTrue);
      expect(result.length, greaterThan(AgentsMdLoader.maxBytes));
      expect(result, contains('truncated'));
    });

    test('cache invalidates when mtime changes', () async {
      final file = File('${tempDir.path}/AGENTS.md');
      file.writeAsStringSync('first');
      expect(loader.loadForProject(tempDir.path), 'first');

      // Bump mtime forward beyond filesystem timestamp granularity so the
      // statSync comparison reliably detects a change.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      file.writeAsStringSync('second');
      expect(loader.loadForProject(tempDir.path), 'second');
    });

    test('invalidate clears cache for a specific root', () {
      final file = File('${tempDir.path}/AGENTS.md');
      file.writeAsStringSync('cached');
      expect(loader.loadForProject(tempDir.path), 'cached');

      file.writeAsStringSync('replaced');
      loader.invalidate(tempDir.path);
      expect(loader.loadForProject(tempDir.path), 'replaced');
    });

    test('returns null when an override file directory mismatch occurs', () {
      // AGENTS.override.md present but unreadable as a regular file
      // (e.g. a directory by that name) → fall back to AGENTS.md.
      Directory('${tempDir.path}/AGENTS.override.md').createSync();
      File('${tempDir.path}/AGENTS.md').writeAsStringSync('Primary rules.');

      expect(loader.loadForProject(tempDir.path), 'Primary rules.');
    });
  });
}
