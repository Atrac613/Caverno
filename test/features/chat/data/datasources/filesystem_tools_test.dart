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

  test('resolvePath expands home-relative paths', () {
    if (Platform.isWindows) {
      return;
    }

    final home = Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) {
      return;
    }

    final resolved = FilesystemTools.resolvePath(
      '~/.caverno/session_logs',
      defaultRoot: tempDir.path,
    );

    expect(
      resolved,
      '${Directory(home).absolute.path}${Platform.pathSeparator}.caverno${Platform.pathSeparator}session_logs',
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

  test('editFile reports no_change when new_text equals old_text', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}noop.txt';
    await FilesystemTools.writeFile(path: targetPath, content: 'hello world');

    final editResult =
        jsonDecode(
              await FilesystemTools.editFile(
                path: targetPath,
                oldText: 'world',
                newText: 'world',
              ),
            )
            as Map<String, dynamic>;

    expect(editResult['error'], 'no_change');
    expect(editResult.containsKey('replacements'), isFalse);
    // The file must be left untouched.
    expect(await File(targetPath).readAsString(), 'hello world');
  });

  test('editFile not-found error echoes content and an actionable hint for '
      'small files', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}arrow.dart';
    final file = File(targetPath)..createSync(recursive: true);
    // An arrow function, as a live canary fixture writes it. A model that
    // assumes a `  return '...';` block body will miss with old_text.
    file.writeAsStringSync("String canaryValue() => 'BROKEN';\n");

    final editResult =
        jsonDecode(
              await FilesystemTools.editFile(
                path: targetPath,
                oldText: "  return 'BROKEN';",
                newText: "  return 'OK';",
              ),
            )
            as Map<String, dynamic>;

    // The exact phrase tool-loop recovery / telemetry match on is preserved.
    expect(editResult['error'], 'old_text was not found in the target file');
    // Small files echo their current content so the model can copy old_text
    // verbatim (or overwrite via write_file) without another read_file.
    expect(editResult['current_content'], "String canaryValue() => 'BROKEN';\n");
    expect(editResult['hint'], contains('write_file'));
    expect(editResult['hint'], contains('verbatim'));

    // The file is left untouched on a failed edit.
    expect(
      await File(targetPath).readAsString(),
      "String canaryValue() => 'BROKEN';\n",
    );
  });

  test('editFile not-found error omits inline content for large files', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}big.dart';
    final file = File(targetPath)..createSync(recursive: true);
    file.writeAsStringSync('// padding\n' * 1000); // > 4 KiB

    final editResult =
        jsonDecode(
              await FilesystemTools.editFile(
                path: targetPath,
                oldText: 'does-not-exist',
                newText: 'whatever',
              ),
            )
            as Map<String, dynamic>;

    expect(editResult['error'], 'old_text was not found in the target file');
    expect(editResult.containsKey('current_content'), isFalse);
    expect(editResult['hint'], contains('Re-read'));
  });

  test('readFile returns requested line range metadata', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}range_sample.txt';
    final file = File(targetPath);
    file.createSync(recursive: true);
    file.writeAsStringSync('one\ntwo\nthree\nfour\n');

    final readResult =
        jsonDecode(
              await FilesystemTools.readFile(
                path: targetPath,
                offset: 2,
                limit: 2,
              ),
            )
            as Map<String, dynamic>;

    expect(readResult['content'], 'two\nthree');
    expect(readResult['start_line'], 2);
    expect(readResult['line_count'], 2);
    expect(readResult['total_lines'], 4);
    expect(readResult['truncated_by_limit'], isTrue);
  });

  test('readFile reports empty content for an out-of-range offset', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}short_sample.txt';
    final file = File(targetPath);
    file.createSync(recursive: true);
    file.writeAsStringSync('one\ntwo\n');

    final readResult =
        jsonDecode(await FilesystemTools.readFile(path: targetPath, offset: 10))
            as Map<String, dynamic>;

    expect(readResult['content'], '');
    expect(readResult['start_line'], 10);
    expect(readResult['line_count'], 0);
    expect(readResult['total_lines'], 2);
    expect(readResult.containsKey('truncated'), isFalse);
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

  test('searchFiles paginates matching lines with offset', () async {
    final libDir = Directory('${tempDir.path}${Platform.pathSeparator}lib')
      ..createSync(recursive: true);
    await File(
      '${libDir.path}${Platform.pathSeparator}matches.txt',
    ).writeAsString('needle one\nneedle two\nneedle three\nneedle four\n');

    final searchResult =
        jsonDecode(
              await FilesystemTools.searchFiles(
                path: tempDir.path,
                query: 'needle',
                maxResults: 2,
                offset: 1,
              ),
            )
            as Map<String, dynamic>;
    final searchMatches = (searchResult['matches'] as List<dynamic>)
        .cast<String>();

    expect(searchMatches, hasLength(2));
    expect(searchMatches.first, contains('matches.txt:2'));
    expect(searchMatches.last, contains('matches.txt:3'));
    expect(searchResult['offset'], 1);
    expect(searchResult['matches_seen'], 3);
    expect(searchResult['truncated'], isTrue);
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

  test(
    'readFile streams a large file and returns a correct late window',
    () async {
      final targetPath = '${tempDir.path}${Platform.pathSeparator}big.log';
      final file = File(targetPath)..createSync(recursive: true);
      final sink = file.openWrite();
      const totalLines = 20000;
      for (var i = 1; i <= totalLines; i++) {
        sink.writeln('line $i');
      }
      await sink.close();
      const offset = totalLines - 2;

      final readResult =
          jsonDecode(
                await FilesystemTools.readFile(
                  path: targetPath,
                  offset: offset,
                  limit: 2,
                ),
              )
              as Map<String, dynamic>;

      expect(readResult['content'], 'line $offset\nline ${offset + 1}');
      expect(readResult['start_line'], offset);
      expect(readResult['line_count'], 2);
      expect(readResult['total_lines'], totalLines);
      expect(readResult['size_bytes'], await file.length());
      expect(readResult['truncated_by_limit'], isTrue);
    },
  );

  test('readFile and inspectFile reject binary content', () async {
    final targetPath = '${tempDir.path}${Platform.pathSeparator}data.bin';
    final file = File(targetPath)..createSync(recursive: true);
    file.writeAsBytesSync([72, 105, 0, 1, 2, 3, 255]); // contains a NUL byte

    final readResult =
        jsonDecode(await FilesystemTools.readFile(path: targetPath))
            as Map<String, dynamic>;
    expect(readResult['error'], contains('Binary'));

    final inspectResult =
        jsonDecode(await FilesystemTools.inspectFile(path: targetPath))
            as Map<String, dynamic>;
    expect(inspectResult['is_binary'], isTrue);
  });

  test('readFile truncates a single huge line by max_chars', () async {
    final targetPath = '${tempDir.path}${Platform.pathSeparator}oneline.txt';
    final file = File(targetPath)..createSync(recursive: true);
    file.writeAsStringSync('x' * 50000); // one line, no trailing newline

    final readResult =
        jsonDecode(
              await FilesystemTools.readFile(path: targetPath, maxChars: 1000),
            )
            as Map<String, dynamic>;

    expect(readResult['total_lines'], 1);
    expect((readResult['content'] as String).length, 1000);
    expect(readResult['truncated_by_chars'], isTrue);
  });

  test(
    'readFile stays bounded on a single line larger than the carry cap',
    () async {
      final targetPath = '${tempDir.path}${Platform.pathSeparator}giant.txt';
      final file = File(targetPath)..createSync(recursive: true);
      // 3 MB single line, no newline — exceeds the 1 MB per-line carry cap.
      file.writeAsStringSync('z' * (3 * 1024 * 1024));

      final readResult =
          jsonDecode(
                await FilesystemTools.readFile(path: targetPath, maxChars: 500),
              )
              as Map<String, dynamic>;

      expect(readResult['total_lines'], 1);
      expect((readResult['content'] as String).length, 500);
      expect(readResult['truncated_by_chars'], isTrue);
      expect(readResult['size_bytes'], 3 * 1024 * 1024);
    },
  );

  test('inspectFile returns head, tail, size and format hint', () async {
    final targetPath = '${tempDir.path}${Platform.pathSeparator}records.jsonl';
    final file = File(targetPath)..createSync(recursive: true);
    final sink = file.openWrite();
    for (var i = 1; i <= 500; i++) {
      sink.writeln('{"i": $i}');
    }
    await sink.close();

    final result =
        jsonDecode(
              await FilesystemTools.inspectFile(
                path: targetPath,
                headLines: 3,
                tailLines: 2,
              ),
            )
            as Map<String, dynamic>;

    expect(result['is_binary'], isFalse);
    expect(result['total_lines'], 500);
    expect(result['format_hint'], 'jsonl');
    expect((result['head'] as List).length, 3);
    expect((result['head'] as List).first, '{"i": 1}');
    expect((result['tail'] as List).length, 2);
    expect((result['tail'] as List).last, '{"i": 500}');
    expect(result['size_bytes'], await file.length());
  });

  test('searchFiles matches inside files larger than 1MB', () async {
    final libDir = Directory('${tempDir.path}${Platform.pathSeparator}lib')
      ..createSync(recursive: true);
    final bigPath = '${libDir.path}${Platform.pathSeparator}big.log';
    final file = File(bigPath);
    final sink = file.openWrite();
    for (var i = 0; i < 60000; i++) {
      sink.writeln('filler line padding padding padding $i');
    }
    sink.writeln('the special NEEDLE marker is here');
    await sink.close();
    expect(await file.length(), greaterThan(1024 * 1024));

    final result =
        jsonDecode(
              await FilesystemTools.searchFiles(
                path: tempDir.path,
                query: 'NEEDLE',
              ),
            )
            as Map<String, dynamic>;
    final matches = (result['matches'] as List).cast<String>();
    expect(matches, isNotEmpty);
    expect(matches.first, contains('NEEDLE'));
  });

  test('searchFiles honors max_line_length and max_bytes_scanned', () async {
    final libDir = Directory('${tempDir.path}${Platform.pathSeparator}lib')
      ..createSync(recursive: true);
    final filePath = '${libDir.path}${Platform.pathSeparator}wide.txt';
    await File(filePath).writeAsString('NEEDLE ${'y' * 2000}\n');

    final clampResult =
        jsonDecode(
              await FilesystemTools.searchFiles(
                path: tempDir.path,
                query: 'NEEDLE',
                maxLineLength: 50,
              ),
            )
            as Map<String, dynamic>;
    final clampMatches = (clampResult['matches'] as List).cast<String>();
    expect(clampMatches, isNotEmpty);
    expect(clampMatches.first.endsWith('…'), isTrue);

    final ceilingResult =
        jsonDecode(
              await FilesystemTools.searchFiles(
                path: tempDir.path,
                query: 'NEEDLE',
                maxBytesScanned: 1,
              ),
            )
            as Map<String, dynamic>;
    expect(ceilingResult['scan_ceiling_hit'], isTrue);
  });
}
