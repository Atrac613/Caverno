import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';
import 'package:caverno/features/chat/domain/services/repo_map_lsp_symbol_cache.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'repo_map_lsp_symbol_cache_test_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('stores LSP symbols by project root and changed file', () {
    final source = _writeFile(
      tempDir,
      'src/app.ts',
      'export class AppRoot {}\n',
    );
    final cache = RepoMapLspSymbolCache();

    cache.updateFromLsp(
      projectRoot: tempDir.path,
      changedPaths: [source.path],
      symbols: [
        LspDocumentSymbol(
          uri: source.uri.toString(),
          name: 'AppRoot',
          kind: 5,
          kindLabel: 'Class',
          startLine: 0,
          startCharacter: 13,
        ),
      ],
    );

    final entries = cache.entriesForRoot(tempDir.path);
    expect(entries, hasLength(1));
    expect(entries.single.relativePath, 'src/app.ts');
    expect(entries.single.symbols, ['class AppRoot']);
  });

  test('replaces stale symbols for changed files', () {
    final source = _writeFile(
      tempDir,
      'src/app.ts',
      'export class AppRoot {}\n',
    );
    final cache = RepoMapLspSymbolCache();

    cache.updateFromLsp(
      projectRoot: tempDir.path,
      changedPaths: [source.path],
      symbols: [
        LspDocumentSymbol(
          uri: source.uri.toString(),
          name: 'OldRoot',
          kind: 5,
          kindLabel: 'Class',
          startLine: 0,
          startCharacter: 13,
        ),
      ],
    );
    cache.updateFromLsp(
      projectRoot: tempDir.path,
      changedPaths: [source.path],
      symbols: [
        LspDocumentSymbol(
          uri: source.uri.toString(),
          name: 'NewRoot',
          kind: 5,
          kindLabel: 'Class',
          startLine: 0,
          startCharacter: 13,
        ),
      ],
    );

    final entries = cache.entriesForRoot(tempDir.path);
    expect(entries, hasLength(1));
    expect(entries.single.symbols, ['class NewRoot']);
  });
}

File _writeFile(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}
