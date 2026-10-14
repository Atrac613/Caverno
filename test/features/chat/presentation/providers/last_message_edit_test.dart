import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/last_message_edit.dart';
import 'package:flutter_test/flutter_test.dart';

Message _message(
  String id,
  String content, {
  MessageRole role = MessageRole.assistant,
}) => Message(
  id: id,
  content: content,
  role: role,
  timestamp: DateTime.utc(2026, 10, 14),
);

void main() {
  test('rewrites only the last message, in a new list', () {
    final messages = [_message('a', 'first'), _message('b', 'second')];

    final updated = LastMessageEdit.withContent(messages, 'rewritten')!;

    expect(updated.map((message) => message.content), ['first', 'rewritten']);
    expect(updated.last.id, 'b');
    expect(messages.last.content, 'second');
  });

  test('has nothing to rewrite in an absent or empty list', () {
    expect(LastMessageEdit.withContent(null, 'x'), isNull);
    expect(LastMessageEdit.withContent(const [], 'x'), isNull);
  });

  group('withoutToolArtifacts', () {
    test('strips tool tags from the last assistant message', () {
      final updated = LastMessageEdit.withoutToolArtifacts([
        _message('u', 'Read it', role: MessageRole.user),
        _message(
          'a',
          'Reading.\n<tool_use>{"name":"read_file","arguments":{}}</tool_use>',
        ),
      ])!;
      expect(updated, hasLength(2));
      expect(updated.last.content.trim(), 'Reading.');
    });

    test('drops a last message left with nothing in it', () {
      final updated = LastMessageEdit.withoutToolArtifacts([
        _message('u', 'Read it', role: MessageRole.user),
        _message(
          'a',
          '<tool_use>{"name":"read_file","arguments":{}}</tool_use>',
        ),
      ])!;
      expect(updated.map((message) => message.id), ['u']);
    });

    test('leaves a list whose last message is not the assistant alone', () {
      expect(
        LastMessageEdit.withoutToolArtifacts([
          _message('u', 'hi', role: MessageRole.user),
        ]),
        isNull,
      );
      expect(LastMessageEdit.withoutToolArtifacts(const []), isNull);
    });
  });
}
