import 'package:caverno/features/chat/domain/services/anabasis_address.dart';
import 'package:test/test.dart';

void main() {
  group('addressed', () {
    test('at the start, in either case, with or without punctuation', () {
      for (final content in [
        '@anabasis plan the migration',
        '@Anabasis plan the migration',
        '  @anabasis plan the migration',
        '@anabasis: plan the migration',
        '@anabasis、移行を計画して',
        '@anabasis',
      ]) {
        expect(AnabasisAddress.isAddressed(content), isTrue, reason: content);
      }
    });
  });

  group('not addressed', () {
    test('a message that only mentions the parent is not one to it', () {
      for (final content in [
        'ask @anabasis about the migration',
        'what does @anabasis do?',
        '@anabasistown is not a place',
        'anabasis plan the migration',
        '',
      ]) {
        expect(AnabasisAddress.isAddressed(content), isFalse, reason: content);
      }
    });
  });
}
