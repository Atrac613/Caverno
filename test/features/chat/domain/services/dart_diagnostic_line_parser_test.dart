import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/dart_diagnostic_line_parser.dart';

const _parser = DartDiagnosticLineParser();
const _root = '/work/project';

void main() {
  group('machine format', () {
    test(
      'reads the pipe-delimited fields dart analyze --format=machine emits',
      () {
        final diagnostic = _parser.parse(
          'ERROR|COMPILE_TIME_ERROR|UNDEFINED_METHOD|'
          '/work/project/lib/main.dart|12|7|9|The method is not defined.',
          pathBase: _root,
        );

        expect(diagnostic, isNotNull);
        expect(diagnostic!.severity, 'Error');
        expect(diagnostic.absolutePath, '/work/project/lib/main.dart');
        expect(diagnostic.line, 12);
        expect(diagnostic.column, 7);
        expect(diagnostic.code, 'UNDEFINED_METHOD');
        expect(diagnostic.message, 'The method is not defined.');
      },
    );

    test('rejects a line with too few fields', () {
      expect(
        _parser.parse(
          'ERROR|COMPILE_TIME_ERROR|X|/a.dart|1|1',
          pathBase: _root,
        ),
        isNull,
      );
    });

    test('rejects an unknown severity', () {
      expect(
        _parser.parse(
          'BANANA|COMPILE_TIME_ERROR|X|/work/project/a.dart|1|1|1|m',
          pathBase: _root,
        ),
        isNull,
      );
    });
  });

  group('human format', () {
    test('reads the default dart analyze line', () {
      final diagnostic = _parser.parse(
        '  error - lib/main.dart:12:7 - The method is not defined. - undefined_method',
        pathBase: _root,
      );

      expect(diagnostic, isNotNull);
      expect(diagnostic!.severity, 'Error');
      expect(diagnostic.line, 12);
      expect(diagnostic.column, 7);
      expect(diagnostic.absolutePath, contains('lib/main.dart'));
    });
  });

  group('lines that must not parse', () {
    test('leaves ordinary output alone', () {
      // The parser is walked over every line of a command's output, so
      // anything it accepts loosely becomes a phantom error in the evidence.
      for (final line in const [
        '',
        'Analyzing project...',
        'No issues found!',
        '00:02 +14: All tests passed!',
        'Building package executable...',
        'error: something went wrong',
        'lib/main.dart',
        '| | | | | | | |',
      ]) {
        expect(_parser.parse(line, pathBase: _root), isNull, reason: line);
      }
    });
  });
}
