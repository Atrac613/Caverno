import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/last_message_edit.dart';
import 'package:flutter_test/flutter_test.dart';

Message _message(String id, String content) => Message(
  id: id,
  content: content,
  role: MessageRole.assistant,
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
}
