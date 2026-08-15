import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/ask_user_question_option_parser.dart';

const _parser = AskUserQuestionOptionParser();

void main() {
  group('parse', () {
    test('accepts bare strings and maps in one list', () {
      final options = _parser.parse([
        'Keep going',
        {'id': 'stop-now', 'label': 'Stop', 'description': 'End the turn'},
      ]);

      expect(options.map((o) => o.id), ['keep-going', 'stop-now']);
      expect(options.map((o) => o.label), ['Keep going', 'Stop']);
      expect(options.last.description, 'End the turn');
    });

    test('gives repeated labels distinct ids', () {
      // Two rows resolving to the same id would make the answer ambiguous.
      final options = _parser.parse(['Retry', 'Retry', 'Retry']);

      expect(options.map((o) => o.id), ['retry', 'retry-2', 'retry-3']);
    });

    test('drops entries that cannot become an option', () {
      final options = _parser.parse([
        '   ',
        {'label': ''},
        42,
        null,
        'Usable',
      ]);

      expect(options.map((o) => o.label), ['Usable']);
    });

    test('stops at the maximum and returns empty for a non-list', () {
      expect(
        _parser.parse(List.generate(20, (i) => 'Option $i')),
        hasLength(AskUserQuestionOptionParser.maxOptions),
      );
      expect(_parser.parse('not a list'), isEmpty);
      expect(_parser.parse(null), isEmpty);
    });

    test('bounds each field so the sheet stays on screen', () {
      final options = _parser.parse([
        {'label': 'L' * 400, 'description': 'D' * 900, 'preview': 'P' * 4000},
      ]);

      final option = options.single;
      expect(option.label.length, 120);
      expect(option.description.length, 500);
      expect(option.preview.length, 2000);
      expect(option.label, endsWith('...'));
    });
  });

  group('optionId', () {
    test('slugs the label and falls back to the position', () {
      expect(_parser.optionId('Run  the Tests!', 0), 'run-the-tests');
      expect(_parser.optionId('***', 2), 'option-3');
      expect(_parser.optionId('x' * 80, 0).length, 40);
    });
  });

  group('clip', () {
    test('trims, and only truncates past the limit', () {
      expect(_parser.clip('  kept  ', 10), 'kept');
      expect(_parser.clip('abcdefghij', 10), 'abcdefghij');
      expect(_parser.clip('abcdefghijk', 10), 'abcdefg...');
    });
  });
}
