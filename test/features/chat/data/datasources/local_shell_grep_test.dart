import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/local_shell_grep.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:flutter_test/flutter_test.dart';

// Expected outputs below were recorded from /usr/bin/grep (BSD grep 2.6.0,
// GNU compatible) on the same fixture, so they pin shell parity, not just the
// implementation's current behaviour.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local_shell_grep_test_');
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: caverno\n'
      'description: A chat app\n'
      'version: 1.3.44+58\n'
      'environment:\n'
      '  sdk: ^3.9.0\n',
    );
    Directory('${root.path}/lib/sub').createSync(recursive: true);
    File('${root.path}/lib/a.dart').writeAsStringSync(
      'class Foo {}\n'
      'void main() {\n'
      '  final foo = Foo();\n'
      '  print(foo);\n'
      '}\n'
      '// TODO: foo bar\n'
      'foobar\n',
    );
    File('${root.path}/lib/sub/b.txt').writeAsStringSync(
      'alpha\n'
      'beta 42\n'
      'gamma (x)\n'
      'delta|epsilon\n'
      'FOO\n'
      'line with a+b\n'
      'end\n',
    );
    File(
      '${root.path}/crlf.txt',
    ).writeAsStringSync('version: 1\r\nname: x\r\n');
  });

  tearDown(() => root.delete(recursive: true));

  Future<Map<String, dynamic>> run(String command) async {
    expect(LocalShellTools.isReadOnly(command), isTrue, reason: command);
    final payload =
        jsonDecode(
              await LocalShellTools.execute(
                command: command,
                workingDirectory: root.path,
              ),
            )
            as Map<String, dynamic>;
    expect(payload['executed_internally'], isTrue, reason: command);
    return payload;
  }

  Future<void> expectGrep(
    String command,
    String stdout, {
    int exitCode = 0,
  }) async {
    final payload = await run(command);
    expect(payload['stdout'], stdout, reason: command);
    expect(payload['exit_code'], exitCode, reason: command);
  }

  group('shell parity', () {
    test('matches the version lookups the audit log is full of', () async {
      await expectGrep(
        "grep -E '^version:' pubspec.yaml",
        'version: 1.3.44+58\n',
      );
      await expectGrep(
        'grep -n "^version:" pubspec.yaml',
        '3:version: 1.3.44+58\n',
      );
      await expectGrep("grep -m1 'sdk' pubspec.yaml", '  sdk: ^3.9.0\n');
      await expectGrep(
        r"grep '^version:\|^name:' pubspec.yaml",
        'name: caverno\nversion: 1.3.44+58\n',
      );
      await expectGrep(
        "grep -E '^(name|version):' pubspec.yaml",
        'name: caverno\nversion: 1.3.44+58\n',
      );
    });

    test('prefixes file names only when more than one file is searched', () {
      return Future.wait([
        expectGrep(
          'grep -i foo lib/a.dart lib/sub/b.txt',
          'lib/a.dart:class Foo {}\n'
              'lib/a.dart:  final foo = Foo();\n'
              'lib/a.dart:  print(foo);\n'
              'lib/a.dart:// TODO: foo bar\n'
              'lib/a.dart:foobar\n'
              'lib/sub/b.txt:FOO\n',
        ),
        expectGrep(
          'grep -h foo lib/a.dart lib/sub/b.txt',
          '  final foo = Foo();\n  print(foo);\n// TODO: foo bar\nfoobar\n',
        ),
        expectGrep(
          'grep -H version pubspec.yaml',
          'pubspec.yaml:version: 1.3.44+58\n',
        ),
      ]);
    });

    test('walks directories recursively in sorted order', () async {
      await expectGrep(
        'grep -rn foo lib',
        'lib/a.dart:3:  final foo = Foo();\n'
            'lib/a.dart:4:  print(foo);\n'
            'lib/a.dart:6:// TODO: foo bar\n'
            'lib/a.dart:7:foobar\n',
      );
      await expectGrep('grep -rl foo .', './lib/a.dart\n');
      await expectGrep(
        'grep -rn --include=*.txt a lib',
        'lib/sub/b.txt:1:alpha\n'
            'lib/sub/b.txt:2:beta 42\n'
            'lib/sub/b.txt:3:gamma (x)\n'
            'lib/sub/b.txt:4:delta|epsilon\n'
            'lib/sub/b.txt:6:line with a+b\n',
      );
      await expectGrep(
        'grep -rn --exclude-dir=sub a lib',
        'lib/a.dart:1:class Foo {}\n'
            'lib/a.dart:2:void main() {\n'
            'lib/a.dart:3:  final foo = Foo();\n'
            'lib/a.dart:6:// TODO: foo bar\n'
            'lib/a.dart:7:foobar\n',
      );
    });

    test('prints context with group separators', () async {
      await expectGrep(
        'grep -n -C1 foo lib/a.dart',
        '2-void main() {\n'
            '3:  final foo = Foo();\n'
            '4:  print(foo);\n'
            '5-}\n'
            '6:// TODO: foo bar\n'
            '7:foobar\n',
      );
      await expectGrep(
        'grep -B1 -A2 version pubspec.yaml',
        'description: A chat app\n'
            'version: 1.3.44+58\n'
            'environment:\n'
            '  sdk: ^3.9.0\n',
      );
      // The separator also falls between groups in different files.
      await expectGrep(
        'grep -A1 foobar lib/a.dart lib/sub/b.txt pubspec.yaml',
        'lib/a.dart:foobar\n',
      );
      await expectGrep(
        'grep -B1 -e foobar -e FOO lib/a.dart lib/sub/b.txt',
        'lib/a.dart-// TODO: foo bar\n'
            'lib/a.dart:foobar\n'
            '--\n'
            'lib/sub/b.txt-delta|epsilon\n'
            'lib/sub/b.txt:FOO\n',
      );
      await expectGrep(
        'grep -m1 -A2 a lib/sub/b.txt',
        'alpha\nbeta 42\n'
            'gamma (x)\n',
      );
    });

    test('supports counting, listing, inversion and word matching', () async {
      await expectGrep(
        'grep -c foo lib/a.dart lib/sub/b.txt',
        'lib/a.dart:4\nlib/sub/b.txt:0\n',
      );
      await expectGrep(
        'grep -l foo lib/a.dart lib/sub/b.txt pubspec.yaml',
        'lib/a.dart\n',
      );
      await expectGrep(
        'grep -L foo lib/a.dart lib/sub/b.txt pubspec.yaml',
        'lib/sub/b.txt\npubspec.yaml\n',
      );
      await expectGrep(
        'grep -v foo lib/a.dart',
        'class Foo {}\nvoid main() {\n}\n',
      );
      await expectGrep(
        'grep -w foo lib/a.dart',
        '  final foo = Foo();\n  print(foo);\n// TODO: foo bar\n',
      );
      await expectGrep('grep -x foobar lib/a.dart', 'foobar\n');
      await expectGrep(
        "grep -on 'fo*' lib/a.dart",
        // `fo*` also matches the `f` of `final`.
        '3:f\n3:foo\n4:foo\n6:foo\n7:foo\n',
      );
      await expectGrep('grep -q version pubspec.yaml', '');
    });

    test('keeps basic and extended regular expressions distinct', () async {
      await expectGrep("grep 'a+b' lib/sub/b.txt", 'line with a+b\n');
      await expectGrep("grep -E 'a+b' lib/sub/b.txt", '', exitCode: 1);
      await expectGrep("grep -F 'a+b' lib/sub/b.txt", 'line with a+b\n');
      await expectGrep("grep '(x)' lib/sub/b.txt", 'gamma (x)\n');
      await expectGrep("grep 'delta|epsilon' lib/sub/b.txt", 'delta|epsilon\n');
      await expectGrep("grep -E '[[:digit:]]+' lib/sub/b.txt", 'beta 42\n');
      await expectGrep(r"grep 'x\{1,\}' lib/sub/b.txt", 'gamma (x)\n');
      await expectGrep("grep '*' lib/sub/b.txt", '', exitCode: 1);
      await expectGrep(r"grep 'e$' lib/sub/b.txt", '', exitCode: 1);
      await expectGrep(r"grep -E 'epsilon$' lib/sub/b.txt", 'delta|epsilon\n');
      // POSIX `.` matches the carriage return Dart's `.` would stop at.
      await expectGrep(r"grep '^version:.*$' crlf.txt", 'version: 1\r\n');
    });

    test('reports exit status like grep', () async {
      await expectGrep('grep nothing pubspec.yaml', '', exitCode: 1);
      final missing = await run('grep foo missing.txt');
      expect(missing['exit_code'], 2);
      expect(missing['stderr'], contains('missing.txt'));
      final silent = await run('grep -s foo missing.txt');
      expect(silent['exit_code'], 2);
      expect(silent['stderr'], isEmpty);
      final directory = await run('grep foo lib');
      expect(directory['exit_code'], 2);
    });
  });

  group('recursion stays inside the searched tree', () {
    test('skips symlinks met during recursion', () async {
      final outside = await Directory.systemTemp.createTemp('grep_outside_');
      addTearDown(() => outside.delete(recursive: true));
      File('${outside.path}/secret.txt').writeAsStringSync('needle\n');
      try {
        await Link('${root.path}/lib/escape').create(outside.path);
        await Link(
          '${root.path}/lib/escape.txt',
        ).create('${outside.path}/secret.txt');
      } on FileSystemException {
        markTestSkipped('Symbolic links are unavailable on this platform.');
        return;
      }

      await expectGrep('grep -r needle lib', '', exitCode: 1);
    });
  });

  group('falls back to the shell path', () {
    test('for forms it cannot reproduce', () {
      for (final command in [
        'grep needle',
        'grep -R needle lib',
        'grep -P x lib/a.dart',
        'grep -f patterns.txt lib/a.dart',
        'grep --binary-files=text x lib/a.dart',
        'grep -z x lib/a.dart',
        r"grep '\d' lib/sub/b.txt",
        r"grep '\<foo\>' lib/a.dart",
        r"grep 'a\(b\)\1' lib/sub/b.txt",
        "grep -E '(?:a)' lib/sub/b.txt",
        "grep '[[=a=]]' lib/sub/b.txt",
        'grep -r --include=*.{dart,txt} foo lib',
        'grep foo -',
      ]) {
        expect(LocalShellTools.isReadOnly(command), isFalse, reason: command);
      }
    });

    test('for words the shell would expand differently', () {
      for (final command in [
        'grep foo lib/*.dart',
        'grep foo lib/[ab].dart',
        'grep foo ~/notes.txt',
        r'grep foo\.bar lib/a.dart',
        "grep '' lib/a.dart lib/sub/b.txt",
        'grep "a\\"b" lib/a.dart',
      ]) {
        expect(LocalShellTools.isReadOnly(command), isFalse, reason: command);
      }
      // A glob inside an option word is grep's to interpret, not the shell's.
      expect(
        LocalShellTools.isReadOnly('grep -rn --include=*.dart foo lib'),
        isTrue,
      );
    });

    test('for patterns Dart would backtrack on exponentially', () {
      for (final command in [
        "grep -E '(a+)+\$' lib/sub/b.txt",
        "grep -E '(a|aa)*b' lib/sub/b.txt",
        r"grep '\(a*\)*b' lib/sub/b.txt",
        "grep -E '(ab?){2,}' lib/sub/b.txt",
      ]) {
        expect(LocalShellTools.isReadOnly(command), isFalse, reason: command);
      }
    });
  });

  group('pattern translation', () {
    test('maps basic syntax onto Dart', () {
      expect(LocalShellGrep.translatePattern(r'a\|b', extended: false), 'a|b');
      expect(LocalShellGrep.translatePattern('a|b', extended: false), r'a\|b');
      expect(
        LocalShellGrep.translatePattern(r'\(ab\)\{2\}', extended: false),
        '(ab){2}',
      );
      expect(LocalShellGrep.translatePattern('*a', extended: false), r'\*a');
      expect(
        LocalShellGrep.translatePattern(r'a^b$', extended: false),
        r'a\^b$',
      );
    });

    test('maps extended syntax and bracket classes onto Dart', () {
      expect(
        LocalShellGrep.translatePattern('[[:alpha:]_]+', extended: true),
        '[A-Za-z_]+',
      );
      expect(
        LocalShellGrep.translatePattern(r'[\.]', extended: true),
        r'[\\.]',
      );
      expect(
        LocalShellGrep.translatePattern('a{,2}', extended: true),
        'a{0,2}',
      );
      expect(LocalShellGrep.translatePattern('a{x', extended: true), r'a\{x');
      expect(LocalShellGrep.translatePattern('a*?', extended: true), isNull);
    });

    test('flags only nested repetition', () {
      expect(LocalShellGrep.hasNestedQuantifier('(a+)+'), isTrue);
      expect(LocalShellGrep.hasNestedQuantifier('(a|b)*'), isTrue);
      expect(LocalShellGrep.hasNestedQuantifier('(ab)+c*'), isFalse);
      expect(LocalShellGrep.hasNestedQuantifier('(a+)?'), isFalse);
      expect(LocalShellGrep.hasNestedQuantifier(r'[(+]+\(a+\)+'), isFalse);
    });
  });
}
