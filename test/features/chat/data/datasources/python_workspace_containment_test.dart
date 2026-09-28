import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/data/datasources/python_workspace_containment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects only direct foreground Python command shapes', () {
    final root = Directory.systemTemp.createTempSync('python-root-');
    addTearDown(() => root.deleteSync(recursive: true));
    final supported =
        Platform.isMacOS &&
        File(PythonWorkspaceContainment.executable).existsSync();

    for (final command in [
      'python3 watcher.py --help',
      'python3 -c "print(1)"',
      'cd ${root.path} && python3 -m pytest --version',
      '.venv/bin/python -m unittest',
    ]) {
      expect(
        PythonWorkspaceContainment.eligible(command: command, root: root.path),
        supported,
        reason: command,
      );
    }
    for (final command in [
      'echo python3 watcher.py',
      'curl example.com && python3 watcher.py',
      'python3-not-an-interpreter watcher.py',
    ]) {
      expect(
        PythonWorkspaceContainment.eligible(command: command, root: root.path),
        isFalse,
        reason: command,
      );
    }
  });

  test('profile restricts writes and service escapes', () {
    final profile = PythonWorkspaceContainment.profile(
      root: '/project',
      scratch: '/scratch',
    );
    expect(profile, contains('(deny file-write*)'));
    expect(profile, contains('(allow file-write* (subpath "/project"))'));
    expect(profile, contains('(allow file-write* (subpath "/scratch"))'));
    expect(profile, contains('(deny file-write* (subpath "/project/.git"))'));
    expect(profile, contains('(deny appleevent-send)'));
    expect(profile, contains('(deny mach-lookup)'));
    expect(profile, contains('(deny network*)'));
  });

  test(
    'real sandbox allows project writes and blocks symlink escapes',
    () async {
      final root = await Directory.systemTemp.createTemp('python-project-');
      final outside = await Directory.systemTemp.createTemp('python-outside-');
      addTearDown(() async {
        await root.delete(recursive: true);
        await outside.delete(recursive: true);
      });
      if (!PythonWorkspaceContainment.eligible(
        command: 'python3 -c "print(1)"',
        root: root.path,
      )) {
        return;
      }
      await Link('${root.path}/escape').create(outside.path);

      final inside = await LocalShellTools.executeResult(
        command:
            "python3 -c 'from pathlib import Path; "
            'Path("inside.txt").write_text("ok")\'',
        workingDirectory: root.path,
        projectRoot: root.path,
        containmentRoot: root.path,
      );
      expect((jsonDecode(inside.result) as Map)['exit_code'], 0);
      expect(await File('${root.path}/inside.txt').readAsString(), 'ok');

      final escaped = await LocalShellTools.executeResult(
        command:
            "python3 -c 'from pathlib import Path; "
            'Path("escape/blocked.txt").write_text("bad")\'',
        workingDirectory: root.path,
        projectRoot: root.path,
        containmentRoot: root.path,
      );
      expect((jsonDecode(escaped.result) as Map)['exit_code'], isNot(0));
      expect(File('${outside.path}/blocked.txt').existsSync(), isFalse);
    },
  );
}
