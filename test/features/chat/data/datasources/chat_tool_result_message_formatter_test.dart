import 'package:caverno/features/chat/data/datasources/chat_tool_result_message_formatter.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:openai_dart/openai_dart.dart';
import 'package:test/test.dart';

const _formatter = ChatToolResultMessageFormatter();

ToolResultInfo _result(String id, {bool fromEarlierLoop = false}) =>
    ToolResultInfo(
      id: id,
      name: 'read_file',
      arguments: {'path': '$id.dart'},
      result: '{"path":"$id.dart","content":"x"}',
      fromEarlierLoop: fromEarlierLoop,
    );

/// "role|toolCallIds|assistantContent" per message. A string rather than a
/// record because a record holding a List compares that List by identity.
List<String> _shape(List<ChatMessage> messages) => messages.map((message) {
  if (message is AssistantMessage) {
    final ids = (message.toolCalls ?? const <ToolCall>[])
        .map((call) => call.id)
        .join(',');
    return 'assistant|$ids|${message.content}';
  }
  if (message is ToolMessage) return 'tool|${message.toolCallId}|';
  return 'other||';
}).toList();

void main() {
  group('appendToolExchange', () {
    test('keeps one batch as a single exchange', () {
      final messages = <ChatMessage>[];

      _formatter.appendToolExchange(
        messages,
        toolResults: [_result('a'), _result('b')],
        assistantContent: 'working',
      );

      expect(_shape(messages), ['assistant|a,b|working', 'tool|a|', 'tool|b|']);
    });

    test('gives each re-sent result its own earlier exchange', () {
      final messages = <ChatMessage>[];

      _formatter.appendToolExchange(
        messages,
        toolResults: [
          _result('old-1', fromEarlierLoop: true),
          _result('old-2', fromEarlierLoop: true),
          _result('now'),
        ],
        assistantContent: 'working',
      );

      // Merged into one turn, three results read as three tools that just
      // returned together, and the model re-analyses all of them every
      // request. Session 95631b24 measured 9,977 characters of reasoning at
      // six carried results, to emit one tool call.
      expect(_shape(messages), [
        'assistant|old-1|',
        'tool|old-1|',
        'assistant|old-2|',
        'tool|old-2|',
        'assistant|now|working',
        'tool|now|',
      ]);
    });

    test('keeps the assistant content on the current turn only', () {
      final messages = <ChatMessage>[];

      _formatter.appendToolExchange(
        messages,
        toolResults: [_result('old', fromEarlierLoop: true), _result('now')],
        assistantContent: 'the digest and the visible text',
      );

      final contents = _shape(messages)
          .where((entry) => entry.startsWith('assistant|'))
          .map((entry) => entry.split('|').last)
          .toList();
      expect(contents, ['', 'the digest and the visible text']);
    });

    test('still emits the assistant turn when every result is re-sent', () {
      final messages = <ChatMessage>[];

      // A batch can be empty after a skip, and the turn's text still has to
      // reach the model.
      _formatter.appendToolExchange(
        messages,
        toolResults: [_result('old', fromEarlierLoop: true)],
        assistantContent: 'nothing ran this time',
      );

      expect(_shape(messages), [
        'assistant|old|',
        'tool|old|',
        'assistant||nothing ran this time',
      ]);
    });
  });
}
