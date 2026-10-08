import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/shell_write_observation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const on = {ShellWriteObservation.environmentKey: '1'};

  group('wrap', () {
    test('leaves the command alone unless observation is switched on', () {
      expect(
        ShellWriteObservation.wrap(
          command: 'echo hi',
          shellExecutable: 'sh',
          shellArgs: const ['-c', 'echo hi'],
          root: Directory.systemTemp.path,
          environment: const {},
        ),
        isNull,
      );
    });

    test('leaves the command alone without a project root', () {
      expect(
        ShellWriteObservation.wrap(
          command: 'echo hi',
          shellExecutable: 'sh',
          shellArgs: const ['-c', 'echo hi'],
          root: '  ',
          environment: on,
        ),
        isNull,
      );
    });

    test('skips toolchains that apply a sandbox of their own', () {
      for (final command in [
        'xcodebuild -scheme Runner',
        'fvm flutter build macos --release',
        'flutter run -d macos',
        'swift build',
        'bash tool/release_ios_macos.sh --dry-run',
        'cd ios && pod install',
        'codex exec "x"',
      ]) {
        expect(
          ShellWriteObservation.reachesNestedSandbox(command),
          isTrue,
          reason: command,
        );
      }
      for (final command in [
        'fvm flutter test',
        'fvm dart analyze',
        'git status',
        'python3 -m unittest',
        'opener.sh',
      ]) {
        expect(
          ShellWriteObservation.reachesNestedSandbox(command),
          isFalse,
          reason: command,
        );
      }
    });

    test('runs the shell under sandbox-exec with a reporting profile', () {
      final root = Directory.systemTemp.createTempSync('observe_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      final wrapped = ShellWriteObservation.wrap(
        command: 'echo hi',
        shellExecutable: 'sh',
        shellArgs: const ['-c', 'echo hi'],
        root: root.path,
        environment: on,
      )!;
      expect(wrapped.executable, '/usr/bin/sandbox-exec');
      expect(wrapped.args.first, '-p');
      final canary = ShellWriteObservation.canaryPath(wrapped.tag)!;
      expect(wrapped.args.sublist(2), [
        '/bin/sh',
        '-c',
        r'( : > "$0" ) 2>/dev/null; exec "$@"',
        canary,
        'sh',
        '-c',
        'echo hi',
      ]);
      expect(canary, isNot(startsWith(root.resolveSymbolicLinksSync())));
      final profile = wrapped.args[1];
      expect(profile, contains('(allow default)'));
      expect(profile, contains(root.resolveSymbolicLinksSync()));
      expect(profile, contains('(with message "${wrapped.tag}")'));
      expect(profile, isNot(contains('deny')));
    }, skip: Platform.isMacOS ? false : 'seatbelt is macOS only');
  });

  test('escapes the root inside the profile literal', () {
    final profile = ShellWriteObservation.profile(
      root: r'/tmp/a "b"\c',
      tag: 'cv-1-ab',
    );
    expect(profile, contains(r'(subpath "/tmp/a \"b\"\\c")'));
  });

  test('reads a well-formed tag back from the payload only', () {
    const tag = 'cv-1727150000-0a1b2c3d';
    expect(
      ShellWriteObservation.tagFromPayload(
        jsonEncode({'exit_code': 0, ShellWriteObservation.payloadKey: tag}),
      ),
      tag,
    );
    expect(ShellWriteObservation.tagFromPayload('{"exit_code":0}'), isNull);
    // The tag is interpolated into a log predicate.
    expect(
      ShellWriteObservation.tagFromPayload(
        jsonEncode({ShellWriteObservation.payloadKey: 'cv-1-a" OR 1'}),
      ),
      isNull,
    );
  });

  test('parses only reports carrying the tag, deduplicated', () {
    const tag = 'cv-1727150000-0a1b2c3d';
    String event(String message) => jsonEncode({'eventMessage': message});
    final ndjson = [
      event(
        'Sandbox: bash(1) allow file-write-create /Users/me/.pub-cache/x\n$tag',
      ),
      event(
        'Sandbox: Python(2) allow file-write-data /Users/me/.pub-cache/x\n$tag',
      ),
      event('Sandbox: bash(3) allow file-write-unlink /tmp/y\n$tag'),
      event('Sandbox: bash(4) allow file-write-create /other\ncv-9-ffffffff'),
      event('Sandbox: bash(5) deny(1) file-write-create /denied\n$tag'),
      'not json $tag',
    ].join('\n');
    final parsed = ShellWriteObservation.parseReports(ndjson, tag);
    expect(parsed.paths, ['/Users/me/.pub-cache/x', '/tmp/y']);
    expect(parsed.truncated, isFalse);
  });

  test(
    'the canary prelude keeps the command\'s exit code and output',
    () async {
      final root = Directory.systemTemp.createTempSync('observe_exit_');
      addTearDown(() => root.deleteSync(recursive: true));
      final wrapped = ShellWriteObservation.wrap(
        command: 'x',
        shellExecutable: '/bin/sh',
        shellArgs: ['-c', 'echo "\$0 \$1"; exit 7', 'name', 'arg'],
        root: root.path,
        environment: on,
      )!;
      final run = await Process.run(
        wrapped.executable,
        wrapped.args,
        workingDirectory: root.path,
      );
      expect(run.exitCode, 7, reason: '${run.stderr}');
      expect(run.stdout, 'name arg\n');
      final canary = File(ShellWriteObservation.canaryPath(wrapped.tag)!);
      expect(canary.existsSync(), isTrue);
      canary.deleteSync();
    },
    skip: Platform.isMacOS ? false : 'seatbelt is macOS only',
  );

  test(
    'observes a real write outside the root and nothing inside it',
    () async {
      final sandbox = Directory.systemTemp.createTempSync('observe_e2e_');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final root = Directory('${sandbox.path}/project')..createSync();
      final outside = '${sandbox.resolveSymbolicLinksSync()}/outside.txt';
      final wrapped = ShellWriteObservation.wrap(
        command: 'x',
        shellExecutable: '/bin/sh',
        shellArgs: ['-c', 'echo a > inside.txt; echo b > "$outside"'],
        root: root.path,
        environment: on,
      )!;
      final run = await Process.run(
        wrapped.executable,
        wrapped.args,
        workingDirectory: root.path,
      );
      expect(run.exitCode, 0, reason: '${run.stderr}');
      // Writes are allowed, not merely reported.
      expect(File(outside).readAsStringSync(), 'b\n');

      ({List<String> paths, bool truncated, bool reportingConfirmed})? observed;
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        observed = await ShellWriteObservation.collect(wrapped.tag);
        if (observed != null && observed.reportingConfirmed) break;
      }
      expect(observed, isNotNull);
      if (observed!.reportingConfirmed) {
        // The canary is consumed, never reported as the command's write.
        expect(observed.paths, [outside]);
      } else {
        // No report arrived, not even the canary's (macOS 26.7.1 delivers
        // none): the observation must say so instead of claiming no writes.
        expect(observed.paths, isEmpty);
        // ignore: avoid_print
        print('seatbelt reports unavailable here; observation marked unknown');
      }
      expect(
        File(ShellWriteObservation.canaryPath(wrapped.tag)!).existsSync(),
        isFalse,
      );
    },
    skip: Platform.isMacOS ? false : 'seatbelt is macOS only',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
