import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_default_title.dart';
import 'package:flutter_test/flutter_test.dart';

Message _user(String content) => Message(
  id: content.hashCode.toString(),
  content: content,
  role: MessageRole.user,
  timestamp: DateTime(2026, 9, 1),
);

void main() {
  group('subjectOf', () {
    test('is the message itself when nothing is attached', () {
      expect(
        ConversationDefaultTitle.subjectOf('  What changed?  '),
        'What changed?',
      );
    });

    test('is the question in front of an attachment header', () {
      expect(
        ConversationDefaultTitle.subjectOf(
          'これは何？\n\n[File: rules.pdf (PDF, 20 pages, 1.0 MB)]',
        ),
        'これは何？',
      );
    });

    test('is the file when the person sent no question', () {
      expect(
        ConversationDefaultTitle.subjectOf('[File: rules.pdf (1.0 MB)]'),
        'rules.pdf (1.0 MB)',
      );
    });

    test('leaves a header that is not at the end alone', () {
      // A message from before the visible/model split put the header first and
      // inlined the file under it; there is no question to lift out.
      const legacy = '[File: notes.txt]\nalpha\n\nWhat is this?';

      expect(ConversationDefaultTitle.subjectOf(legacy), legacy);
    });
  });

  group('deriveFrom', () {
    test('uses the first user message', () {
      final title = ConversationDefaultTitle.deriveFrom([
        Message(
          id: 'system',
          content: 'ignored',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 9, 1),
        ),
        _user('First question'),
        _user('Second question'),
      ]);

      expect(title, 'First question');
    });

    test('skips a user message with nothing in it', () {
      expect(ConversationDefaultTitle.deriveFrom([_user('   '), _user('Hi')]), 'Hi');
    });

    test('elides past the drawer width', () {
      final title = ConversationDefaultTitle.deriveFrom([_user('x' * 40)]);

      expect(title, '${'x' * ConversationDefaultTitle.maxLength}...');
    });

    test('is null when nobody has spoken', () {
      expect(ConversationDefaultTitle.deriveFrom(const []), isNull);
    });
  });
}
