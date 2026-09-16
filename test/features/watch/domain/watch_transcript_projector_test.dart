import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/watch/domain/watch_snapshot.dart';
import 'package:caverno/features/watch/domain/watch_transcript_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const projector = WatchTranscriptProjector();

  Message message(
    String id,
    MessageRole role,
    String content, {
    bool isStreaming = false,
    bool isSynthesizedPrompt = false,
  }) => Message(
    id: id,
    role: role,
    content: content,
    timestamp: DateTime.utc(2026, 9, 16),
    isStreaming: isStreaming,
    isSynthesizedPrompt: isSynthesizedPrompt,
  );

  test('keeps human and assistant prose while removing internal traffic', () {
    final projection = projector.project([
      message('system', MessageRole.system, 'Hidden instructions'),
      message('user', MessageRole.user, 'Run the tests'),
      message(
        'tool-result',
        MessageRole.user,
        '<tool_result>{"ok":true}</tool_result>',
        isSynthesizedPrompt: true,
      ),
      message(
        'assistant',
        MessageRole.assistant,
        '<think>private reasoning</think>All green.'
            '<tool_call>{"name":"run_tests"}</tool_call>',
      ),
      message(
        'tool-only',
        MessageRole.assistant,
        '<tool_use>{"name":"read_file"}</tool_use>',
      ),
      message(
        'synthesized-assistant',
        MessageRole.assistant,
        'Internal recovery text',
        isSynthesizedPrompt: true,
      ),
    ]);

    expect(projection.messages.map((item) => item.id), ['user', 'assistant']);
    expect(projection.messages.last.text, 'All green.');
    expect(projection.lastAssistantText, 'All green.');
    expect(projection.messagesTruncated, isFalse);
  });

  test('keeps an empty streaming bubble as a compact working state', () {
    final projection = projector.project([
      message('user', MessageRole.user, 'Continue'),
      message('assistant', MessageRole.assistant, '', isStreaming: true),
    ]);

    expect(projection.messages.last.id, 'assistant');
    expect(projection.messages.last.isStreaming, isTrue);
    expect(projection.lastAssistantText, isEmpty);
  });

  test('keeps the newest bounded history and marks earlier messages', () {
    final projection = projector.project([
      for (var index = 0; index < watchSnapshotMaxMessages + 3; index += 1)
        message('m-$index', MessageRole.user, 'Message $index'),
    ]);

    expect(projection.messages, hasLength(watchSnapshotMaxMessages));
    expect(projection.messages.first.id, 'm-3');
    expect(projection.messages.last.id, 'm-10');
    expect(projection.messagesTruncated, isTrue);
  });
}
