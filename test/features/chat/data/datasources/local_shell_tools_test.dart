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

  test('executes head, tail, wc, find, and rg internally', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_extended_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final libDir = Directory('${tempDir.path}/lib')
      ..createSync(recursive: true);
    final nestedDir = Directory('${libDir.path}/nested')
      ..createSync(recursive: true);
    await File(
      '${libDir.path}/main.dart',
    ).writeAsString('alpha\nbeta\ngamma\ndelta\n');
    await File(
      '${nestedDir.path}/feature.txt',
    ).writeAsString('first line\nsecond line\nthird line\n');

    final head =
        jsonDecode(
              await LocalShellTools.execute(
                command: 'head -n 2 lib/main.dart',
                workingDirectory: tempDir.path,
              ),
            )
            as Map<String, dynamic>;
    expect(head['executed_internally'], isTrue);
    expect(head['stdout'], 'alpha\nbeta\n');

    final tail =
        jsonDecode(
              await LocalShellTools.execute(
                command: 'tail -n 2 lib/main.dart',
                workingDirectory: tempDir.path,
              ),
            )
            as Map<String, dynamic>;
    expect(tail['stdout'], 'gamma\ndelta\n');

    final wc =
        jsonDecode(
              await LocalShellTools.execute(
                command: 'wc -lwc lib/main.dart',
                workingDirectory: tempDir.path,
              ),
            )
            as Map<String, dynamic>;
    expect(wc['stdout'], contains('4'));
    expect(wc['stdout'], contains('lib/main.dart'));

    final find =
        jsonDecode(
              await LocalShellTools.execute(
                command: 'find lib -type f -name *.txt',
                workingDirectory: tempDir.path,
              ),
            )
            as Map<String, dynamic>;
    expect(find['stdout'], contains('./nested/feature.txt'));

    final rg =
        jsonDecode(
              await LocalShellTools.execute(
                command: 'rg second lib',
                workingDirectory: tempDir.path,
              ),
            )
            as Map<String, dynamic>;
    expect(rg['stdout'], contains('nested/feature.txt:2:second line'));
  });
}
