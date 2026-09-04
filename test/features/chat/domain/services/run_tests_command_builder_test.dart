import 'dart:io';

import 'package:caverno/features/chat/domain/services/run_tests_command_builder.dart';
import 'package:test/test.dart';

/// These were private methods inside the ChatNotifier library and were only
/// reachable through a full `run_tests` tool call. Outside it they can be
/// asserted directly, which is most of the reason the extraction was worth
/// doing: the path rewriting below is the part that silently produces a
/// command that runs the wrong tests.
void main() {
  group('normalizeRunner', () {
    test('accepts the three it knows and rejects the rest', () {
      expect(RunTestsCommandBuilder.normalizeRunner(null), 'auto');
      expect(RunTestsCommandBuilder.normalizeRunner('  '), 'auto');
      expect(RunTestsCommandBuilder.normalizeRunner('AUTO'), 'auto');
      expect(RunTestsCommandBuilder.normalizeRunner('Flutter'), 'flutter');
      expect(RunTestsCommandBuilder.normalizeRunner('dart'), 'dart');
      expect(
        RunTestsCommandBuilder.normalizeRunner('pytest'),
        isNull,
        reason: 'null is the signal to reject the call, not a default.',
      );
    });
  });

  group('normalizePathForWorkingDirectory', () {
    String rewrite(String path) =>
        RunTestsCommandBuilder.normalizePathForWorkingDirectory(
          path,
          projectRoot: '/repo',
          workingDirectory: '/repo/packages/app',
        );

    test(
      'drops the working directory prefix a project-relative path repeats',
      () {
        expect(
          rewrite('packages/app/test/widget_test.dart'),
          'test/widget_test.dart',
        );
      },
    );

    test('answers "." when the path is the working directory itself', () {
      expect(rewrite('packages/app'), '.');
    });

    test('leaves a path that does not start inside the working directory', () {
      expect(rewrite('packages/other/test'), 'packages/other/test');
    });

    test('leaves absolute paths alone, POSIX and Windows alike', () {
      expect(rewrite('/repo/packages/app/test'), '/repo/packages/app/test');
      expect(rewrite(r'C:\repo\test'), r'C:\repo\test');
    });

    test('passes the path through when the package is the project root', () {
      expect(
        RunTestsCommandBuilder.normalizePathForWorkingDirectory(
          'test/widget_test.dart',
          projectRoot: '/repo',
          workingDirectory: '/repo',
        ),
        'test/widget_test.dart',
      );
    });
  });

  group('shellQuoteArgument', () {
    test('quotes, and closes the quote around an embedded one', () {
      expect(
        RunTestsCommandBuilder.shellQuoteArgument('test/a b.dart'),
        "'test/a b.dart'",
      );
      expect(RunTestsCommandBuilder.shellQuoteArgument(''), "''");
      expect(
        RunTestsCommandBuilder.shellQuoteArgument("it's.dart"),
        """'it'"'"'s.dart'""",
        reason:
            'A single quote cannot be escaped inside single quotes, so the '
            'quote has to be closed and reopened around it.',
      );
    });
  });

  group('normalizeAbsolutePath', () {
    test('collapses traversal and keeps unparseable input as written', () {
      expect(RunTestsCommandBuilder.normalizeAbsolutePath('  '), '');
      expect(
        RunTestsCommandBuilder.normalizeAbsolutePath('/repo/packages/../app'),
        '/repo/app',
      );
    });
  });

  group('buildCommand', () {
    late Directory root;

    setUp(
      () => root = Directory.systemTemp.createTempSync('run_tests_builder'),
    );
    tearDown(() => root.deleteSync(recursive: true));

    test('infers flutter from the package pubspec and quotes the path', () {
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );

      expect(
        RunTestsCommandBuilder.buildCommand(
          runner: 'auto',
          projectRoot: root.path,
          workingDirectory: root.path,
          testPath: 'test/a b.dart',
        ),
        "flutter test 'test/a b.dart'",
      );
    });

    test('falls back to dart for a package with no flutter dependency', () {
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: tool\n');

      expect(
        RunTestsCommandBuilder.buildCommand(
          runner: 'auto',
          projectRoot: root.path,
          workingDirectory: root.path,
        ),
        'dart test',
      );
    });

    test('an explicit runner is not second-guessed by the file system', () {
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );

      expect(
        RunTestsCommandBuilder.buildCommand(
          runner: 'dart',
          projectRoot: root.path,
          workingDirectory: root.path,
        ),
        'dart test',
      );
    });

    test('an empty test path adds no argument', () {
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: tool\n');

      expect(
        RunTestsCommandBuilder.buildCommand(
          runner: 'dart',
          projectRoot: root.path,
          workingDirectory: root.path,
          testPath: '   ',
        ),
        'dart test',
      );
    });
  });
}
