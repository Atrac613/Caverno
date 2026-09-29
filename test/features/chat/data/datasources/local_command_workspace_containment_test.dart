import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/local_command_workspace_containment.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final supported =
      Platform.isMacOS &&
      File(LocalCommandWorkspaceContainment.executable).existsSync();

  test('selects direct Python and Bash command shapes', () {
    final root = Directory.systemTemp.createTempSync('python-root-');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final command in [
      'python3 watcher.py --help',
      'python3 -c "print(1)"',
      'cd ${root.path} && python3 -m pytest --version',
      '.venv/bin/python -m unittest',
      'bash tool/check.sh',
      'bash -c "printf ok > output.txt"',
      'cd "${root.path}" && bash tool/check.sh',
      'bash tool/check.sh | cat > output.txt',
      'bash tool/check.sh && bash tool/another-check.sh',
      "bash <<'SCRIPT'\nprintf ok > output.txt\nSCRIPT",
    ]) {
      expect(
        LocalCommandWorkspaceContainment.eligible(
          command: command,
          root: root.path,
        ),
        supported,
        reason: command,
      );
    }
    for (final command in [
      'echo python3 watcher.py',
      'curl example.com && python3 watcher.py',
      'python3-not-an-interpreter watcher.py',
      'echo bash tool/check.sh',
      'curl example.com && bash tool/check.sh',
      'bash-not-a-shell tool/check.sh',
      'sh tool/check.sh',
      'zsh tool/check.sh',
      'bash tool/release_ios_macos.sh',
      'bash tool/publish_macos_sparkle_release.sh',
      'bash -c "flutter build macos"',
      'bash -c "xcodebuild -version"',
      'bash -c "sandbox-exec -h"',
      'bash tool/check.sh &',
      "bash -c 'bash tool/check.sh &'",
    ]) {
      expect(
        LocalCommandWorkspaceContainment.eligible(
          command: command,
          root: root.path,
        ),
        isFalse,
        reason: command,
      );
    }
  });

  test('requires an existing project root', () {
    for (final root in [null, '', '/no-such-caverno-containment-project']) {
      expect(
        LocalCommandWorkspaceContainment.eligible(
          command: 'bash tool/check.sh',
          root: root,
        ),
        isFalse,
      );
    }
  });

  test('profile restricts writes and service escapes', () {
    final profile = LocalCommandWorkspaceContainment.profile(
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
    skip: !supported,
  );

  group('real Bash containment', () {
    late Directory fixture;
    late Directory project;
    late Directory outside;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('bash-containment-');
      project = await Directory('${fixture.path}/project').create();
      outside = await Directory('${fixture.path}/outside').create();
    });
    tearDown(() => fixture.delete(recursive: true));

    Future<Map<String, dynamic>> execute(String command) async {
      final result = await LocalShellTools.executeResult(
        command: command,
        workingDirectory: project.path,
        projectRoot: project.path,
        containmentRoot: project.path,
      );
      return jsonDecode(result.result) as Map<String, dynamic>;
    }

    test(
      'allows scripts, pipelines, child shells and scratch writes',
      () async {
        await File('${project.path}/check.sh').writeAsString(r'''
set -eu
printf 'inside' | cat > inside.txt
bash -c 'printf child > child.txt'
scratch=$(mktemp)
printf scratch > "$scratch"
cat "$scratch" > scratch.txt
''');

        final result = await execute('bash check.sh');

        expect(result['exit_code'], 0, reason: result['stderr'] as String?);
        expect(
          await File('${project.path}/inside.txt').readAsString(),
          'inside',
        );
        expect(await File('${project.path}/child.txt').readAsString(), 'child');
        expect(
          await File('${project.path}/scratch.txt').readAsString(),
          'scratch',
        );
      },
      skip: !supported,
    );

    test(
      'blocks outside writes and symlink escapes without retrying',
      () async {
        await Link('${project.path}/escape').create(outside.path);
        for (final (script, target) in [
          ('direct.sh', '../outside/direct.txt'),
          ('symlink.sh', 'escape/symlink.txt'),
        ]) {
          // Hide targets in the script so this exercises the OS sandbox,
          // rather than stopping at the lexical mutation preflight.
          await File('${project.path}/$script').writeAsString(
            r'''
set -eu
printf attempt >> attempts.txt
bash -c 'printf blocked > "$1"' child 'TARGET'
'''
                .replaceAll('TARGET', target),
          );

          final result = await execute('bash $script');
          expect(result['exit_code'], allOf(isA<int>(), isNot(0)));
          expect(result['stderr'], contains('Operation not permitted'));
          expect(outside.listSync(), isEmpty);
        }
        expect(
          await File('${project.path}/attempts.txt').readAsString(),
          'attemptattempt',
        );
      },
      skip: !supported,
    );

    test('keeps Git hooks read-only', () async {
      final hook = File('${project.path}/.git/hooks/pre-commit');
      await hook.parent.create(recursive: true);
      await hook.writeAsString('original');

      final result = await execute(
        "bash -c 'printf changed > .git/hooks/pre-commit'",
      );

      expect(result['exit_code'], allOf(isA<int>(), isNot(0)));
      expect(await hook.readAsString(), 'original');
    }, skip: !supported);

    test('blocks loopback network access from script children', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) {
        requests++;
        request.response.close();
      });
      await File('${project.path}/network.sh').writeAsString(r'''
set -eu
/usr/bin/curl --silent --show-error --connect-timeout 1 --max-time 2 "$1"
''');

      final result = await execute(
        'bash network.sh http://127.0.0.1:${server.port}/probe',
      );

      expect(result['exit_code'], allOf(isA<int>(), isNot(0)));
      expect(requests, 0);
    }, skip: !supported);

    test('fails closed when containment preparation fails', () async {
      final result = await LocalShellTools.executeResult(
        command: "bash -c 'printf ran > unexpected.txt'",
        workingDirectory: project.path,
        projectRoot: project.path,
        containmentRoot: '${fixture.path}/missing',
      );

      expect(result.errorMessage, contains('containment could not be started'));
      expect(File('${project.path}/unexpected.txt').existsSync(), isFalse);
    });
  });
}
