import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/truncation_notice.dart';

void main() {
  group('TruncationNotice.withMaxTokenNotice', () {
    test('appends the notice to a non-empty answer', () {
      final out = TruncationNotice.withMaxTokenNotice('partial answer');
      expect(out, startsWith('partial answer'));
      expect(out, contains(TruncationNotice.maxTokenNotice));
      expect(out, contains('continue from the last verified point'));
      expect(out, isNot(contains('Increase Max Tokens')));
    });

    test('is idempotent (does not duplicate the notice)', () {
      final once = TruncationNotice.withMaxTokenNotice('x');
      final twice = TruncationNotice.withMaxTokenNotice(once);
      expect(once, twice);
      expect(TruncationNotice.maxTokenNotice.allMatches(twice).length, 1);
    });

    test('returns just the notice for empty/whitespace content', () {
      expect(
        TruncationNotice.withMaxTokenNotice(''),
        TruncationNotice.maxTokenNotice,
      );
      expect(
        TruncationNotice.withMaxTokenNotice('   \n'),
        TruncationNotice.maxTokenNotice,
      );
    });

    test('trims trailing whitespace before appending', () {
      final out = TruncationNotice.withMaxTokenNotice('answer\n\n  ');
      expect(out, 'answer\n\n${TruncationNotice.maxTokenNotice}');
    });
  });
}
