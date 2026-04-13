import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marks simple inspection commands as read-only', () {
    expect(LocalShellTools.isReadOnly('pwd'), isTrue);
    expect(LocalShellTools.isReadOnly('ls -la'), isTrue);
    expect(
      LocalShellTools.isReadOnly(
        "ls -R && echo '--- pubspec.yaml content ---' && cat pubspec.yaml",
      ),
      isTrue,
    );
    expect(LocalShellTools.isReadOnly('rg ChatPage lib'), isTrue);
    expect(LocalShellTools.isReadOnly('git status --short'), isTrue);
  });

  test('marks mutating or shell-heavy commands as requiring approval', () {
    expect(LocalShellTools.isReadOnly('flutter test'), isFalse);
    expect(LocalShellTools.isReadOnly('rm -rf build'), isFalse);
    expect(LocalShellTools.isReadOnly('rg ChatPage lib | head'), isFalse);
    expect(LocalShellTools.isReadOnly('sed -i s/foo/bar/g file.txt'), isFalse);
  });

  test('executes chained read-only commands internally', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File('${tempDir.path}/pubspec.yaml').writeAsString('name: sample\n');
    final libDir = Directory('${tempDir.path}/lib')
      ..createSync(recursive: true);
    await File('${libDir.path}/main.dart').writeAsString('void main() {}\n');

    final raw = await LocalShellTools.execute(
      command:
          "ls -R && echo '--- pubspec.yaml content ---' && cat pubspec.yaml",
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], 0);
    expect(result['executed_internally'], isTrue);
    expect(result['stdout'], contains('.:'));
    expect(result['stdout'], contains('lib:'));
    expect(result['stdout'], contains('pubspec.yaml'));
    expect(result['stdout'], contains('--- pubspec.yaml content ---'));
    expect(result['stdout'], contains('name: sample'));
  });
}
