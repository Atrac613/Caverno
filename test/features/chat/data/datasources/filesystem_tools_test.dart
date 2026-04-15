import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filesystem_tools_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resolvePath uses project root for relative paths', () {
    final resolved = FilesystemTools.resolvePath(
      'lib/main.dart',
      defaultRoot: tempDir.path,
    );

    expect(resolved, isNotNull);
    expect(
      resolved,
      endsWith(
        '${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
      ),
    );
  });

  test('write, read, and edit file round-trip', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}sample.txt';

    final writeResult =
        jsonDecode(
              await FilesystemTools.writeFile(
                path: targetPath,
                content: 'hello world',
              ),
            )
            as Map<String, dynamic>;
    expect(writeResult['created'], isTrue);

    final readResult =
        jsonDecode(await FilesystemTools.readFile(path: targetPath))
            as Map<String, dynamic>;
    expect(readResult['content'], 'hello world');

    final editResult =
        jsonDecode(
              await FilesystemTools.editFile(
                path: targetPath,
                oldText: 'world',
                newText: 'agent',
              ),
            )
            as Map<String, dynamic>;
    expect(editResult['replacements'], 1);

    final updated = await File(targetPath).readAsString();
    expect(updated, 'hello agent');
  });

  test('findFiles and searchFiles return project matches', () async {
    final libDir = Directory('${tempDir.path}${Platform.pathSeparator}lib')
      ..createSync(recursive: true);
    final testDir = Directory('${tempDir.path}${Platform.pathSeparator}test')
      ..createSync(recursive: true);

    await File(
      '${libDir.path}${Platform.pathSeparator}alpha.dart',
    ).writeAsString('class Alpha {}\nfinal value = 1;\n');
    await File(
      '${testDir.path}${Platform.pathSeparator}alpha_test.dart',
    ).writeAsString('Alpha value\n');

    final findResult =
        jsonDecode(
              await FilesystemTools.findFiles(
                path: tempDir.path,
                pattern: '*alpha*',
              ),
            )
            as Map<String, dynamic>;
    final findMatches = (findResult['matches'] as List<dynamic>).cast<String>();
    expect(findMatches, contains('lib${Platform.pathSeparator}alpha.dart'));
    expect(
      findMatches,
      contains('test${Platform.pathSeparator}alpha_test.dart'),
    );

    final searchResult =
        jsonDecode(
              await FilesystemTools.searchFiles(
                path: tempDir.path,
                query: 'Alpha',
                filePattern: '*.dart',
              ),
            )
            as Map<String, dynamic>;
    final searchMatches = (searchResult['matches'] as List<dynamic>)
        .cast<String>();
    expect(searchMatches, isNotEmpty);
    expect(
      searchMatches.any((match) => match.contains('alpha.dart:1')),
      isTrue,
    );
  });

  test('buildWriteDiffPreview returns a unified diff for text changes', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}diff_sample.txt';
    final file = File(targetPath);
    file.createSync(recursive: true);
    file.writeAsStringSync('hello world\nline two\n');

    final preview = await FilesystemTools.buildWriteDiffPreview(
      path: targetPath,
      newContent: 'hello agent\nline two\n',
    );

    expect(preview, contains('--- $targetPath'));
    expect(preview, contains('+++ $targetPath'));
    expect(preview, contains('-hello world'));
    expect(preview, contains('+hello agent'));
  });

  test(
    'writeFile returns structured error payload on filesystem failure',
    () async {
      final directoryTarget = Directory(
        '${tempDir.path}${Platform.pathSeparator}existing_dir',
      )..createSync(recursive: true);

      final result =
          jsonDecode(
                await FilesystemTools.writeFile(
                  path: directoryTarget.path,
                  content: 'hello world',
                ),
              )
              as Map<String, dynamic>;

      expect(result['error'], isNotNull);
      expect(result['code'], 'filesystem_error');
      expect(result['path'], directoryTarget.absolute.path);
    },
  );
}
