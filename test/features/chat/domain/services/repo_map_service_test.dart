import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';
import 'package:caverno/features/chat/domain/services/repo_map_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('repo_map_service_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('builds a bounded repository map with key files and Dart symbols', () {
    _writeFile(tempDir, 'pubspec.yaml', 'name: example\n');
    _writeFile(tempDir, 'README.md', '# Example\n');
    _writeFile(tempDir, 'lib/main.dart', '''
class AppRoot {}

final appProvider = Provider((ref) => AppRoot());

void bootstrap() {}
''');
    _writeFile(tempDir, 'lib/features/chat/chat_service.dart', '''
abstract class ChatService {}

Future<void> sendMessage() async {}
''');

    final map = RepoMapService.buildForProject(
      rootPath: tempDir.path,
      maxFiles: 10,
      maxSymbols: 20,
    );

    expect(map, isNotNull);
    expect(map, contains('pubspec.yaml'));
    expect(map, contains('README.md'));
    expect(map, contains('lib/main.dart'));
    expect(map, contains('lib/features/chat/chat_service.dart'));
    expect(map, contains('class AppRoot'));
    expect(map, contains('provider appProvider'));
    expect(map, contains('function bootstrap'));
    expect(map, contains('class ChatService'));
    expect(map, contains('function sendMessage'));
  });

  test('adds LSP symbols for non-Dart project files', () {
    _writeFile(tempDir, 'pubspec.yaml', 'name: example\n');
    _writeFile(tempDir, 'src/app.ts', 'export class AppRoot {}\n');

    final map = RepoMapService.buildForProject(
      rootPath: tempDir.path,
      maxFiles: 10,
      maxSymbols: 4,
      lspSymbolEntries: const [
        RepoMapSymbolEntry(
          relativePath: 'src/app.ts',
          symbols: ['class AppRoot', 'function createApp'],
        ),
      ],
    );

    expect(map, isNotNull);
    expect(map, contains('src/app.ts'));
    expect(map, contains('LSP symbols:'));
    expect(map, contains('- src/app.ts: class AppRoot, function createApp'));
  });

  test('converts LSP document symbols into repo-map entries', () {
    final source = _writeFile(
      tempDir,
      'src/app.ts',
      'export class AppRoot {}\n',
    );
    _writeFile(tempDir, 'other/outside.ts', 'export const ignored = true;\n');

    final entries = RepoMapService.symbolEntriesFromLsp(
      projectRoot: tempDir.path,
      symbols: [
        LspDocumentSymbol(
          uri: source.uri.toString(),
          name: 'AppRoot',
          kind: 5,
          kindLabel: 'Class',
          startLine: 0,
          startCharacter: 13,
          children: [
            LspDocumentSymbol(
              uri: source.uri.toString(),
              name: 'render',
              kind: 6,
              kindLabel: 'Method',
              startLine: 2,
              startCharacter: 2,
              containerName: 'AppRoot',
            ),
          ],
        ),
        const LspDocumentSymbol(
          uri: 'file:///tmp/outside.ts',
          name: 'Outside',
          kind: 5,
          kindLabel: 'Class',
          startLine: 0,
          startCharacter: 0,
        ),
      ],
    );

    expect(entries, hasLength(1));
    expect(entries.single.relativePath, 'src/app.ts');
    expect(entries.single.symbols, ['class AppRoot', 'method AppRoot.render']);
  });

  test('skips generated and build files while respecting explicit limits', () {
    _writeFile(tempDir, 'pubspec.yaml', 'name: example\n');
    _writeFile(tempDir, 'build/generated.dart', 'class BuildArtifact {}\n');
    _writeFile(tempDir, 'node_modules/pkg/index.yaml', 'ignored: true\n');
    _writeFile(
      tempDir,
      'lib/generated/app.freezed.dart',
      'class Generated {}\n',
    );
    for (var index = 0; index < 8; index += 1) {
      _writeFile(
        tempDir,
        'lib/features/sample/file_$index.dart',
        'class Feature$index {}\nvoid feature$index() {}\n',
      );
    }

    final map = RepoMapService.buildForProject(
      rootPath: tempDir.path,
      maxFiles: 3,
      maxSymbols: 2,
    );

    expect(map, isNotNull);
    expect(map, isNot(contains('build/generated.dart')));
    expect(map, isNot(contains('node_modules')));
    expect(map, isNot(contains('app.freezed.dart')));
    expect(_sectionLineCount(map!, 'Key files:'), lessThanOrEqualTo(3));
    expect(_sectionLineCount(map, 'Dart symbols:'), lessThanOrEqualTo(2));
  });

  test('returns null when the project root is unavailable', () {
    final map = RepoMapService.buildForProject(
      rootPath: '${tempDir.path}/missing',
    );

    expect(map, isNull);
  });
}

File _writeFile(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}

int _sectionLineCount(String text, String heading) {
  final lines = text.split('\n');
  final start = lines.indexOf(heading);
  if (start < 0) return 0;
  var count = 0;
  for (final line in lines.skip(start + 1)) {
    if (!line.startsWith('- ')) break;
    count += 1;
  }
  return count;
}
