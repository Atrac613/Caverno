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
    expect(editResult['changed'], isTrue);

    final updated = await File(targetPath).readAsString();
    expect(updated, 'hello agent');
  });

  test('deleteFile removes a regular UTF-8 text file', () async {
    final target = File('${tempDir.path}${Platform.pathSeparator}obsolete.txt')
      ..writeAsStringSync('obsolete\n');

    final result =
        jsonDecode(await FilesystemTools.deleteFile(path: target.path))
            as Map<String, dynamic>;

    expect(result['deleted'], isTrue);
    expect(target.existsSync(), isFalse);
  });

  test('deleteFile rejects directories', () async {
    final directory = Directory(
      '${tempDir.path}${Platform.pathSeparator}nested',
    )..createSync();

    final result =
        jsonDecode(await FilesystemTools.deleteFile(path: directory.path))
            as Map<String, dynamic>;

    expect(result['error'], contains('regular files only'));
    expect(directory.existsSync(), isTrue);
  });

  test('writeFile reports whether the content actually changed', () async {
    // A byte-identical rewrite is otherwise indistinguishable from a real one:
    // same bytes_written, same success. Without this fact the model can loop on
    // edit -> re-read -> edit while the file never moves.
    final targetPath = '${tempDir.path}${Platform.pathSeparator}write.txt';

    final createdExecution = await FilesystemTools.writeFileResult(
      path: targetPath,
      content: 'hello world',
    );
    final rewrittenExecution = await FilesystemTools.writeFileResult(
      path: targetPath,
      content: 'hello world',
    );
    final editedExecution = await FilesystemTools.writeFileResult(
      path: targetPath,
      content: 'hello there',
    );
    final created = jsonDecode(createdExecution.result) as Map<String, dynamic>;
    final rewritten =
        jsonDecode(rewrittenExecution.result) as Map<String, dynamic>;
    final edited = jsonDecode(editedExecution.result) as Map<String, dynamic>;

    expect(created['created'], isTrue);
    expect(created['changed'], isTrue);
    expect(rewritten['created'], isFalse);
    expect(rewritten['changed'], isFalse);
    expect(edited['changed'], isTrue);
    expect(rewritten['bytes_written'], created['bytes_written']);
    expect(createdExecution.outcome?.effectiveFileChanged, isTrue);
    expect(rewrittenExecution.outcome?.effectiveFileChanged, isFalse);
    expect(
      editedExecution.outcome?.fileMutations.single.contentHash,
      isNotEmpty,
    );
  });

  test('writeFile detects a same-length content change', () async {
    // The length comparison is only a shortcut; equal lengths must still be
    // compared byte for byte or a same-size edit reads as a no-op.
    final targetPath = '${tempDir.path}${Platform.pathSeparator}samesize.txt';
    await FilesystemTools.writeFile(path: targetPath, content: 'aaaa');

    final result =
        jsonDecode(
              await FilesystemTools.writeFile(
                path: targetPath,
                content: 'bbbb',
              ),
            )
            as Map<String, dynamic>;

    expect(result['changed'], isTrue);
  });

  test('editFile reports no_change when new_text equals old_text', () async {
    final targetPath = '${tempDir.path}${Platform.pathSeparator}noop.txt';
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

  test(
    'editFile treats an overlapping replacement as already applied',
    () async {
      final targetPath = '${tempDir.path}${Platform.pathSeparator}pubspec.yaml';
      await FilesystemTools.writeFile(
        path: targetPath,
        content: 'name: todo_app\n',
      );

      final editResult =
          jsonDecode(
                await FilesystemTools.editFile(
                  path: targetPath,
                  oldText: 'name: todo',
                  newText: 'name: todo_app',
                ),
              )
              as Map<String, dynamic>;

      expect(editResult['already_applied'], isTrue);
      expect(editResult['replacements'], 0);
      expect(editResult['changed'], isFalse);
      expect(await File(targetPath).readAsString(), 'name: todo_app\n');
    },
  );

  test('preflightEditFile rejects a stale old_text before approval', () async {
    final targetPath = '${tempDir.path}${Platform.pathSeparator}pubspec.yaml';
    await FilesystemTools.writeFile(
      path: targetPath,
      content: 'name: current_app\n',
    );

    final preflightResult =
        jsonDecode(
              (await FilesystemTools.preflightEditFile(
                path: targetPath,
                oldText: 'name: todo',
                newText: 'name: todo_app',
              ))!,
            )
            as Map<String, dynamic>;

    expect(
      preflightResult['error'],
      'old_text was not found in the target file',
    );
    expect(await File(targetPath).readAsString(), 'name: current_app\n');
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
    expect(
      editResult['current_content'],
      "String canaryValue() => 'BROKEN';\n",
    );
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
    expect(editResult.containsKey('new_text_present'), isFalse);
  });

  test(
    'editFile not-found error locates new_text when the edit already landed',
    () async {
      // The repeated-bump shape from a session log: the version was already
      // changed, so old_text is gone and the model has no idea why. The file is
      // over the inline-content limit, which is where the model then burned six
      // read_file windows without reaching the line.
      final targetPath =
          '${tempDir.path}${Platform.pathSeparator}pubspec_like.yaml';
      final file = File(targetPath)..createSync(recursive: true);
      file.writeAsStringSync(
        '${'# padding\n' * 500}version: 1.3.15+27\n${'# tail\n' * 500}',
      );

      final editResult =
          jsonDecode(
                await FilesystemTools.editFile(
                  path: targetPath,
                  oldText: 'version: 1.3.14+26',
                  newText: 'version: 1.3.15+27',
                ),
              )
              as Map<String, dynamic>;

      expect(editResult['error'], 'old_text was not found in the target file');
      expect(editResult['new_text_present'], isTrue);
      expect(editResult['new_text_line'], 501);
      expect(editResult['hint'], contains('line 501'));
      expect(editResult['hint'], contains('already'));
    },
  );

  test('editFile not-found error reports no new_text location for a small file '
      'that never had it', () async {
    final targetPath = '${tempDir.path}${Platform.pathSeparator}absent.txt';
    final file = File(targetPath)..createSync(recursive: true);
    file.writeAsStringSync('alpha\n');

    final editResult =
        jsonDecode(
              await FilesystemTools.editFile(
                path: targetPath,
                oldText: 'beta',
                newText: 'gamma',
              ),
            )
            as Map<String, dynamic>;

    expect(editResult.containsKey('new_text_present'), isFalse);
    expect(editResult['current_content'], 'alpha\n');
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

  test('readFile hashes the whole file, not the returned window', () async {
    // The point of a whole-file hash: two paging windows of one unchanged file
    // return different text, and a consumer must still be able to tell that
    // the file did not move.
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}hashed.txt';
    final file = File(targetPath);
    file.createSync(recursive: true);
    file.writeAsStringSync('one\ntwo\nthree\nfour\n');

    Future<({Map<String, dynamic> payload, String? contentHash})> read({
      int offset = 1,
      int? limit,
    }) async {
      final execution = await FilesystemTools.readFileResult(
        path: targetPath,
        offset: offset,
        limit: limit,
      );
      return (
        payload: jsonDecode(execution.result) as Map<String, dynamic>,
        contentHash: execution.outcome?.effectiveContentHash,
      );
    }

    final head = await read(offset: 1, limit: 2);
    final tail = await read(offset: 3, limit: 2);

    expect(head.payload['content'], isNot(tail.payload['content']));
    expect(head.payload['content_hash'], isNotEmpty);
    expect(
      head.contentHash,
      tail.contentHash,
      reason: 'different windows of an unchanged file share one identity',
    );
    expect(head.contentHash, head.payload['content_hash']);

    file.writeAsStringSync('one\ntwo\nthree\nFIVE\n');
    final afterEdit = await read(offset: 1, limit: 2);

    expect(
      afterEdit.payload['content'],
      head.payload['content'],
      reason: 'the edit is outside this window, so the text is unchanged',
    );
    expect(
      afterEdit.contentHash,
      isNot(head.contentHash),
      reason: 'the hash sees the edit the window does not show',
    );
  });

  test('readFile omits the hash rather than guessing one', () async {
    final targetPath =
        '${tempDir.path}${Platform.pathSeparator}missing_hash.txt';

    final missing =
        jsonDecode(await FilesystemTools.readFile(path: targetPath))
            as Map<String, dynamic>;

    expect(missing.containsKey('content_hash'), isFalse);
    expect(missing['error'], contains('does not exist'));
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
